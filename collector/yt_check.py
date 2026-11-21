"""유명 유튜버 따라가기 — 채널 후보 확인 (한 번만 돌려 보는 점검)

채널마다: 실제 채널 찾기(핸들 → 없으면 이름 검색), 구독자·영상 수, 최근 영상 50개 중
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
    ("전국", "풍자 또간집 (스튜디오 수제)", ["studiosuje", "studio_suje", "스튜디오수제"], "스튜디오 수제 또간집", ""),
    ("전국", "최자로드", ["choizaroad", "최자로드"], "최자로드", ""),
    ("전국", "정육왕", ["meatcreator", "정육왕"], "정육왕 MeatCreator", ""),
    ("전국", "맛상무", ["matsangmu", "맛상무"], "맛상무", ""),
    ("전국", "김사원세끼", ["김사원세끼", "kimsawon"], "김사원세끼", ""),
    ("전국", "맛있겠다 (노포 부부)", ["맛있겠다", "yummy_couple"], "맛있겠다 노포 부부 유튜버", ""),
    ("전국", "빅페이스", ["bigface", "빅페이스"], "빅페이스 먹방", ""),
    ("전국", "섬마을훈태TV", ["섬마을훈태tv", "섬마을훈태"], "섬마을훈태TV", ""),
    ("전국", "윤호찌", ["윤호찌", "yoonhozzi"], "윤호찌 맛집", ""),
    ("전국", "츄릅켠", ["츄릅켠"], "츄릅켠 맛집", ""),
    ("전국", "지뉼랭가이드", ["지뉼랭가이드", "지뉼랭"], "지뉼랭가이드", ""),
    ("전국", "회사랑", ["회사랑"], "회사랑 맛집 유튜버", ""),
    ("전국", "쯔양", ["tzuyang6145", "쯔양"], "쯔양 tzuyang", ""),
    ("전국", "히밥", ["heebab", "히밥"], "히밥 heebab", ""),
    ("전국", "입짧은햇님", ["입짧은햇님", "hatnim"], "입짧은햇님", ""),
    ("전국", "먹보스 쭈엽이", ["먹보스쭈엽이", "mukboss"], "먹보스 쭈엽이", ""),
    ("전국", "백종원 (님아 그 시장을 가오)", ["paikjongwon", "백종원"], "백종원 PAIK JONG WON", ""),
    ("전국", "이태리 파브리", [], "", "UCza_sEjIhb1yhvVZEdEl6gA"),
    ("전국", "윤코치 (씨름 윤정수)", ["윤코치", "yooncoach"], "윤코치 씨름 먹방", ""),
    ("전국", "육식맨", ["yooxicman", "육식맨"], "육식맨 YOOXICMAN", ""),
    ("길거리", "하이푸디", ["hifoodie", "하이푸디"], "하이푸디", ""),
    ("길거리", "푸디랜드", ["foodieland", "푸디랜드"], "푸디랜드", ""),
    ("길거리", "야미보이", ["yummyboy", "야미보이"], "야미보이 Yummyboy", ""),
    ("인천", "인천_레전드푸드", ["인천_레전드푸드", "인천레전드푸드"], "인천 레전드푸드", ""),
    ("인천", "인천맛집-먹보스", ["인천맛집-먹보스", "인천맛집먹보스"], "인천맛집 먹보스", ""),
    ("인천", "인천맛집 모푸디", ["모푸디", "mofoodie"], "인천맛집 모푸디", ""),
    ("인천", "시소아빠 맛집탐방", ["시소아빠", "시소아빠맛집탐방"], "시소아빠 맛집탐방", ""),
]

SIDO = r"(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주|충청[남북]도|전라[남북]도|경상[남북]도)"
ADDR_RE = re.compile(SIDO + r"[가-힣]*\s+[가-힣]{1,6}(시|군|구)\s")
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


def look(ch):
    up = ch["contentDetails"]["relatedPlaylists"]["uploads"]
    items = get("playlistItems", part="snippet", playlistId=up, maxResults=50).get("items", [])
    today = dt.date.today()
    dates, addr, store, recent, sample = [], 0, 0, 0, ""
    for it in items:
        sn = it["snippet"]
        d = sn.get("description", "")
        day = sn.get("publishedAt", "")[:10]
        if day:
            dates.append(day)
            if (today - dt.date.fromisoformat(day)).days <= 90:
                recent += 1
        m = ADDR_RE.search(d)
        if m or (ROAD_RE.search(d) and ("주소" in d or "위치" in d)):
            addr += 1
            if not sample and m:
                sample = d[m.start(): m.start() + 40].replace("\n", " ")
        if STORE_RE.search(d):
            store += 1
    return {"n": len(items), "last": max(dates) if dates else "", "recent": recent, "addr": addr, "store": store, "sample": sample}


def main():
    if not KEY:
        print("유튜브 키가 없습니다")
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
            info = look(ch)
            row = {
                "group": group, "name": name, "title": sn.get("title", ""), "handle": sn.get("customUrl", ""), "id": ch["id"],
                "subs": int(st.get("subscriberCount", 0) or 0), "videos": int(st.get("videoCount", 0) or 0), "how": how, **info,
            }
            rows.append(row)
            print(f"[{group}] {name} → {row['title']} ({row['handle']}) 구독 {row['subs']:,} · 영상 {row['videos']:,} · "
                  f"마지막 {row['last']} · 90일 {row['recent']}개 · 주소 {row['addr']}/{row['n']} · 상호표시 {row['store']}/{row['n']} · {how}"
                  + (f" · 예: {row['sample']}" if row["sample"] else ""))
    except Stop as e:
        print("중단:", e)
    print(f"\n유튜브 사용량 약 {used[0]} (이름 검색 {searched[0]}번)")
    with open("yt_check.json", "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
