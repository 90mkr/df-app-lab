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

# 송도 일대 범위 (서쪽 경도, 남쪽 위도, 동쪽 경도, 북쪽 위도)
AREA = (126.600, 37.355, 126.700, 37.420)
AREA_NAME = "송도"
RECENT_DAYS = 90
YOUTUBE_TOP = int(os.environ.get("YOUTUBE_TOP", "80"))
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

def kakao_rect(x1, y1, x2, y2, page):
    q = urllib.parse.urlencode({
        "category_group_code": "FD6",
        "rect": f"{x1},{y1},{x2},{y2}",
        "page": page,
        "size": 15,
    })
    return get_json("https://dapi.kakao.com/v2/local/search/category.json?" + q,
                    {"Authorization": f"KakaoAK {KAKAO_KEY}"})


def collect_places():
    places = {}

    def walk(x1, y1, x2, y2, depth=0):
        first = kakao_rect(x1, y1, x2, y2, 1)
        total = first["meta"]["total_count"]
        # 한 칸에 45곳 넘으면 4칸으로 쪼갠다
        if total > 45 and depth < 8:
            mx, my = (x1 + x2) / 2, (y1 + y2) / 2
            for a in ((x1, y1, mx, my), (mx, y1, x2, my), (x1, my, mx, y2), (mx, my, x2, y2)):
                walk(*a, depth=depth + 1)
            return
        docs = list(first["documents"])
        page = 1
        meta = first["meta"]
        while not meta["is_end"] and page < 3:
            page += 1
            res = kakao_rect(x1, y1, x2, y2, page)
            docs += res["documents"]
            meta = res["meta"]
            time.sleep(0.05)
        for d in docs:
            places[d["id"]] = d

    walk(*AREA)
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
    items = []
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
            break
        time.sleep(0.05)
    return {"items": items}


def blog_stats(place):
    base = base_name(place["place_name"])
    key = norm(base)
    query = f"{AREA_NAME} {base}"
    res = naver_blog(query) if (NAVER_ID and NAVER_SECRET) else kakao_blog(query)
    since = (dt.date.today() - dt.timedelta(days=RECENT_DAYS)).strftime("%Y%m%d")
    clean_posts, ad_count = [], 0
    for it in res.get("items", []):
        title, desc = clean(it.get("title")), clean(it.get("description"))
        if key not in norm(title + desc):
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
    return clean_posts, ad_count


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


def main():
    if not KAKAO_KEY:
        print("열쇠가 없습니다: KAKAO_REST_KEY")
        sys.exit(1)
    print("블로그 검색:", "네이버" if (NAVER_ID and NAVER_SECRET) else "다음(카카오)")

    places = collect_places()
    print(f"카카오 음식점 {len(places)}곳")

    rows = []
    for i, p in enumerate(places):
        try:
            posts, ads = blog_stats(p)
        except Exception as e:
            print("블로그 실패", p["place_name"], e)
            posts, ads = [], 0
        rows.append({"p": p, "posts": posts, "ads": ads, "vids": []})
        time.sleep(0.11)
        if i % 100 == 0:
            print(f"  블로그 {i}/{len(places)}")

    rows.sort(key=lambda r: len(r["posts"]), reverse=True)
    if YOUTUBE_KEY:
        for r in rows[:YOUTUBE_TOP]:
            if not r["posts"]:
                break
            try:
                r["vids"] = youtube_videos(r["p"])
            except Exception as e:
                print("유튜브 중단:", e)
                break

    out = []
    for r in rows:
        p = r["p"]
        n_blog = len(r["posts"])
        raw = 10 * math.log2(1 + n_blog) + 6 * min(len(r["vids"]), 3)
        out.append({
            "id": p["id"],
            "name": p["place_name"],
            "cat": short_category(p.get("category_name")),
            "lat": float(p["y"]),
            "lng": float(p["x"]),
            "addr": p.get("road_address_name") or p.get("address_name"),
            "tel": p.get("phone"),
            "kakao": p.get("place_url"),
            "blog": n_blog,
            "ads": r["ads"],
            "raw": round(raw, 2),
            "posts": r["posts"][:6],
            "vids": r["vids"],
        })

    top = max([o["raw"] for o in out] + [1])
    for o in out:
        o["score"] = round(100 * o.pop("raw") / top)
    out.sort(key=lambda o: o["score"], reverse=True)

    data = {
        "area": AREA_NAME,
        "updated": dt.datetime.now(dt.timezone(dt.timedelta(hours=9))).strftime("%Y-%m-%d %H:%M"),
        "recent_days": RECENT_DAYS,
        "count": len(out),
        "places": out,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    hot = sum(1 for o in out if o["score"] >= 30)
    print(f"저장 완료: {len(out)}곳, 화제 30점 이상 {hot}곳")


if __name__ == "__main__":
    main()
