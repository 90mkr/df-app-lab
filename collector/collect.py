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

# 송도 일대 범위 (서쪽 경도, 남쪽 위도, 동쪽 경도, 북쪽 위도)
AREA = (126.600, 37.355, 126.700, 37.420)
AREA_NAME = "송도"
RECENT_DAYS = 90
YOUTUBE_TOP = int(os.environ.get("YOUTUBE_TOP", "25"))  # 종류별 유튜브 확인 수
TOP_N = int(os.environ.get("TOP_N", "10"))  # 종류별로 앱에 남기는 수
KINDS = [("food", "FD6", "맛집"), ("cafe", "CE7", "카페")]
OUT = os.path.join(os.path.dirname(__file__), "..", "web", "data", "songdo.json")

AD_WORDS = ["협찬", "체험단", "원고료", "소정의", "제공받", "지원받", "광고", "업체로부터", "서포터즈", "무료로 제공"]

KAKAO_KEY = os.environ.get("KAKAO_REST_KEY", "").strip()
NAVER_ID = os.environ.get("NAVER_CLIENT_ID", "").strip()
NAVER_SECRET = os.environ.get("NAVER_CLIENT_SECRET", "").strip()
YOUTUBE_KEY = os.environ.get("YOUTUBE_KEY", "").strip()


def get_json(url, headers=None, tries=3):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=headers or {})
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "ignore")[:300]
            if e.code in (429, 500, 502, 503) and i < tries - 1:
                time.sleep(2 + i * 3)
                continue
            raise RuntimeError(f"{e.code} {url[:80]} {body}")
        except Exception:
            if i < tries - 1:
                time.sleep(2)
                continue
            raise


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


def kakao_blog(query):
    """다음(카카오) 블로그 검색 — 네이버 블로그·티스토리 글도 함께 잡힌다. 네이버 검색과 같은 모양으로 바꿔 돌려준다."""
    items, ended = [], False
    for page in (1, 2):
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


def blog_stats(place, chain=False):
    base = base_name(place["place_name"])
    key = norm(base)
    # 두 글자 이하 이름(봄, 숲, 정원…)은 엉뚱한 글이 너무 많이 잡혀 판단 불가 → 제외
    if len(key) < 3:
        return [], 0, 0, ""
    branch = branch_token(place["place_name"], base) if chain else ""
    if chain and len(branch) < 2:
        return [], 0, 0, ""
    query = f"{AREA_NAME} {base}"
    res = naver_blog(query) if (NAVER_ID and NAVER_SECRET) else kakao_blog(query)
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


# ---------- 4. 점수 ----------

def short_category(cat):
    parts = [p.strip() for p in (cat or "").split(">")]
    return parts[2] if len(parts) > 2 else (parts[-1] if parts else "")


# ---------- 4. 후보: 카카오 검색 인기 순위 ----------

QUERIES = [
    "맛집", "맛집 추천", "현지인 맛집", "데이트 맛집", "가족 외식", "회식",
    "한식", "고기집", "일식", "중식", "양식", "파스타", "브런치", "센트럴파크 맛집", "트리플스트리트 맛집",
    "카페", "대형카페", "베이커리 카페", "브런치 카페", "디저트 카페", "뷰 카페", "분위기 좋은 카페", "빵집",
    "핫플", "가볼만한곳", "대형 베이커리카페", "식물원 카페",
]

# 대표님이 직접 짚어 준, 꼭 후보에 넣어 볼 가게
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
    for q in QUERIES:
        rank = 0
        for page in (1, 2, 3):
            res = kakao_keyword(f"{AREA_NAME} {q}", page)
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
            print("  직접 확인:", d["place_name"], "/", d.get("category_name"), "/", d.get("road_address_name"), "/ 송도 범위", "안" if inside else "밖")
            if inside and d["id"] not in cands:
                if d.get("category_group_code") not in ("FD6", "CE7"):
                    d["category_group_code"] = "CE7" if "카페" in (d.get("category_name") or "") or "베이커리" in (d.get("category_name") or "") else "FD6"
                cands[d["id"]] = {"p": d, "pop": mid, "hits": 0}
    print(f"인기 후보 {len(cands)}곳 (검색어 {len(QUERIES)}개)")
    for c in cands.values():
        if "포레스트" in c["p"]["place_name"]:
            print("  확인:", c["p"]["place_name"], c["p"].get("category_name"), "인기", c["pop"], "횟수", c["hits"])
    return list(cands.values())


def build_list(kind, rows, top_n):
    rows = [r for r in rows if r["kind"] == kind]
    if not rows:
        return []
    max_pop = max(r["pop"] for r in rows) or 1
    max_blog = max(r["est"] for r in rows) or 1
    for r in rows:
        p_ = r["pop"] / max_pop
        b_ = math.log2(1 + r["est"]) / math.log2(1 + max_blog)
        v_ = min(len(r["vids"]), 3) / 3
        r["raw"] = 0.5 * p_ + 0.35 * b_ + 0.15 * v_
    rows.sort(key=lambda r: r["raw"], reverse=True)
    top = rows[0]["raw"] or 1
    out = []
    for r in rows[:top_n]:
        p = r["p"]
        out.append({
            "id": p["id"],
            "kind": kind,
            "name": p["place_name"],
            "cat": short_category(p.get("category_name")),
            "lat": float(p["y"]),
            "lng": float(p["x"]),
            "addr": p.get("road_address_name") or p.get("address_name"),
            "tel": p.get("phone"),
            "kakao": p.get("place_url"),
            "home": r["home"],
            "blog": r["est"],
            "ads": r["ads"],
            "score": round(100 * r["raw"] / top),
            "posts": r["posts"][:6],
            "vids": r["vids"],
        })
    return out


def main():
    if not KAKAO_KEY:
        print("열쇠가 없습니다: KAKAO_REST_KEY")
        sys.exit(1)
    print("블로그 검색:", "네이버" if (NAVER_ID and NAVER_SECRET) else "다음(카카오)")

    prev = {}
    try:
        with open(OUT, encoding="utf-8") as f:
            prev = {str(o["id"]): o.get("vids", []) for o in json.load(f).get("places", [])}
    except Exception:
        pass

    cands = popular_candidates()

    def one(c):
        p = c["p"]
        try:
            posts, ads, est, home = blog_stats(p)
        except Exception as e:
            print("블로그 실패", p["place_name"], str(e)[:120])
            posts, ads, est, home = [], 0, 0, ""
        kind = "cafe" if p.get("category_group_code") == "CE7" else "food"
        return {"p": p, "kind": kind, "pop": c["pop"], "posts": posts, "ads": ads, "est": est,
                "home": home, "vids": prev.get(str(p["id"]), [])}

    with ThreadPoolExecutor(max_workers=6) as ex:
        rows = list(ex.map(one, cands))

    # 유튜브는 종류별 인기 상위 후보만 확인 (하루 사용량 한도)
    if YOUTUBE_KEY:
        stop = False
        for kind in ("food", "cafe"):
            ks = sorted([r for r in rows if r["kind"] == kind], key=lambda r: r["pop"], reverse=True)
            for r in ks[:YOUTUBE_TOP]:
                if stop:
                    break
                try:
                    found = youtube_videos(r["p"])
                    if found:
                        r["vids"] = found
                except Exception as e:
                    print("유튜브 중단:", str(e)[:120])
                    stop = True

    all_out = []
    for kind, label in (("food", "맛집"), ("cafe", "카페")):
        out = build_list(kind, rows, TOP_N)
        all_out += out
        print(f"[{label}] " + " / ".join(f"{o['name']}({o['score']})" for o in out))

    data = {
        "area": AREA_NAME,
        "updated": dt.datetime.now(dt.timezone(dt.timedelta(hours=9))).strftime("%Y-%m-%d %H:%M"),
        "recent_days": RECENT_DAYS,
        "candidates": len(cands),
        "count": len(all_out),
        "places": all_out,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    print(f"저장 완료: {len(all_out)}곳 ({os.path.getsize(OUT) // 1024}KB)")


if __name__ == "__main__":
    main()
