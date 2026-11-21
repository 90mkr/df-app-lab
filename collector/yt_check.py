"""유명 유튜버 따라가기 — 채널 후보 확인 (한 번만 돌려 보는 점검)

채널마다: 실제 채널 찾기(핸들 → 없으면 이름 검색), 구독자·영상 수, 최근 영상 150개 중
설명란에 가게 주소·상호가 적힌 영상 수, 마지막 업로드 날짜를 적는다.
유튜브 사용량: 핸들 찾기 1, 이름 검색 100, 최근 영상 50개 1 (모두 합쳐 몇천 이하).
"""
import datetime as dt
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

KEY = os.environ.get("YOUTUBE_KEY", "").strip()
API = "https://www.googleapis.com/youtube/v3/"
MAX_SEARCH = int(os.environ.get("MAX_SEARCH", "25"))  # 이름 검색(100씩)은 이만큼까지만
used = [0]
searched = [0]


class Stop(Exception):
    pass


def get(path, cost=1, **q):
    q["key"] = KEY
    used[0] += cost
    url = API + path + "?" + urllib.parse.urlencode(q)
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "kokple-check"}), timeout=25) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "ignore")
        if e.code in (403, 429) and ("quota" in body.lower() or "rateLimit" in body):
            raise Stop(f"{e.code} 사용량 초과: {body[:200]}")
        raise RuntimeError(f"{e.code} {body[:200]}")


# (구분, 이름, 핸들 후보, 검색어, 채널 id)
CANDS = [
    ("전국", "성시경 (먹을텐데)", ["sungsikyung"], "성시경 먹을텐데", ""),
    ("전국", "풍자 또간집 (스튜디오 수제)", ["studio_suze"], "스튜디오 수제 또간집", "UC4ZA57iJrf73bJlApKFeLRw"),
    ("전국", "최자로드", ["choiza_road", "choizaroadtv", "choiza11"], "최자로드", ""),
    ("전국", "정육왕", ["meatcreator"], "정육왕 MeatCreator", ""),
    ("전국", "맛상무", ["matsangmu"], "맛상무", ""),
    ("전국", "김사원세끼", [], "김사원세끼", "UC-x55HF1-IilhxZOzwJm7JA"),
    ("전국", "맛있겠다 (노포 부부)", [], "맛있겠다 노포 부부 유튜버", ""),
    ("전국", "하이갱스 (동네 맛집)", [], "", "UC86GzuZXRb7aZnhnnUA3IAg"),
    ("전국", "섬마을훈태TV", ["seommaeulhuntae"], "섬마을훈태TV", ""),
    ("전국", "윤호찌", ["yoonhozzi"], "윤호찌 맛집", ""),
    ("전국", "츄릅켠", [], "츄릅켠 맛집", ""),
    ("전국", "지뉼랭가이드", ["jinyulang"], "지뉼랭가이드", ""),
    ("전국", "회사랑", [], "회사랑 맛집 유튜버", ""),
    ("전국", "쯔양", ["tzuyang6145"], "쯔양 tzuyang", ""),
    ("전국", "히밥", ["heebab"], "히밥 heebab", ""),
    ("전국", "입짧은햇님", [], "입짧은햇님", ""),
    ("전국", "먹보스 쭈엽이", ["mukbossjjuyeobi", "mukboss_jjuyeobi"], "먹보스 쭈엽이", ""),
    ("전국", "백종원 (님아 그 시장을 가오)", ["paik_jongwon"], "백종원 PAIK JONG WON", ""),
    ("전국", "이태리 파브리", [], "", "UCza_sEjIhb1yhvVZEdEl6gA"),
    ("전국", "윤코치 (씨름 윤정수)", [], "윤코치 씨름 먹방", ""),
    ("전국", "육식맨", ["yooxicman"], "육식맨 YOOXICMAN", ""),
    ("길거리", "하이푸디", ["hifoodie", "hi_foodie"], "하이푸디", ""),
    ("길거리", "푸디랜드", ["foodieland", "foodie_land"], "푸디랜드", ""),
    ("길거리", "야미보이", ["yummyboys"], "야미보이 Yummyboy", ""),
    ("길거리", "푸디버디", [], "", "UCDF-aN5luFYAM9Fnx7imo3A"),
    ("인천", "인천_레전드푸드", [], "인천 레전드푸드", ""),
    ("인천", "인천맛집-먹보스", [], "인천맛집 먹보스", ""),
    ("인천", "인천맛집 모푸디", [], "인천맛집 모푸디", ""),
    ("인천", "시소아빠 맛집탐방", [], "시소아빠 맛집탐방", ""),
]

SIDO = r"(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주|충청[남북]도|전라[남북]도|경상[남북]도)"
# 시도 + 시군구 (+ 구) + 길·로·동 이름 + 번지 — 이야기 속 지명("예산군 오가면에서")은 빼고 진짜 주소만
ADDR_RE = re.compile(SIDO + r"[가-힣]*\s+[가-힣]{1,6}(시|군|구)(\s+[가-힣]{1,6}(구|읍|면))?\s+[가-힣0-9·.]{1,15}(로|길|동|가|리)\s*\d{1,4}(-\d{1,4})?")
ROAD_RE = re.compile(r"[가-힣0-9]{1,12}(로|길)\s?\d{1,4}")
STORE_RE = re.compile(r"(상호|가게|식당|매장|업체)\s*(명|이름|정보)?\s*[:：]|📍|주소\s*[:：]|위치\s*[:：]")
PARTS = "snippet,statistics,contentDetails"


def find(handles, q, cid):
    if cid:
        it = get("channels", part=PARTS, id=cid).get("items", [])
        if it:
            return it[0], "id"
    for h in handles:
        it = get("channels", part=PARTS, forHandle=h).get("items", [])
        if it:
            return it[0], "핸들"
    if not q or searched[0] >= MAX_SEARCH:
        return None, "못 찾음"
    searched[0] += 1
    res = get("search", cost=100, part="snippet", q=q, type="channel", maxResults=3, regionCode="KR", relevanceLanguage="ko")
    items = res.get("items", [])
    if not items:
        return None, "검색 없음"
    others = " / ".join(i["snippet"]["channelTitle"] for i in items)
    it = get("channels", part=PARTS, id=items[0]["snippet"]["channelId"]).get("items", [])
    return (it[0] if it else None), f"검색({others})"


def look(ch, pages=3):
    up = ch["contentDetails"]["relatedPlaylists"]["uploads"]
    items, token = [], ""
    for _ in range(pages):  # 최근 영상 150개까지 (한 번에 50개, 1씩)
        q = {"part": "snippet", "playlistId": up, "maxResults": 50}
        if token:
            q["pageToken"] = token
        res = get("playlistItems", **q)
        items += res.get("items", [])
        token = res.get("nextPageToken", "")
        if not token:
            break
    today = dt.date.today()
    dates, addr, store, recent, sample = [], 0, 0, 0, ""
    uniq = set()
    for it in items:
        sn = it["snippet"]
        d = sn.get("description", "")
        day = sn.get("publishedAt", "")[:10]
        if day:
            dates.append(day)
            if (today - dt.date.fromisoformat(day)).days <= 90:
                recent += 1
        m = ADDR_RE.search(d)
        if m:
            addr += 1
            uniq.update(x.group(0) for x in ADDR_RE.finditer(d))
            if not sample and m:
                sample = d[m.start(): m.start() + 40].replace("\n", " ")
        if STORE_RE.search(d):
            store += 1
    return {"n": len(items), "last": max(dates) if dates else "", "recent": recent, "addr": addr, "store": store, "sample": sample, "uniq": len(uniq)}


def probe(handles):
    """제목만 있는 채널: 채널 주인이 단 댓글(고정 댓글)에 가게 정보가 있는지 최근 영상 12개로 확인"""
    for h in handles:
        try:
            it = get("channels", part=PARTS, forHandle=h).get("items", [])
            if not it:
                print(f"[확인] {h} → 못 찾음")
                continue
            ch = it[0]
            cid, title = ch["id"], ch["snippet"]["title"]
            up = ch["contentDetails"]["relatedPlaylists"]["uploads"]
            items = get("playlistItems", part="snippet", playlistId=up, maxResults=50).get("items", [])
            # 쇼츠는 빼고 보려고 영상 길이를 함께 본다
            ids = [x["snippet"]["resourceId"]["videoId"] for x in items]
            durs = {}
            for v in get("videos", part="contentDetails", id=",".join(ids)).get("items", []):
                durs[v["id"]] = v["contentDetails"].get("duration", "")
            longs = [x for x in items if not re.fullmatch(r"PT(\d+S|[0-2]M(\d+S)?|3M)", durs.get(x["snippet"]["resourceId"]["videoId"], "PT0S"))][:12]
            own = addr = 0
            sample = ""
            for x in longs:
                vid = x["snippet"]["resourceId"]["videoId"]
                try:
                    cs = get("commentThreads", part="snippet", videoId=vid, maxResults=5, order="relevance").get("items", [])
                except RuntimeError:
                    continue
                for c in cs:
                    top = c["snippet"]["topLevelComment"]["snippet"]
                    if top.get("authorChannelId", {}).get("value") == cid:
                        own += 1
                        txt = re.sub(r"<[^>]+>", " ", top.get("textDisplay", ""))
                        m = ADDR_RE.search(txt) or (STORE_RE.search(txt))
                        if m:
                            addr += 1
                            if not sample:
                                sample = txt[max(0, m.start() - 30): m.start() + 50].replace("\n", " ")
                        break
            print(f"[확인] {title} (@{h}) 긴 영상 {len(longs)}개 중 주인 댓글 {own}개 · 가게 정보 {addr}개"
                  + (f" · 예: {sample}" if sample else "")
                  + " · 제목 예: " + " / ".join(x["snippet"]["title"][:40] for x in longs[:3]))
        except Stop:
            raise
        except Exception as e:
            print(f"[확인] {h} → 오류 {str(e)[:120]}")


MIN_SUBS = int(os.environ.get("MIN_SUBS", "100000"))


def discover(words, known):
    """검색어마다 채널 50개 → 구독자 MIN_SUBS 이상 → 최근 영상 50개 중 주소가 적힌 비율"""
    ids = []
    for w in words:
        if searched[0] >= MAX_SEARCH:
            break
        searched[0] += 1
        res = get("search", cost=100, part="snippet", q=w, type="channel", maxResults=50, regionCode="KR", relevanceLanguage="ko")
        for it in res.get("items", []):
            c = it["snippet"]["channelId"]
            if c not in ids and c not in known:
                ids.append(c)
    found = []
    for i in range(0, len(ids), 50):
        for ch in get("channels", part=PARTS, id=",".join(ids[i:i + 50])).get("items", []):
            if int(ch.get("statistics", {}).get("subscriberCount", 0) or 0) >= MIN_SUBS:
                found.append(ch)
    print(f"\n[찾아보기] 검색어 {len(words)}개 → 채널 {len(ids)}개 중 구독 {MIN_SUBS:,} 이상 {len(found)}개")
    rows = []
    for ch in found:
        try:
            info = look(ch, pages=1)
        except RuntimeError:
            continue
        st, sn = ch["statistics"], ch["snippet"]
        rows.append((info["addr"] / max(info["n"], 1), int(st.get("subscriberCount", 0)), sn.get("title", ""), sn.get("customUrl", ""), ch["id"], info))
    rows.sort(key=lambda r: (r[0] >= 0.3, r[1]), reverse=True)
    for ratio, subs, title, handle, cid, info in rows:
        print(f"[찾아보기] {title} ({handle} {cid}) 구독 {subs:,} · 마지막 {info['last']} · 90일 {info['recent']}개 · 주소 {info['addr']}/{info['n']} (서로 다른 주소 {info['uniq']}곳) · 상호표시 {info['store']}/{info['n']}"
              + (f" · 예: {info['sample']}" if info["sample"] else ""))


def main():
    if not KEY:
        print("유튜브 키가 없습니다")
        return
    pr = [x.strip() for x in os.environ.get("PROBE", "").split(",") if x.strip()]
    if pr:
        try:
            probe(pr)
        except Stop as e:
            print("중단:", e)
        print(f"\n유튜브 사용량 약 {used[0]}")
        return
    rows = []
    try:
        for group, name, handles, q, cid in CANDS:
            try:
                ch, how = find(handles, q, cid)
            except RuntimeError as e:
                print(f"[{group}] {name} → 오류 {e}")
                continue
            if not ch:
                print(f"[{group}] {name} → {how}")
                continue
            st, sn = ch.get("statistics", {}), ch["snippet"]
            try:
                info = look(ch)
            except RuntimeError as e:
                print(f"[{group}] {name} → {sn.get('title', '')} 영상 목록 오류 {str(e)[:80]}")
                continue
            row = {
                "group": group, "name": name, "title": sn.get("title", ""), "handle": sn.get("customUrl", ""), "id": ch["id"],
                "subs": int(st.get("subscriberCount", 0) or 0), "videos": int(st.get("videoCount", 0) or 0), "how": how, **info,
            }
            rows.append(row)
            print(f"[{group}] {name} → {row['title']} ({row['handle']}) 구독 {row['subs']:,} · 영상 {row['videos']:,} · "
                  f"마지막 {row['last']} · 90일 {row['recent']}개 · 주소 {row['addr']}/{row['n']} (서로 다른 주소 {row['uniq']}곳) · 상호표시 {row['store']}/{row['n']} · {how}"
                  + (f" · 예: {row['sample']}" if row["sample"] else ""))
    except Stop as e:
        print("중단:", e)
    words = [x.strip() for x in os.environ.get("DISCOVER", "").split(",") if x.strip()]
    if words:
        try:
            discover(words, {r["id"] for r in rows})
        except Stop as e:
            print("중단:", e)
    print(f"\n유튜브 사용량 약 {used[0]} (이름 검색 {searched[0]}번)")
    with open("yt_check.json", "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
