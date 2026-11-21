"""송도 맛집 자료 수집기

매일 새벽 깃허브 자동 실행으로 돌아간다.
1) 카카오 지도 검색으로 송도 일대 음식점 목록을 모은다.
2) 가게마다 블로그(네이버 열쇠가 있으면 네이버, 없으면 다음)를 검색해 최근 90일 언급 수를 센다 (광고 의심 글은 따로 센다).
3) 블로그 화제 상위 가게만 유튜브 영상을 찾는다 (하루 사용량 한도 때문).
4) 화제 점수를 매겨 web/data/songdo.json 으로 저장한다.

필요한 열쇠(깃허브 비밀값): KAKAO_REST_KEY (필수), YOUTUBE_KEY·NAVER_CLIENT_ID·NAVER_CLIENT_SECRET (없어도 됨)
"""

import datetime as dt
import html
import json
import math
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

# 지금 모으는 동네 (run_all이 regions.json의 동네마다 바꿔 끼운다)
# 범위: (서쪽 경도, 남쪽 위도, 동쪽 경도, 북쪽 위도)
AREA = (126.590, 37.355, 126.705, 37.445)  # 송도국제도시 + 송도유원지·동춘동 쪽까지
AREA_NAME = "송도"      # 검색어 앞에 붙이는 동네 이름
AREA_ID = "songdo"
AREA_LABEL = "송도/연수"
EXTRA_Q = []            # 그 동네만의 검색어 (통째로 검색)
NEW_AREA = False        # 처음 여는 동네면 구글 조회를 한 번에 더 많이
REGIONS = os.path.join(os.path.dirname(__file__), "..", "web", "data", "regions.json")
GOOGLE_PER_AREA = 150   # 동네마다 구글로 확인하는 후보 상한 (블로그·인기 상위부터)
GOOGLE_NEW_MAX = 160    # 처음 여는 동네는 한 번에 이만큼까지
RECENT_DAYS = 90
YOUTUBE_TOP = int(os.environ.get("YOUTUBE_TOP", "25"))  # 종류별 유튜브 확인 수
TOP_N = int(os.environ.get("TOP_N", "20"))  # 종류별로 앱에 남기는 수
KINDS = [("food", "FD6", "맛집"), ("cafe", "CE7", "카페")]
DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "web", "data")
OUT = os.path.join(DATA_DIR, "songdo.json")

AD_WORDS = ["협찬", "체험단", "원고료", "소정의", "제공받", "지원받", "광고", "업체로부터", "서포터즈", "무료로 제공"]

KAKAO_KEY = os.environ.get("KAKAO_REST_KEY", "").strip()
NAVER_ID = os.environ.get("NAVER_CLIENT_ID", "").strip()
NAVER_SECRET = os.environ.get("NAVER_CLIENT_SECRET", "").strip()
YOUTUBE_KEY = os.environ.get("YOUTUBE_KEY", "").strip()
# 구글 지도(별점·리뷰 수) 열쇠 — 따로 없으면 유튜브 열쇠를 같이 쓴다
GOOGLE_KEY = (os.environ.get("GOOGLE_KEY", "") or YOUTUBE_KEY).strip()
GOOGLE_MAX = int(os.environ.get("GOOGLE_MAX", "30"))   # 하루 새로 조회하는 최대 수 (무료 범위 유지)
GOOGLE_DAYS = int(os.environ.get("GOOGLE_DAYS", "90"))  # 순위 밖 가게: 석 달마다 갱신
GOOGLE_DAYS_TOP = 30   # 순위권 가게: 한 달마다 갱신
BLOG_DAYS = 14         # 1차 블로그 건수는 2주마다 새로 (무료)
GOOGLE_MONTH = 900     # 한 달 구글 조회 상한 (무료 1,000회 안쪽)
USAGE = os.path.join(os.path.dirname(__file__), "google_usage.json")
TV_CACHE = os.path.join(os.path.dirname(__file__), "tv_cache.json")   # 방송 출연 확인 결과
TV_DAYS = 30           # 방송 출연은 한 달마다 다시 확인 (무료)
MIN_REVIEWS = int(os.environ.get("MIN_REVIEWS", "30"))  # 구글 리뷰가 이보다 적으면 순위 제외
CACHE = os.path.join(os.path.dirname(__file__), "..", "web", "data", "google_cache.json")
PLACES_CACHE = os.path.join(os.path.dirname(__file__), "places_cache.json")  # 가게 목록 (7일마다 새로)
BLOG_CACHE = os.path.join(os.path.dirname(__file__), "blog_cache.json")      # 1차 블로그 건수 (14일마다 새로)


def load_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def save_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))


class KakaoDown(Exception):
    """카카오가 계속 응답하지 않음 → 이번 수집은 멈추고 기존 자료를 그대로 둔다."""


KAKAO_FAILS = [0]   # 카카오 연속 실패 수
BLOG_UP = [True]    # 블로그 검색이 되는지 (안 되면 지난 글을 그대로 씀)
KAKAO_LIMIT = 4     # 연속 4번 실패하면 카카오가 멈춘 것으로 본다


def check_kakao():
    if KAKAO_FAILS[0] >= KAKAO_LIMIT:
        raise KakaoDown()


def get_json(url, headers=None, tries=3):
    kakao = "kakao.com" in url
    if kakao and KAKAO_FAILS[0] >= KAKAO_LIMIT:
        raise KakaoDown()   # 이미 멈춘 것으로 확인됨: 기다리지 않고 바로 포기
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=headers or {})
            with urllib.request.urlopen(req, timeout=10) as r:
                out = json.loads(r.read().decode("utf-8"))
            if kakao:
                KAKAO_FAILS[0] = 0
            return out
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "ignore")[:300]
            if e.code in (429, 500, 502, 503) and i < tries - 1:
                time.sleep(2 + i * 2)
                continue
            if kakao and e.code in (429, 500, 502, 503):
                KAKAO_FAILS[0] += 1
            raise RuntimeError(f"{e.code} {url[:80]} {body}")
        except Exception:
            if i < tries - 1:
                time.sleep(2 + i * 2)
                continue
            if kakao:
                KAKAO_FAILS[0] += 1
            raise


def post_json(url, body, headers):
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json", **headers}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code} {e.read().decode('utf-8', 'ignore')[:300]}")


def dist_m(lat1, lng1, lat2, lng2):
    dy = (lat1 - lat2) * 111000
    dx = (lng1 - lng2) * 88000
    return (dx * dx + dy * dy) ** 0.5


def google_lookup(p):
    """구글 지도에서 같은 가게를 찾아 별점·리뷰 수를 받는다 (300m 안, 이름 일부 일치)."""
    lat, lng = float(p["y"]), float(p["x"])
    body = {
        "textQuery": f'{p["place_name"]} {p.get("road_address_name") or p.get("address_name") or ""}',
        "languageCode": "ko", "regionCode": "KR", "maxResultCount": 3,
        "locationBias": {"circle": {"center": {"latitude": lat, "longitude": lng}, "radius": 300.0}},
    }
    res = post_json("https://places.googleapis.com/v1/places:searchText", body, {
        "X-Goog-Api-Key": GOOGLE_KEY,
        # 영업시간·영업 상태는 별점과 같은 등급. 주차·애견 동반 같은 편의 정보는 한 단계 위 등급이지만
        # 그 등급도 한 달 1,000번까지 무료라, 한 달 900번 상한 안에서는 비용이 없다
        "X-Goog-FieldMask": "places.id,places.displayName,places.rating,places.userRatingCount,places.location,"
                            "places.googleMapsUri,places.regularOpeningHours,places.businessStatus,"
                            "places.parkingOptions,places.allowsDogs,places.goodForChildren,places.reservable,"
                            "places.outdoorSeating,places.takeout,places.delivery,places.goodForGroups,places.accessibilityOptions,"
                            "places.websiteUri",  # 같은 등급 — 가게 홈페이지(인스타 계정을 적어 둔 가게가 많다)
    })
    key = norm(base_name(p["place_name"]))
    for g in res.get("places", []):
        loc = g.get("location", {})
        if dist_m(lat, lng, loc.get("latitude", 0), loc.get("longitude", 0)) > 300:
            continue
        gname = norm((g.get("displayName") or {}).get("text", ""))
        if key[:3] not in gname and gname[:3] not in key:
            continue
        out = {"r": g.get("rating", 0), "n": g.get("userRatingCount", 0), "u": g.get("googleMapsUri", ""), "v": 4}
        if g.get("websiteUri"):
            out["web"] = g["websiteUri"]
        feat = []  # 편의 정보: 구글에 '있음'으로 등록된 것만
        if any(v is True for v in (g.get("parkingOptions") or {}).values()):
            feat.append("park")
        for field, code in (("allowsDogs", "dog"), ("goodForChildren", "kid"), ("reservable", "resv"),
                            ("outdoorSeating", "out"), ("takeout", "take"), ("delivery", "deliv"), ("goodForGroups", "group")):
            if g.get(field) is True:
                feat.append(code)
        if (g.get("accessibilityOptions") or {}).get("wheelchairAccessibleEntrance") is True:
            feat.append("wheel")
        if feat:
            out["f"] = feat
        bs = g.get("businessStatus", "")
        if bs and bs != "OPERATIONAL":
            out["bs"] = bs
        oh = g.get("regularOpeningHours") or {}
        per = []
        for pr in oh.get("periods", []):
            o, c = pr.get("open") or {}, pr.get("close")
            if not o:
                continue
            row = [o.get("day", 0), o.get("hour", 0) * 100 + o.get("minute", 0)]
            row += [c.get("day", 0), c.get("hour", 0) * 100 + c.get("minute", 0)] if c else [-1, -1]
            per.append(row)
        if per:
            out["h"] = per                                  # [여는 요일, 시각, 닫는 요일, 시각] (요일 0=일)
        if oh.get("weekdayDescriptions"):
            out["w"] = oh["weekdayDescriptions"]            # "월요일: 오전 11:00~오후 9:00" 같은 한국어 7줄
        return out
    return {"r": 0, "n": 0, "u": "", "v": 4}


# ---------- 1. 카카오: 음식점 목록 ----------

def kakao_rect(x1, y1, x2, y2, page, code="FD6"):
    q = urllib.parse.urlencode({
        "category_group_code": code,
        "rect": f"{x1},{y1},{x2},{y2}",
        "page": page,
        "size": 15,
    })
    return get_json("https://dapi.kakao.com/v2/local/search/category.json?" + q,
                    {"Authorization": f"KakaoAK {KAKAO_KEY}"})


def collect_places(code="FD6"):
    """송도 범위를 약 1km 칸으로 나누고, 한 칸에 45곳이 넘으면 4칸씩 3번까지 더 쪼갠다."""
    places = {}
    calls = [0]

    def fetch_all(x1, y1, x2, y2):
        docs, page = [], 1
        while True:
            res = kakao_rect(x1, y1, x2, y2, page, code)
            calls[0] += 1
            docs += res["documents"]
            if res["meta"]["is_end"] or page >= 3:
                return docs, res["meta"]["total_count"]
            page += 1

    def walk(x1, y1, x2, y2, depth):
        first = kakao_rect(x1, y1, x2, y2, 1, code)
        calls[0] += 1
        total = first["meta"]["total_count"]
        if total > 45 and depth < 3:
            mx, my = (x1 + x2) / 2, (y1 + y2) / 2
            for a in ((x1, y1, mx, my), (mx, y1, x2, my), (x1, my, mx, y2), (mx, my, x2, y2)):
                walk(*a, depth + 1)
            return
        docs, _ = fetch_all(x1, y1, x2, y2) if total > 15 else (first["documents"], total)
        for d in docs:
            places[d["id"]] = d

    x1, y1, x2, y2 = AREA
    step = 0.0125
    nx = round((x2 - x1) / step)
    ny = round((y2 - y1) / step)
    for i in range(nx):
        for j in range(ny):
            cx1, cy1 = x1 + i * step, y1 + j * step
            walk(round(cx1, 5), round(cy1, 5), round(cx1 + step, 5), round(cy1 + step, 5), 0)
        print(f"  지도 칸 {i + 1}/{nx} 완료 · 음식점 {len(places)}곳 · 호출 {calls[0]}회")
    return list(places.values())


# ---------- 2. 네이버 블로그 ----------

TAG = re.compile(r"<[^>]+>")


def clean(s):
    return html.unescape(TAG.sub("", s or "")).strip()


def norm(s):
    return re.sub(r"[\s\-·_()\[\]]", "", s or "").lower()


def base_name(name):
    # "○○ 송도점", "○○ 송도센트럴파크점" 처럼 지점명을 뗀다
    n = re.sub(r"\s+\S*점$", "", name.strip())
    return n if len(norm(n)) >= 2 else name.strip()


def naver_blog(query):
    q = urllib.parse.urlencode({"query": query, "display": 100, "sort": "date"})
    return get_json("https://openapi.naver.com/v1/search/blog.json?" + q, {
        "X-Naver-Client-Id": NAVER_ID,
        "X-Naver-Client-Secret": NAVER_SECRET,
    })


def kakao_blog(query, pages=2):
    """다음(카카오) 블로그 검색 — 네이버 블로그·티스토리 글도 함께 잡힌다. 네이버 검색과 같은 모양으로 바꿔 돌려준다."""
    items, ended = [], False
    for page in range(1, pages + 1):
        q = urllib.parse.urlencode({"query": query, "sort": "recency", "size": 50, "page": page})
        res = get_json("https://dapi.kakao.com/v2/search/blog?" + q, {"Authorization": f"KakaoAK {KAKAO_KEY}"})
        for d in res.get("documents", []):
            items.append({
                "title": d.get("title"),
                "description": d.get("contents"),
                "link": d.get("url"),
                "bloggername": d.get("blogname"),
                "postdate": (d.get("datetime") or "")[:10].replace("-", ""),
            })
        if res.get("meta", {}).get("is_end", True):
            ended = True
            break
        time.sleep(0.05)
    return {"items": items, "full": not ended}


# ---------- 방송 출연 확인: 다음(카카오) 블로그 글에서 방송 이름이 가게 이름 가까이 나오는지 본다 (무료) ----------

TV_SHOWS = [  # (띄어쓰기 없앤 검색어, 앱에 보일 이름)
    ("생활의달인", "생활의 달인"), ("수요미식회", "수요미식회"), ("맛있는녀석들", "맛있는 녀석들"),
    ("3대천왕", "백종원의 3대천왕"), ("골목식당", "백종원의 골목식당"), ("생생정보", "생생정보"),
    ("vj특공대", "VJ특공대"), ("6시내고향", "6시 내고향"), ("생방송투데이", "생방송 투데이"),
    ("생방송오늘저녁", "생방송 오늘 저녁"), ("생방송오늘아침", "생방송 오늘 아침"), ("전지적참견시점", "전지적 참견 시점"),
    ("나혼자산다", "나 혼자 산다"), ("줄서는식당", "줄 서는 식당"), ("토요일은밥이좋아", "토요일은 밥이 좋아"),
    ("토밥좋아", "토요일은 밥이 좋아"), ("백반기행", "식객 허영만의 백반기행"), ("서민갑부", "서민갑부"),
    ("놀라운토요일", "놀라운 토요일"), ("테이스티로드", "테이스티로드"), ("맛있는tv", "찾아라 맛있는 TV"),
    ("모닝와이드", "모닝와이드"), ("굿모닝대한민국", "굿모닝 대한민국"), ("먹거리x파일", "먹거리 X파일"),
    ("돈쭐내러왔습니다", "돈쭐내러 왔습니다"), ("동네한바퀴", "김영철의 동네 한 바퀴"), ("한국인의밥상", "한국인의 밥상"),
    # 요리 경연 (앱에서 「요리 경연 방송 코스」로 묶음 — 이름은 앱 kCookShows와 같게)
    ("흑백요리사", "흑백요리사"), ("한식대첩", "한식대첩"), ("마스터셰프", "마스터셰프 코리아"), ("냉장고를부탁해", "냉장고를 부탁해"),
]
TV_NEAR = 60   # 가게 이름과 방송 이름이 이 글자 수 안에 함께 나와야 인정


def tv_check(name):
    """블로그 글 2묶음(가게+방송 / 가게+출연)을 보고, 같은 방송이 글 2개 이상(또는 제목 1개)에서 나오면 출연으로 본다."""
    base = base_name(name)
    key = norm(base)
    if len(key) < 3:
        return []
    near, strong, seen = {}, set(), set()
    for word in ("방송", "출연"):
        q = urllib.parse.urlencode({"query": f"{base} {AREA_NAME} {word}", "sort": "accuracy", "size": 50})
        res = get_json("https://dapi.kakao.com/v2/search/blog?" + q, {"Authorization": f"KakaoAK {KAKAO_KEY}"})
        for d in res.get("documents", []):
            u = d.get("url") or ""
            if u in seen:
                continue
            seen.add(u)
            title = norm(clean(d.get("title")))
            text = title + "|" + norm(clean(d.get("contents")))
            spots = [m.start() for m in re.finditer(re.escape(key), text)]
            if not spots:
                continue
            for k, label in TV_SHOWS:
                if k in title and key in title:
                    strong.add(label)
                    continue
                for m in re.finditer(re.escape(k), text):
                    if any(abs(m.start() - sp) <= TV_NEAR for sp in spots):
                        near.setdefault(label, set()).add(u)
                        break
        time.sleep(0.05)
    found = [lb for lb in dict.fromkeys(list(strong) + [lb for lb, us in near.items() if len(us) >= 2])]
    return found[:2]


BIG_KEYS = ("대형카페", "초대형카페", "대형베이커리카페")


def big_check(name):
    """대형 카페: '대형카페'가 가게 이름 가까이 나오는 블로그 글이 2개 이상(또는 제목 1개)이면 인정."""
    base = base_name(name)
    key = norm(base)
    if len(key) < 3:
        return False
    q = urllib.parse.urlencode({"query": f"{base} 대형카페", "sort": "accuracy", "size": 50})
    res = get_json("https://dapi.kakao.com/v2/search/blog?" + q, {"Authorization": f"KakaoAK {KAKAO_KEY}"})
    near = 0
    for d in res.get("documents", []):
        title = norm(clean(d.get("title")))
        text = title + "|" + norm(clean(d.get("contents")))
        spots = [m.start() for m in re.finditer(re.escape(key), text)]
        if not spots:
            continue
        if key in title and any(k in title for k in BIG_KEYS):
            return True
        for k in BIG_KEYS:
            if any(abs(m.start() - sp) <= TV_NEAR for m in re.finditer(k, text) for sp in spots):
                near += 1
                break
    return near >= 2


VIEW_KEYS = ("오션뷰", "바다뷰", "공원뷰", "호수뷰", "시티뷰", "센트럴파크뷰", "뷰맛집", "뷰카페", "뷰가좋", "뷰좋은", "전망좋", "전망이좋", "야경")


def view_check(name):
    """뷰 맛집·오션뷰 카페: 전망 이야기가 가게 이름 가까이 나오는 글이 2개 이상(또는 제목 1개)."""
    base = base_name(name)
    key = norm(base)
    if len(key) < 3:
        return False
    q = urllib.parse.urlencode({"query": f"{base} {AREA_NAME} 뷰", "sort": "accuracy", "size": 50})
    res = get_json("https://dapi.kakao.com/v2/search/blog?" + q, {"Authorization": f"KakaoAK {KAKAO_KEY}"})
    near = 0
    for d in res.get("documents", []):
        title = norm(clean(d.get("title")))
        text = title + "|" + norm(clean(d.get("contents")))
        spots = [m.start() for m in re.finditer(re.escape(key), text)]
        if not spots:
            continue
        if key in title and any(k in title for k in VIEW_KEYS):
            return True
        for k in VIEW_KEYS:
            if any(abs(m.start() - sp) <= TV_NEAR for m in re.finditer(k, text) for sp in spots):
                near += 1
                break
    return near >= 2


def blog_home(url):
    """글 주소에서 블로그 첫 화면 주소를 뽑는다."""
    m = re.match(r"https?://(?:m\.)?blog\.naver\.com/([^/?#]+)", url or "")
    if m:
        return f"https://blog.naver.com/{m.group(1)}"
    m = re.match(r"(https?://[^/]+\.tistory\.com)", url or "")
    if m:
        return m.group(1)
    m = re.match(r"(https?://[^/]+)", url or "")
    return m.group(1) if m else ""


def branch_token(name, base):
    """지점 이름에서 구별 글자만 뽑는다. 예: 스타벅스 송도호반써밋점 → 호반써밋"""
    rest = name.strip()[len(base):].strip() if name.strip().startswith(base) else ""
    full = norm(rest)  # 예: 송도점
    rest = re.sub(r"(직영|본)?점$", "", rest)
    rest = re.sub(r"^(인천)?(송도)?", "", rest).strip()
    # 구별 글자가 없으면(송도점) 「송도점」이라는 말 자체를 요구한다
    return norm(rest) or full


def blog_stats(place, chain=False, pages=2):
    base = base_name(place["place_name"])
    key = norm(base)
    # 두 글자 이하 이름(봄, 숲, 정원…)은 엉뚱한 글이 너무 많이 잡혀 판단 불가 → 제외
    if len(key) < 3:
        return [], 0, 0, ""
    branch = branch_token(place["place_name"], base) if chain else ""
    if chain and len(branch) < 2:
        return [], 0, 0, ""
    query = f"{AREA_NAME} {base}"
    res = naver_blog(query) if (NAVER_ID and NAVER_SECRET) else kakao_blog(query, pages)
    since = (dt.date.today() - dt.timedelta(days=RECENT_DAYS)).strftime("%Y%m%d")
    clean_posts, ad_count, home = [], 0, ""
    for it in res.get("items", []):
        title, desc = clean(it.get("title")), clean(it.get("description"))
        # 블로그 이름에 가게 이름이 들어 있으면 가게가 직접 쓰는 블로그 → 바로가기로만 쓰고 점수에선 뺀다
        if len(key) >= 2 and key in norm(clean(it.get("bloggername"))):
            if not home:
                home = blog_home(it.get("link"))
            continue
        if key not in norm(title + desc):
            continue
        # 같은 상호 여러 지점이면 그 지점 이름이 글에 있어야 한다
        if branch and branch not in norm(title + desc):
            continue
        if (it.get("postdate") or "0") < since:
            continue
        text = title + " " + desc
        if any(w in text for w in AD_WORDS):
            ad_count += 1
            continue
        clean_posts.append({
            "t": title[:80],
            "d": desc[:120],
            "u": it.get("link"),
            "date": it.get("postdate"),
            "by": clean(it.get("bloggername"))[:30],
        })
    # 검색 결과가 꽉 찼고(50건) 가장 오래된 글도 90일 안이면, 실제로는 더 많다는 뜻 → 기간 비율로 추정
    items = res.get("items", [])
    est = len(clean_posts)
    if res.get("full", len(items) >= 50):
        dates = [i.get("postdate") for i in items if (i.get("postdate") or "").isdigit()]
        if dates and min(dates) >= since:
            oldest = dt.datetime.strptime(min(dates), "%Y%m%d").date()
            span = max((dt.date.today() - oldest).days, 3)
            est = round(len(clean_posts) * RECENT_DAYS / span)
    return clean_posts, ad_count, est, home


# ---------- 3. 유튜브 ----------

def youtube_videos(place):
    base = base_name(place["place_name"])
    key = norm(base)
    q = urllib.parse.urlencode({
        "part": "snippet", "q": f"{AREA_NAME} {base}", "type": "video",
        "maxResults": 8, "regionCode": "KR", "relevanceLanguage": "ko", "key": YOUTUBE_KEY,
    })
    res = get_json("https://www.googleapis.com/youtube/v3/search?" + q)
    vids = []
    for it in res.get("items", []):
        title = clean(it["snippet"]["title"])
        if key not in norm(title + it["snippet"].get("description", "")):
            continue
        vids.append({
            "id": it["id"]["videoId"],
            "t": title[:80],
            "ch": clean(it["snippet"].get("channelTitle"))[:30],
            "date": it["snippet"].get("publishedAt", "")[:10],
        })
    return vids[:4]


CHANNELS = os.path.join(os.path.dirname(__file__), "channels_cache.json")
SHORTS = os.path.join(os.path.dirname(__file__), "shorts_cache.json")  # 영상 id → 쇼츠(세로)인지 (바뀌지 않으니 한 번만)
INSTA = os.path.join(os.path.dirname(__file__), "insta_cache.json")    # 가게 id → 인스타 계정 주소 (홈페이지에서 찾은 것)
MANUAL = os.path.join(os.path.dirname(__file__), "manual.json")        # 관리자가 직접 넣는 값 {"insta": {"가게 이름 또는 id": "주소"}}

INSTA_RE = re.compile(r"instagram\.com/([A-Za-z0-9_.]{2,30})", re.I)
INSTA_SKIP = {"p", "reel", "reels", "explore", "accounts", "stories", "tv", "about", "developer", "legal", "direct", "web", "share", "sharer"}
NO_FETCH = ("naver.com", "naver.me", "kakao.com", "daum.net", "facebook.com", "youtube.com", "google.com", "goo.gl")


def insta_from(text):
    for m in INSTA_RE.finditer(text or ""):
        h = m.group(1).strip(".")
        if h.lower() not in INSTA_SKIP:
            return f"https://www.instagram.com/{h}/"
    return ""


def find_insta(web):
    """가게 홈페이지(구글에 등록된 주소)에서 인스타그램 계정 주소만 찾는다. 인스타 게시물·사진은 가져오지 않는다."""
    u = insta_from(web)
    if u or not web.startswith("http") or any(d in web for d in NO_FETCH):
        return u
    try:
        req = urllib.request.Request(web, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=8) as r:
            return insta_from(r.read(400000).decode("utf-8", "ignore"))
    except Exception:
        return ""


MODEL = os.path.join(os.path.dirname(__file__), "model_cache.json")  # 동네별 모범음식점 목록 (공공데이터, 30일마다)
DATA_KEY = os.environ.get("DATA_GO_KR_KEY", "")
SIDO_FULL = {"서울": "서울특별시", "부산": "부산광역시", "대구": "대구광역시", "인천": "인천광역시", "광주": "광주광역시",
             "대전": "대전광역시", "울산": "울산광역시", "세종": "세종특별자치시", "경기": "경기도", "강원": "강원특별자치도",
             "충북": "충청북도", "충남": "충청남도", "전북": "전북특별자치도", "전남": "전라남도", "경북": "경상북도",
             "경남": "경상남도", "제주": "제주특별자치도"}


def _road_key(addr):
    """도로명 주소에서 「○○로12번길 3」만 (시·도 표기가 달라도 맞춰 보려고)."""
    m = re.search(r"([가-힣0-9]+(?:로|길)(?:\s*\d+(?:번길|가길|길))?)\s*(\d+(?:-\d+)?)", addr or "")
    return (m.group(1).replace(" ", "") + " " + m.group(2)) if m else ""


def model_fill(all_out):
    """행정안전부 모범음식점 정보(공공데이터, 이용 제한 없음)와 맞춰 「○○구 지정 모범음식점」·주된 음식을 붙인다.
    인증키(DATA_GO_KR_KEY)가 없으면 건너뛴다. 목록은 동네(구)마다 30일에 한 번만 받는다."""
    if not DATA_KEY:
        print("모범음식점: 공공데이터 인증키가 없어 건너뜀")
        return
    key = urllib.parse.unquote(DATA_KEY)
    gus = {}
    for o in all_out:
        t = (o.get("addr") or "").split()
        if len(t) >= 2:
            gus.setdefault(f"{SIDO_FULL.get(t[0], t[0])} {t[1]}", 0)
            gus[f"{SIDO_FULL.get(t[0], t[0])} {t[1]}"] += 1
    if not gus:
        return
    gu = max(gus, key=gus.get)
    mc = load_json(MODEL, {})
    today = dt.date.today()
    hit = mc.get(gu)
    if not hit or (today - dt.date.fromisoformat(hit["d"])).days > 30:
        rows, page = [], 1
        try:
            while page <= 30:
                q = urllib.parse.urlencode({"serviceKey": key, "pageNo": page, "numOfRows": 100, "returnType": "json",
                                            "cond[ROAD_NM_ADDR::LIKE]": gu})
                res = get_json("https://apis.data.go.kr/1741000/excellent_restaurant_info?" + q)
                body = res.get("response", {}).get("body", res.get("body", {})) if isinstance(res, dict) else {}
                items = body.get("items", {})
                if isinstance(items, dict):
                    items = items.get("item", [])
                if isinstance(items, dict):
                    items = [items]
                if not items:
                    break
                for it in items:
                    name = it.get("BSNSSP_NM") or it.get("bsnsspNm") or ""
                    addr = it.get("ROAD_NM_ADDR") or it.get("roadNmAddr") or it.get("LOTNO_ADDR") or ""
                    food = it.get("PRINC_FD") or it.get("PRINC_FD_NM") or it.get("princFd") or ""
                    kind = it.get("PRINC_FD_KND") or it.get("princFdKnd") or ""
                    if name:
                        rows.append({"n": name, "a": addr, "f": food, "k": kind})
                total = int(body.get("totalCount", 0) or 0)
                if page * 100 >= total:
                    break
                page += 1
            mc[gu] = {"d": today.isoformat(), "rows": rows}
            save_json(MODEL, mc)
            print(f"모범음식점 목록 {gu}: {len(rows)}곳")
        except Exception as e:
            print("모범음식점 목록 받기 중단:", str(e)[:200])
            if not hit:
                return
    rows = (mc.get(gu) or {}).get("rows", [])
    by_road = {}
    for r in rows:
        by_road.setdefault(_road_key(r["a"]), []).append(r)
    gu_name = gu.split()[-1]
    n = 0
    for o in all_out:
        k = norm(base_name(o["name"]))
        cand = by_road.get(_road_key(o.get("addr", "")), [])
        # 같은 도로명 주소(건물 번호까지) + 이름 앞 두 글자가 같을 때만 (체인 다른 지점과 헷갈리지 않게)
        m = next((r for r in cand if k[:2] and k[:2] in norm(r["n"])), None)
        if m:
            o["model"] = f"{gu_name} 지정 모범음식점"
            if m.get("f") or m.get("k"):
                o["mfood"] = (m.get("f") or m.get("k"))[:30]
            n += 1
        else:
            o.pop("model", None)
            o.pop("mfood", None)
    print(f"모범음식점: {n}곳 맞춤")


FIX_KEYS = ("name", "tel", "addr", "lat", "lng", "cat", "hours", "week", "home", "insta")


def apply_fix(all_out):
    """관리자가 직접 고친 값(manual.json의 fix)은 항목별 잠금: 자동 수집이 옛 정보로 덮어쓰지 못하게 매번 마지막에 다시 씌운다.
    예) "fix": {"가게 이름 또는 id": {"tel": "032-000-0000", "memo": "11/22 대표님 확인"}} · 폐업은 {"closed": true}
    잠금을 풀려면 그 항목만 지우면 된다 (다른 항목은 계속 자동 갱신)."""
    fix = load_json(MANUAL, {}).get("fix", {})
    if not fix:
        return all_out
    out = []
    for o in all_out:
        f = fix.get(str(o["id"])) or fix.get(o["name"])
        if f:
            if f.get("closed"):
                print(f"직접 수정: {o['name']} 폐업·이전으로 뺌")
                continue
            for k in FIX_KEYS:
                if k in f:
                    o[k] = f[k]
            o["fixed"] = [k for k in FIX_KEYS if k in f]  # 「직접 수정함」 — 관리자 화면에서 잠금 표시
        out.append(o)
    return out


def insta_fill(all_out, gcache):
    """가게마다 인스타 계정 주소: 관리자가 넣은 것 > 구글 홈페이지가 인스타이거나 홈페이지에 적힌 것 (90일마다 다시 확인)."""
    ic = load_json(INSTA, {})
    manual = load_json(MANUAL, {}).get("insta", {})
    today = dt.date.today()
    n = 0
    for o in all_out:
        pid = str(o["id"])
        url = manual.get(pid) or manual.get(o["name"]) or ""
        if not url:
            web = (gcache.get(pid) or {}).get("web", "")
            hit = ic.get(pid)
            if hit and hit.get("w") == web and (today - dt.date.fromisoformat(hit["d"])).days < 90:
                url = hit.get("i", "")
            elif web and n < 80:
                url = find_insta(web)
                n += 1
                ic[pid] = {"i": url, "w": web, "d": today.isoformat()}
        if url:
            o["insta"] = url
        else:
            o.pop("insta", None)
    save_json(INSTA, ic)
    print(f"인스타 주소: {sum(1 for o in all_out if o.get('insta'))}곳 (새로 확인 {n}곳)")


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_noredir = urllib.request.build_opener(_NoRedirect)


def is_short(vid):
    """youtube.com/shorts/영상 이 그대로 열리면 쇼츠, 일반 영상 주소로 넘기면 아님 (유튜브 사용량 안 씀). 모르면 None."""
    try:
        req = urllib.request.Request(f"https://www.youtube.com/shorts/{vid}", method="HEAD", headers={"User-Agent": "Mozilla/5.0"})
        with _noredir.open(req, timeout=8) as r:
            return r.status == 200
    except urllib.error.HTTPError as e:
        return False if 300 <= e.code < 400 else None
    except Exception:
        return None


def mark_shorts(all_out):
    """쇼츠(세로 영상)에 sh=1 — 앱은 쇼츠 표지를 자르지 않고 통째로 보여 준다."""
    sc = load_json(SHORTS, {})
    n = 0
    for o in all_out:
        for v in o.get("vids", []):
            vid = v["id"]
            if vid not in sc and n < 300:
                r = is_short(vid)
                n += 1
                if r is not None:
                    sc[vid] = 1 if r else 0
                time.sleep(0.1)
            if sc.get(vid) == 1:
                v["sh"] = 1
            else:
                v.pop("sh", None)
    save_json(SHORTS, sc)
    print(f"쇼츠 확인: 새로 {n}개, 쇼츠 {sum(1 for x in sc.values() if x == 1)}개 / {len(sc)}개")


def yt_channels(all_out):
    """영상마다 채널 id를 붙이고, 이 동네에 다녀간 유튜버 목록(사진·구독자·다녀간 집)을 만든다. 실패하면 있는 만큼만."""
    try:
        mark_shorts(all_out)
    except Exception as e:
        print("쇼츠 확인 중단:", str(e)[:120])
    vids = {}
    for o in all_out:
        for v in o.get("vids", []):
            vids.setdefault(v["id"], []).append(v)
    cc = load_json(CHANNELS, {})
    today = dt.date.today()
    if YOUTUBE_KEY:
        try:
            need = [vid for vid, vs in vids.items() if not vs[0].get("cid")]
            for i in range(0, len(need), 50):
                q = urllib.parse.urlencode({"part": "snippet", "id": ",".join(need[i:i + 50]), "key": YOUTUBE_KEY})
                for it in get_json("https://www.googleapis.com/youtube/v3/videos?" + q).get("items", []):
                    hd = "maxres" in (it["snippet"].get("thumbnails") or {})
                    for v in vids.get(it["id"], []):
                        v["cid"] = it["snippet"].get("channelId", "")
                        if hd:
                            v["mx"] = 1  # 고화질 표지가 있는 영상 (앱의 큰 사진)
            cids = {v["cid"] for vs in vids.values() for v in vs if v.get("cid")}
            stale = [c for c in cids if c not in cc or (today - dt.date.fromisoformat(cc[c].get("d", "2000-01-01"))).days > 25]  # 25일 지나면 새로 (30일 넘기지 않게)
            for i in range(0, len(stale), 50):
                q = urllib.parse.urlencode({"part": "snippet,statistics", "id": ",".join(stale[i:i + 50]), "key": YOUTUBE_KEY})
                for it in get_json("https://www.googleapis.com/youtube/v3/channels?" + q).get("items", []):
                    th = it["snippet"].get("thumbnails", {})
                    cc[it["id"]] = {
                        "n": clean(it["snippet"].get("title"))[:30],
                        "th": (th.get("medium") or th.get("default") or {}).get("url", ""),
                        "s": int(it.get("statistics", {}).get("subscriberCount", 0) or 0),
                        "d": today.isoformat(),
                    }
        except Exception as e:
            print("유튜버 정보 중단:", str(e)[:120])
    # 유튜브 정책: 채널 정보(프로필 사진 주소·구독자 수)는 30일 넘게 두지 않는다 — 그새 새로 못 받은 채널은 지운다(앱은 첫 글자로)
    cc = {k: x for k, x in cc.items() if (today - dt.date.fromisoformat(x.get("d", "2000-01-01"))).days <= 30}
    save_json(CHANNELS, cc)
    per = {}
    for o in all_out:
        seen = set()
        for v in o.get("vids", []):
            c = v.get("cid")
            if c and c not in seen:
                seen.add(c)
                per.setdefault(c, {"name": v.get("ch", ""), "places": []})["places"].append(o["id"])
    out = []
    for c, x in per.items():
        info = cc.get(c, {})
        out.append({"id": c, "name": info.get("n") or x["name"], "thumb": info.get("th", ""), "subs": info.get("s", 0), "places": x["places"]})
    out.sort(key=lambda x: (len(x["places"]), x["subs"]), reverse=True)
    print("유튜버: " + ", ".join(f"{x['name']}({len(x['places'])}곳)" for x in out[:8]))
    return out[:40]


# ---------- 4. 점수 ----------

def cuisine_of(cat):
    parts = [x.strip() for x in (cat or "").split(">")]
    return parts[1] if len(parts) > 1 else ""


def short_category(cat):
    parts = [p.strip() for p in (cat or "").split(">")]
    return parts[2] if len(parts) > 2 else (parts[-1] if parts else "")


# ---------- 4. 후보: 카카오 검색 인기 순위 ----------

QUERIES = [
    "맛집", "맛집 추천", "현지인 맛집", "데이트 맛집", "가족 외식", "회식",
    "한식", "고기집", "일식", "중식", "양식", "파스타", "브런치",
    "카페", "대형카페", "베이커리 카페", "브런치 카페", "디저트 카페", "뷰 카페", "분위기 좋은 카페", "빵집",
    "핫플", "가볼만한곳", "대형 베이커리카페", "식물원 카페",
]

# 대표님이 직접 짚어 준, 꼭 후보에 넣어 볼 가게 (동네마다 regions.json의 must)
MUST = ["포레스트아웃팅스"]

# 지점 안내가 될 뿐인 전국 체인은 뺀다
CHAINS = [
    "스타벅스", "투썸", "이디야", "메가엠지씨", "메가커피", "빽다방", "컴포즈", "할리스", "파스쿠찌", "커피빈", "폴바셋",
    "탐앤탐스", "엔제리너스", "공차", "배스킨", "던킨", "파리바게뜨", "뚜레쥬르", "더벤티", "매머드", "백미당", "블루보틀",
    "맥도날드", "롯데리아", "버거킹", "맘스터치", "kfc", "서브웨이", "교촌", "bbq", "bhc", "굽네", "네네", "처갓집", "푸라닭",
    "도미노", "피자헛", "파파존스", "미스터피자", "김밥천국", "본죽", "홍콩반점", "빽보이", "새마을식당", "역전우동",
]


def kakao_keyword(query, page):
    x1, y1, x2, y2 = AREA
    q = urllib.parse.urlencode({"query": query, "rect": f"{x1},{y1},{x2},{y2}", "page": page, "size": 15})
    return get_json("https://dapi.kakao.com/v2/local/search/keyword.json?" + q, {"Authorization": f"KakaoAK {KAKAO_KEY}"})


def is_chain(name):
    n = norm(name)
    return any(norm(c) in n for c in CHAINS)


def popular_candidates():
    """여러 검색어로 카카오 검색 상위 45곳씩 모아, 자주·높게 나온 곳일수록 인기 점수를 준다."""
    cands = {}
    for q in [f"{AREA_NAME} {x}" for x in QUERIES] + EXTRA_Q:
        rank = 0
        for page in (1, 2, 3):
            try:
                res = kakao_keyword(q, page)
            except Exception as e:
                print(f"  검색 건너뜀 ({q}):", str(e)[:80])
                break
            for d in res.get("documents", []):
                rank += 1
                code = d.get("category_group_code")
                cat = d.get("category_name") or ""
                # 카카오 분류가 비어 있거나 다르게 잡힌 대형 카페·복합공간도 이름/분류로 받아들인다
                if code not in ("FD6", "CE7"):
                    if "카페" in cat or "베이커리" in cat or "디저트" in cat:
                        d["category_group_code"] = "CE7"
                    elif cat.startswith("음식점"):
                        d["category_group_code"] = "FD6"
                    else:
                        print("  분류 제외:", d.get("place_name"), "/", cat)
                        continue
                if is_chain(d.get("place_name")):
                    continue
                c = cands.setdefault(d["id"], {"p": d, "pop": 0, "hits": 0})
                c["pop"] += (46 - rank)
                c["hits"] += 1
            if res.get("meta", {}).get("is_end", True):
                break
    # 꼭 확인할 가게: 이름으로 직접 찾아 송도 범위 안이면 후보에 넣는다 (인기 점수는 후보들 중간값)
    mid = sorted(c["pop"] for c in cands.values())[len(cands) // 2] if cands else 1
    x1, y1, x2, y2 = AREA
    for name in MUST:
        res = get_json("https://dapi.kakao.com/v2/local/search/keyword.json?" + urllib.parse.urlencode({"query": name}),
                       {"Authorization": f"KakaoAK {KAKAO_KEY}"})
        for d in res.get("documents", []):
            inside = x1 <= float(d["x"]) <= x2 and y1 <= float(d["y"]) <= y2
            print("  직접 확인:", d["place_name"], "/", d.get("category_name"), "/", d.get("road_address_name"), f"/ {AREA_LABEL} 범위", "안" if inside else "밖")
            if inside and d["id"] not in cands:
                if d.get("category_group_code") not in ("FD6", "CE7"):
                    d["category_group_code"] = "CE7" if "카페" in (d.get("category_name") or "") or "베이커리" in (d.get("category_name") or "") else "FD6"
                cands[d["id"]] = {"p": d, "pop": mid, "hits": 0}
    print(f"인기 후보 {len(cands)}곳 (검색어 {len(QUERIES)}개)")
    for c in cands.values():
        if "포레스트" in c["p"]["place_name"]:
            print("  확인:", c["p"]["place_name"], c["p"].get("category_name"), "인기", c["pop"], "횟수", c["hits"])
    return list(cands.values())


def build_list(kind, rows, top_n, use_google):
    rows = [r for r in rows if r["kind"] == kind and not r["g"].get("bs")]  # 폐업·임시 휴업 제외
    if use_google:
        rows = [r for r in rows if r["g"]["n"] >= MIN_REVIEWS]
    if not rows:
        return []
    max_pop = max(r["pop"] for r in rows) or 1
    max_blog = max(r["est"] for r in rows) or 1
    max_g = max(r["g"]["r"] / 5 * math.log10(1 + r["g"]["n"]) for r in rows) or 1
    for r in rows:
        b_ = math.log2(1 + r["est"]) / math.log2(1 + max_blog)
        v_ = min(len(r["vids"]), 3) / 3
        if use_google:
            g_ = (r["g"]["r"] / 5 * math.log10(1 + r["g"]["n"])) / max_g
            r["raw"] = 0.65 * g_ + 0.2 * b_ + 0.15 * v_
        else:
            r["raw"] = 0.5 * (r["pop"] / max_pop) + 0.35 * b_ + 0.15 * v_
    rows.sort(key=lambda r: r["raw"], reverse=True)
    top = rows[0]["raw"] or 1
    for r in rows:
        r["score"] = round(100 * r["raw"] / top)
    for r in rows[:top_n]:
        r["top"] = True
    return [to_out(r) for r in rows[:top_n]]


def dong_of(p):
    """지번 주소에서 동·읍·면 이름 (예: 인천 연수구 송도동 24-5 → 송도동)."""
    toks = (p.get("address_name") or "").split()
    for t in toks[1:]:
        if re.search(r"(동|읍|면|리|\d가)$", t) and not re.search(r"(시|구|군)$", t):
            return t
    return ""


def to_out(r):
    p = r["p"]
    return {
        "id": p["id"],
        "kind": r["kind"],
        "name": p["place_name"],
        "cat": short_category(p.get("category_name")),
        "cz": cuisine_of(p.get("category_name")),  # 음식 종류 (카카오 분류 둘째 칸: 한식·중식·일식·양식·분식 …)
        "dong": dong_of(p),
        "lat": float(p["y"]),
        "lng": float(p["x"]),
        "addr": p.get("road_address_name") or p.get("address_name"),
        "tel": p.get("phone"),
        "kakao": p.get("place_url"),
        "home": r["home"],
        "blog": r["est"],
        "ads": r["ads"],
        "grate": r["g"]["r"],
        "greviews": r["g"]["n"],
        "gurl": r["g"]["u"],
        "score": r.get("score", 0),
        "top": bool(r.get("top")),
        "rise": bool(r.get("rise")),
        "r30": r.get("r30", 0),
        "rr": r.get("rr", 0),
        "posts": r["posts"][:6],
        "vids": r["vids"],
        "hours": r["g"].get("h", []),
        "week": r["g"].get("w", []),
        "feat": r["g"].get("f", []),
    }


def main():
    if not KAKAO_KEY:
        print("열쇠가 없습니다: KAKAO_REST_KEY")
        sys.exit(1)
    print("블로그 검색:", "네이버" if (NAVER_ID and NAVER_SECRET) else "다음(카카오)")
    try:  # 블로그 검색 점검: 막혀 있으면 블로그 단계를 건너뛰고 지난 글을 그대로 쓴다
        kakao_blog(f"{AREA_NAME} 맛집", pages=1)
    except Exception as e:
        BLOG_UP[0] = False
        print("블로그 검색이 막혀 있어 지난 글을 그대로 씁니다:", str(e)[:600])

    prev, rank_of, prev_full = {}, {}, {}
    try:
        with open(OUT, encoding="utf-8") as f:
            _pl = json.load(f).get("places", [])
            prev = {str(o["id"]): o.get("vids", []) for o in _pl}
            prev_full = {str(o["id"]): o for o in _pl}
            rank_of = {str(o["id"]): i for i, o in enumerate(sorted(_pl, key=lambda o: -o.get("score", 0)))}
    except Exception:
        pass
    cache = {}
    try:
        with open(CACHE, encoding="utf-8") as f:
            cache = json.load(f)
    except Exception:
        pass

    # 후보 1: 카카오 검색 상위 + 꼭 확인할 가게
    pop = popular_candidates()
    check_kakao()
    by_id = {c["p"]["id"]: c for c in pop}
    # 후보 2: 송도 전체 음식점·카페 (체인 제외) — 목록은 7일마다만 새로 받는다
    allpc = load_json(PLACES_CACHE, {})
    if "FD6" in allpc:  # 예전 형식(송도 하나)
        allpc = {"songdo": allpc}
    pc = allpc.get(AREA_ID, {})
    fresh = pc.get("d") and (dt.date.today() - dt.date.fromisoformat(pc["d"])).days < 7 and pc.get("area") == list(AREA)
    if not fresh:
        pc = {"d": dt.date.today().isoformat(), "area": list(AREA), "FD6": collect_places("FD6"), "CE7": collect_places("CE7")}
        check_kakao()   # 중간에 끊긴 목록은 저장하지 않는다 (멀쩡한 가게가 빠져 보이지 않게)
        allpc[AREA_ID] = pc
        save_json(PLACES_CACHE, allpc)
    else:
        print(f"가게 목록 재사용 ({pc['d']} 기준)")
    for code in ("FD6", "CE7"):
        for p in pc[code]:
            if is_chain(p.get("place_name")) or p["id"] in by_id:
                continue
            by_id[p["id"]] = {"p": p, "pop": 0, "hits": 0}
    cands = list(by_id.values())
    print(f"블로그 확인 대상 {len(cands)}곳")
    done = [0]

    today0 = dt.date.today()

    bc = load_json(BLOG_CACHE, {})

    def known_small(pid):
        h = cache.get(str(pid))
        return h and h.get("n", 0) < MIN_REVIEWS and (today0 - dt.date.fromisoformat(h["d"])).days < GOOGLE_DAYS

    def one(c):
        p = c["p"]
        kind = "cafe" if p.get("category_group_code") == "CE7" else "food"
        if known_small(p["id"]):  # 구글 리뷰가 적다고 이미 확인된 곳은 건너뛴다
            return {"p": p, "kind": kind, "pop": c["pop"], "posts": [], "ads": 0, "est": 0,
                    "home": "", "vids": prev.get(str(p["id"]), []), "g": {"r": 0, "n": 0, "u": ""}}
        hit = bc.get(str(p["id"]))
        if hit and (today0 - dt.date.fromisoformat(hit["d"])).days < BLOG_DAYS:
            return {"p": p, "kind": kind, "pop": c["pop"], "posts": [], "ads": 0, "est": hit["e"],
                    "home": "", "vids": prev.get(str(p["id"]), []), "g": {"r": 0, "n": 0, "u": ""}}
        if not BLOG_UP[0]:
            return {"p": p, "kind": kind, "pop": c["pop"], "posts": [], "ads": 0, "est": (hit or {}).get("e", 0),
                    "home": "", "vids": prev.get(str(p["id"]), []), "g": {"r": 0, "n": 0, "u": ""}}
        try:
            posts, ads, est, home = blog_stats(p, pages=1)
            bc[str(p["id"])] = {"e": est, "d": today0.isoformat()}
        except Exception as e:
            print("블로그 실패", p["place_name"], str(e)[:120])
            posts, ads, est, home = [], 0, 0, ""
        done[0] += 1
        if done[0] % 300 == 0:
            print(f"  블로그 {done[0]}/{len(cands)}")
        kind = "cafe" if p.get("category_group_code") == "CE7" else "food"
        return {"p": p, "kind": kind, "pop": c["pop"], "posts": posts, "ads": ads, "est": est,
                "home": home, "vids": prev.get(str(p["id"]), []), "g": {"r": 0, "n": 0, "u": ""}}

    with ThreadPoolExecutor(max_workers=8) as ex:
        rows = list(ex.map(one, cands))
    save_json(BLOG_CACHE, bc)
    check_kakao()

    # 구글 별점·리뷰: 무료 범위(월 1,000회) 안에서만 조회한다.
    #  - 한 달 최대 GOOGLE_MONTH회, 하루 최대 GOOGLE_MAX회 (넘으면 저장값 그대로 씀)
    #  - 순위권(지난 순위 상위) 가게는 한 달, 나머지는 석 달 지나면 오래된 순서로 새로 받음
    use_google = False
    if GOOGLE_KEY:
        today = dt.date.today()
        month = today.strftime("%Y-%m")
        usage = load_json(USAGE, {})
        used = usage.get(month, 0)
        ranked = set(prev.keys())
        pri = sorted(rows, key=lambda r: (r["pop"] > 0, r["est"]), reverse=True)
        keep = [r for r in pri if str(r["p"]["id"]) in ranked]
        rest = [r for r in pri if str(r["p"]["id"]) not in ranked and (r["pop"] > 0 or r["est"] >= 3)]
        pri = keep + rest[:max(0, GOOGLE_PER_AREA - len(keep))]
        need = []
        for r in pri:
            pid = str(r["p"]["id"])
            hit = cache.get(pid)
            if hit:
                r["g"] = hit
                age = (today - dt.date.fromisoformat(hit["d"])).days
                if pid in ranked and hit.get("v", 1) < 4:
                    need.append((0, rank_of.get(pid, 99), r))  # 순위권인데 영업시간·편의 정보·홈페이지가 없음: 맨 먼저 (무료량 안에서)
                    continue
                limit = GOOGLE_DAYS_TOP if pid in ranked else GOOGLE_DAYS
                if age < limit:
                    continue
                need.append((2, -age, r))   # 갱신: 오래된 것부터
            else:
                need.append((1, 0, r))      # 그다음 처음 보는 가게
        need.sort(key=lambda t: (t[0], t[1]))
        new_calls, fails = 0, 0
        for _, _, r in need:
            if new_calls >= (GOOGLE_NEW_MAX if NEW_AREA else GOOGLE_MAX) or used + new_calls >= GOOGLE_MONTH:
                break
            pid = str(r["p"]["id"])
            try:
                g = google_lookup(r["p"])
                new_calls += 1
                g["d"] = today.isoformat()
                cache[pid] = g
                r["g"] = g
            except Exception as e:
                fails += 1
                print("구글 실패:", str(e)[:200])
                if fails >= 3:
                    break
        usage[month] = used + new_calls
        save_json(USAGE, {k: usage[k] for k in sorted(usage)[-6:]})
        print(f"이번 달 구글 조회 {usage[month]}/{GOOGLE_MONTH}회, 남은 갱신 대기 {max(0, len(need) - new_calls)}곳")
        have = sum(1 for r in rows if r["g"]["n"] >= MIN_REVIEWS)
        print(f"구글 새 조회 {new_calls}회, 리뷰 {MIN_REVIEWS}개 이상 {have}곳")
        use_google = have >= 20
        with open(CACHE, "w", encoding="utf-8") as f:
            json.dump(cache, f, ensure_ascii=False, separators=(",", ":"))

    # 2단계: 순위 후보(구글 리뷰 충분한 곳)만 블로그를 자세히(2쪽) 다시 본다
    if not BLOG_UP[0]:  # 블로그가 막힌 날은 지난번 블로그 수를 그대로 써서 순위가 흔들리지 않게
        for r in rows:
            old = prev_full.get(str(r["p"]["id"]))
            if old:
                r["est"] = old.get("blog", r["est"])
    if use_google and BLOG_UP[0]:
        detail = [r for r in rows if r["g"]["n"] >= MIN_REVIEWS]

        def deep(r):
            try:
                r["posts"], r["ads"], r["est"], h = blog_stats(r["p"], pages=2)
                r["home"] = r["home"] or h
            except Exception as e:
                print("블로그 상세 실패", r["p"]["place_name"], str(e)[:100])

        with ThreadPoolExecutor(max_workers=8) as ex:
            list(ex.map(deep, detail))
        print(f"블로그 상세 확인 {len(detail)}곳")
        check_kakao()

    # 새로 뜨는 집: 최근 30일 글 수가 그 전(31~90일) 하루 평균보다 1.8배 이상 늘었거나, 그 전엔 글이 없다가 새로 생긴 집
    if use_google and BLOG_UP[0]:
        today_s = dt.date.today()
        cand = []
        for r in rows:
            if r["g"]["n"] < MIN_REVIEWS or not r["posts"]:
                continue
            ds = sorted(dt.datetime.strptime(x["date"], "%Y%m%d").date() for x in r["posts"] if (x.get("date") or "").isdigit())
            if not ds:
                continue
            span = min(RECENT_DAYS, (today_s - ds[0]).days)
            r30 = sum(1 for x in ds if (today_s - x).days <= 30)
            older = len(ds) - r30
            r["r30"] = r30
            if r30 < 6:
                continue
            if older == 0:
                ratio = 9.9 if span <= 30 else 5.0  # 그 전엔 글이 없던 새 가게
            elif span <= 40:
                continue  # 글이 너무 많아 비교할 기간이 안 됨 (원래 인기 많은 집)
            else:
                ratio = (r30 / 30) / (older / (span - 30))
            if ratio >= 1.8:
                r["rr"] = round(ratio, 1)
                cand.append(r)
        cand.sort(key=lambda r: (r["rr"], r["r30"]), reverse=True)
        for r in cand[:12]:
            r["rise"] = True
        print("새로 뜨는 집: " + ", ".join(f"{r['p']['place_name']}({r['r30']}건, {r['rr']}배)" for r in cand[:12]))

    # 유튜브: 종류별 상위 후보만 (하루 사용량 한도)
    if YOUTUBE_KEY:
        stop = False
        for kind in ("food", "cafe"):
            ks = sorted([r for r in rows if r["kind"] == kind],
                        key=lambda r: (r["g"]["n"], r["est"]) if use_google else (r["pop"], r["est"]), reverse=True)
            for r in ks[:YOUTUBE_TOP]:
                if stop or r["vids"]:
                    continue
                try:
                    found = youtube_videos(r["p"])
                    if found:
                        r["vids"] = found
                except Exception as e:
                    print("유튜브 중단:", str(e)[:120])
                    stop = True

    all_out = []
    for kind, label in (("food", "맛집"), ("cafe", "카페")):
        out = build_list(kind, rows, TOP_N, use_google)
        for o in out:  # 블로그 검색이 실패해 글이 비었으면 지난번 글을 그대로 둔다
            old = prev_full.get(str(o["id"]))
            if old and not o["posts"] and old.get("posts"):
                o["posts"], o["ads"] = old["posts"], old.get("ads", 0)
                o["home"] = o["home"] or old.get("home", "")
        all_out += out
        print(f"[{label}] " + " / ".join(f"{o['name']}({o['score']}, 구글 {o['greviews']})" for o in out))
    tops = {o["id"] for o in all_out}
    all_out += [to_out(r) for r in rows if r.get("rise") and r["p"]["id"] not in tops]

    # 방송 출연·대형 카페: 순위에 든 집만, 한 달에 한 번 (카카오가 멈추면 지난 결과를 그대로 씀)
    tvc = load_json(TV_CACHE, {})
    checked = 0
    for o in all_out:
        pid = str(o["id"])
        h = tvc.get(pid)
        if not o.get("top"):
            o["tv"], o["big"], o["view"] = (h or {}).get("t", []), bool((h or {}).get("b")), bool((h or {}).get("v"))
            continue
        stale = not (h and (dt.date.today() - dt.date.fromisoformat(h["d"])).days < TV_DAYS)
        old = h or {}
        need = stale or "v" not in old or (o["kind"] == "cafe" and "b" not in old)
        if BLOG_UP[0] and need:
            try:
                t = tv_check(o["name"]) if (stale or "t" not in old) else old["t"]
                b = (big_check(o["name"]) if (stale or "b" not in old) else old["b"]) if o["kind"] == "cafe" else False
                v = view_check(o["name"]) if (stale or "v" not in old) else old["v"]
                h = {"t": t, "b": b, "v": v, "d": dt.date.today().isoformat() if stale else old["d"]}
                tvc[pid] = h
                checked += 1
            except Exception as e:
                print("방송·대형·뷰 확인 실패", o["name"], str(e)[:80])
        o["tv"] = (h or {}).get("t", [])
        o["big"] = bool((h or {}).get("b", False))
        o["view"] = bool((h or {}).get("v", False))
    save_json(TV_CACHE, tvc)
    print(f"방송·대형 확인 {checked}곳 새로, 방송 나온 집: " + ", ".join(f"{o['name']}({'·'.join(o['tv'])})" for o in all_out if o["tv"])
          + " / 대형 카페: " + ", ".join(o["name"] for o in all_out if o.get("big"))
          + " / 뷰: " + ", ".join(o["name"] for o in all_out if o.get("view")))

    all_out = apply_fix(all_out)
    try:
        model_fill(all_out)
    except Exception as e:
        print("모범음식점 확인 중단:", str(e)[:120])
    try:
        insta_fill(all_out, cache)
    except Exception as e:
        print("인스타 주소 확인 중단:", str(e)[:120])
    channels = yt_channels(all_out)

    data = {
        "channels": channels,
        "area": AREA_LABEL,
        "area_id": AREA_ID,
        "updated": dt.datetime.now(dt.timezone(dt.timedelta(hours=9))).strftime("%Y-%m-%d %H:%M"),
        "recent_days": RECENT_DAYS,
        "basis": "google" if use_google else "kakao",
        "candidates": len(cands),
        "count": len(all_out),
        "places": all_out,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    print(f"저장 완료: {len(all_out)}곳 ({os.path.getsize(OUT) // 1024}KB), 기준: {data['basis']}")


def run_all():
    """regions.json에서 collect가 켜진 동네를 차례로 모은다. 자료가 잘 나오면 그 동네를 앱에서 열 수 있게(ready) 한다."""
    global AREA, AREA_NAME, AREA_ID, AREA_LABEL, EXTRA_Q, MUST, OUT, NEW_AREA
    regions = load_json(REGIONS, {})
    areas = [a for s in regions.get("sido", []) for a in s.get("areas", []) if a.get("collect")]
    only = [x for x in os.environ.get("AREAS", "").split(",") if x]
    if only:
        areas = [a for a in areas if a["id"] in only]
    # 새 동네를 먼저: 이미 연 동네는 저장된 자료가 있어 하루 늦어도 괜찮다
    areas.sort(key=lambda a: bool(a.get("ready")))
    for a in areas:
        AREA = tuple(a["bbox"])
        AREA_NAME = a.get("q") or a["name"]
        AREA_ID = a["id"]
        AREA_LABEL = a["name"]
        EXTRA_Q = a.get("extra", [])
        MUST = a.get("must", [])
        OUT = os.path.join(DATA_DIR, f"{a['id']}.json")
        NEW_AREA = not a.get("ready")
        if NEW_AREA:
            # 새 동네는 이번 달 구글 무료량이 넉넉히 남았을 때만 시작한다 (모자라면 다음 달 1일에 저절로 시작)
            used = load_json(USAGE, {}).get(dt.date.today().strftime("%Y-%m"), 0)
            if GOOGLE_MONTH - used < 120:
                print(f"\n{a['name']}: 이번 달 구글 무료량이 {GOOGLE_MONTH - used}번 남아 다음 달에 시작합니다")
                continue
        KAKAO_FAILS[0] = 0
        BLOG_UP[0] = True
        print(f"\n========== {AREA_LABEL} ({AREA_ID}) {'처음 여는 동네' if NEW_AREA else ''} ==========")
        try:
            main()
        except KakaoDown:
            print("카카오가 응답하지 않아 이 동네는 여기서 멈춥니다. 앱에는 기존 자료가 그대로 보입니다.")
            continue
        try:
            with open(OUT, encoding="utf-8") as f:
                js = json.load(f)
            pl = js.get("places", [])
            a["updated"] = js.get("updated", "")  # 앱이 휴대폰에 저장한 자료가 새 판인지 보는 표
            n = len(pl)
            a["count"] = sum(1 for x in pl if x.get("top", True))
            a["food"] = sum(1 for x in pl if x.get("top", True) and x["kind"] == "food")
            a["cafe"] = sum(1 for x in pl if x.get("top", True) and x["kind"] == "cafe")
        except Exception:
            n = 0
        if n >= 10 and not a.get("ready"):
            a["ready"] = True
            print(f"{AREA_LABEL}: {n}곳 — 이제 앱에서 열 수 있습니다")
    save_json(REGIONS, regions)


if __name__ == "__main__":
    run_all()
