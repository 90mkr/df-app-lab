"""유명 유튜버 따라가기 — 큰 맛집 채널이 영상 설명란에 적어 둔 가게 주소로 전국 지도 자료를 만든다.

채널 목록  collector/follow_channels.json   [{"name": "김사원세끼", "id": "UC…"} 또는 {"name": …, "handle": "kim3meals"}]
기억       collector/follow_cache.json      영상마다 찾은 가게, 주소마다 카카오 결과 (같은 것을 다시 묻지 않음)
결과       web/data/follow.json             가게(영상 목록 포함)·채널 정보

유튜브 사용량: 채널마다 최근 영상 50개에 1, 처음 한 번만 전체 영상 목록(50개당 1), 영상 길이 50개당 1 — 검색은 쓰지 않는다.
카카오: 새 주소마다 주소 찾기 1 + 가게 이름 찾기 1 (+ 이름이 안 맞으면 그 자리 음식점 1~2)
"""
import datetime as dt
import hashlib
import http.client
import json
import os
import re
import sys
import threading
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import collect as C  # noqa: E402  get_json·clean·norm·load_json·save_json·키

HERE = os.path.dirname(os.path.abspath(__file__))
CHANNELS = os.path.join(HERE, "follow_channels.json")
CACHE = os.path.join(HERE, "follow_cache.json")
OUT = os.path.join(HERE, "..", "web", "data", "follow.json")
YT = "https://www.googleapis.com/youtube/v3/"
MAX_PAGES = int(os.environ.get("FOLLOW_PAGES", "60"))     # 처음 한 번, 채널당 최대 3,000개
KAKAO_MAX = int(os.environ.get("FOLLOW_KAKAO", "5000"))   # 한 번에 카카오에 묻는 최대 수
SIDO_ONLY = [x.strip() for x in os.environ.get("FOLLOW_SIDO", "").split(",") if x.strip()]  # 시범: "서울"
VER = 2      # 이름 뽑는 법을 바꾸면 올린다 (영상·가게를 다시 읽음, 주소 좌표는 그대로)
BOILER = 8   # 한 채널의 영상 8개 이상에 같은 주소 → 가게가 아니라 회사·문의 주소로 본다

SIDO = r"(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주|충청[남북]도|전라[남북]도|경상[남북]도)"
# 시도 + 시군구 (+ 구·읍·면) + 길·로·동 이름 + 번지 (+ 번길 번지) — 이야기 속 지명("예산군 오가면에서")은 안 걸린다
ADDR_RE = re.compile(SIDO + r"[가-힣]*\s+[가-힣]{1,6}(시|군|구)(\s+[가-힣]{1,6}(구|읍|면))?\s+[가-힣0-9·.]{1,15}(로|길|동|가|리)"
                     r"\s*\d{1,4}(-\d{1,4})?(\s*번?길\s*\d{1,4}(-\d{1,4})?)?")
SKIP_LINE = re.compile(r"(문의|사서함|팬레터|우편|보내실|사무실|본사|회사|협찬|제휴|광고|구독|business|contact)", re.I)
GENERIC = re.compile(r"^(위치|주소|장소|location|information|info|식당\s*정보|가게\s*정보|매장\s*정보|정보|영업\s*시간|운영\s*시간|메뉴|가격|지도|네이버\s*지도|구글\s*지도)$", re.I)
NUMBERED = re.compile(r"^\s*(\d{1,2}\s*[.)]|[0-9]️?⃣|[①-⑳])")
EMOJI = re.compile(r"[\U0001F000-\U0001FAFF☀-➿⬀-⯿️⃣]")
QUOTED = re.compile(r"['‘’\"“”\[【]([^'‘’\"“”\[\]【】]{2,30})['‘’\"“”\]】]")


def yt(path, **q):
    q["key"] = C.YOUTUBE_KEY
    return C.get_json(YT + path + "?" + urllib.parse.urlencode(q))


kakao_calls = [0]
_local = threading.local()
DEADLINE = time.time() + float(os.environ.get("FOLLOW_MIN", "25")) * 60   # 이 시간이 지나면 남은 것은 다음 번에


def kakao(path, **q):
    """카카오 지역 검색 — 스레드마다 연결 하나를 계속 이어 쓴다 (매번 새로 잇는 것보다 3배쯤 빠름)"""
    kakao_calls[0] += 1
    url = f"/v2/local/{path}?" + urllib.parse.urlencode(q)
    for i in range(3):
        conn = getattr(_local, "conn", None)
        if conn is None:
            conn = _local.conn = http.client.HTTPSConnection("dapi.kakao.com", timeout=12)
        try:
            conn.request("GET", url, headers={"Authorization": f"KakaoAK {C.KAKAO_KEY}"})
            r = conn.getresponse()
            body = r.read()
            if r.status == 200:
                return json.loads(body.decode("utf-8"))
            if r.status in (429, 500, 502, 503) and i < 2:
                time.sleep(1 + i * 2)
                continue
            raise RuntimeError(f"{r.status} {body[:160]!r}")
        except (http.client.HTTPException, OSError) as e:
            try:
                conn.close()
            except Exception:
                pass
            _local.conn = None
            if i == 2:
                raise RuntimeError(f"연결 실패 {e}")
            time.sleep(1)


# ---------- 설명란에서 가게 이름·주소 뽑기 ----------

PRICE = re.compile(r"(KRW|USD|\$|₩|가격|\d{1,3}(,\d{3})+|\d+\s*원(\s|$)|영업|휴무|매주|시간|주차|예약|택배)", re.I)
LABEL = re.compile(r"^(상호\s*명?|가게\s*(명|이름)?|식당\s*(명|이름)?|매장\s*명?|업체\s*명?|장소)\s*[:：]\s*")


def clean_name(t):
    t = re.sub(r"https?://\S+", "", t or "")
    t = re.sub(r"^\s*[0-9#*]\ufe0f?\u20e3\s*", "", t)   # 1️⃣ 같은 번호 글자
    t = EMOJI.sub("", t).strip()
    t = NUMBERED.sub("", t)
    t = LABEL.sub("", t.strip())
    t = re.sub(r"\(?\s*(location|위치|주소)\s*\)?", "", t, flags=re.I)
    t = t.strip(" \t[]【】<>()-–—:：·|*#~")
    if t.count("(") != t.count(")"):
        t = t.split("(")[0]
    t = re.sub(r"\s{2,}", " ", t).strip(" -–:：·|")
    if not t or len(t) > 30 or len(C.norm(t)) < 2 or GENERIC.match(t) or ADDR_RE.search(t) or SKIP_LINE.search(t) or PRICE.search(t):
        return ""
    if re.search(r"(다|요|죠|니다|습니다)[.!~ ]*$", t) or t.endswith((".", "!", "?")):
        return ""   # 설명 문장
    return t


def bracket(t):
    m = QUOTED.search(t or "")
    return clean_name(m.group(1)) if m else ""


def name_for(lines, i, m):
    """주소가 나온 줄(i)을 기준으로 가게 이름을 찾는다."""
    line = lines[i]
    after = line[m.end():]
    before = line[:m.start()]
    # 1) 주소 뒤 '가게명' (푸디랜드) / 주소 앞 「가게명 :」
    n = bracket(after) or (clean_name(before) if before.strip(" -–:·|📍🚩") else "")
    if n:
        return n
    # 2) 위로 올라가며: 번호 붙은 줄(하이갱스·김사원세끼) > [대괄호](성시경·하이푸디) > 짧은 줄
    near = ""
    for k in range(1, 7):
        if i - k < 0:
            break
        t = lines[i - k].strip()
        if not t:
            if k > 2 and near:
                break
            continue
        if ADDR_RE.search(t):
            break   # 앞 가게의 주소까지 올라감
        if NUMBERED.match(t):
            n = bracket(t) or clean_name(t)
            if n:
                return n
        n = bracket(t)
        if n:
            return n
        if not near and k <= 2:
            near = clean_name(t)
    return near


def parse(desc):
    """설명란 → [(가게 이름, 주소)] (이름은 없을 수도)"""
    out, seen = [], set()
    lines = (desc or "").replace("\r", "").split("\n")
    for i, line in enumerate(lines):
        for m in ADDR_RE.finditer(line):
            prev = lines[i - 1] if i else ""
            if SKIP_LINE.search(line[:m.start()]) or SKIP_LINE.search(prev):
                continue
            addr = re.sub(r"\s+", " ", m.group(0)).strip()
            if addr in seen:
                continue
            seen.add(addr)
            out.append((name_for(lines, i, m), addr))
    return out[:12]


# ---------- 카카오로 자리·가게 확인 ----------

def sim(a, b):
    a, b = C.norm(C.base_name(a)), C.norm(C.base_name(b))
    if not a or not b:
        return 0.0
    if a in b or b in a:
        return 1.0
    ga = {a[i:i + 2] for i in range(len(a) - 1)} or {a}
    gb = {b[i:i + 2] for i in range(len(b) - 1)} or {b}
    return len(ga & gb) / len(ga | gb)


def geocode(addr, cache):
    g = cache["g"].get(addr)
    if g is not None:
        return g or None
    try:
        docs = kakao("search/address.json", query=addr, size=1).get("documents", [])
    except RuntimeError as e:
        print("  주소 찾기 실패:", addr, str(e)[:80])
        return None
    if not docs:
        cache["g"][addr] = {}
        return None
    d = docs[0]
    a = d.get("road_address") or d.get("address") or {}
    j = d.get("address") or {}
    g = {"x": float(d["x"]), "y": float(d["y"]), "road": (d.get("road_address") or {}).get("address_name", "") or d.get("address_name", ""),
         "s": a.get("region_1depth_name", ""), "gu": a.get("region_2depth_name", ""), "dong": j.get("region_3depth_name", "") or a.get("region_3depth_name", "")}
    cache["g"][addr] = g
    return g


def foodish(d):
    c = d.get("category_name", "")
    return d.get("category_group_code") in ("FD6", "CE7") or any(x in c for x in ("음식점", "카페", "식품", "간식", "시장", "제과", "떡", "반찬", "정육"))


def place_doc(d, g, name):
    cat = d.get("category_name", "")
    return {
        "id": str(d["id"]), "name": d.get("place_name", "") or name, "cat": C.short_category(cat), "cz": C.cuisine_of(cat),
        "kind": "cafe" if d.get("category_group_code") == "CE7" else "food",
        "addr": d.get("road_address_name") or d.get("address_name") or g["road"], "tel": d.get("phone", ""),
        "kakao": d.get("place_url", ""), "lat": round(float(d["y"]), 6), "lng": round(float(d["x"]), 6),
        "s": g["s"], "gu": g["gu"], "dong": g["dong"],
    }


def resolve(name, addr, cache):
    """(이름, 주소) → 가게 열쇠. 카카오 가게와 맞으면 그 번호, 아니면 설명란 이름+주소 그대로."""
    k = f"{name}|{addr}"
    if k in cache["r"]:
        return cache["r"][k] or None
    if kakao_calls[0] >= KAKAO_MAX or time.time() > DEADLINE:
        return "later"
    g = geocode(addr, cache)
    if not g:
        cache["r"][k] = ""
        return None
    best, score = None, 0.0
    try:
        if name:
            docs = kakao("search/keyword.json", query=name, x=g["x"], y=g["y"], radius=250, sort="distance", size=10).get("documents", [])
            for d in docs:
                s = sim(d.get("place_name", ""), name)
                if s > score and int(d.get("distance") or 9999) <= 250 and foodish(d):
                    best, score = d, s
        if score < 0.5:
            # 이름이 없거나 안 맞으면 그 주소 자리(30m 안)의 음식점·카페
            near = []
            for code in ("FD6", "CE7"):
                near += kakao("search/category.json", category_group_code=code, x=g["x"], y=g["y"], radius=30, sort="distance").get("documents", [])
            if name:
                for d in near:
                    s = sim(d.get("place_name", ""), name)
                    if s > score:
                        best, score = d, s
            elif len(near) == 1:
                best, score = near[0], 0.6
    except RuntimeError as e:
        print("  가게 찾기 실패:", name, addr, str(e)[:80])
        return "later"
    if best is not None and score >= 0.5:
        p = place_doc(best, g, name)
    elif name:
        # 카카오에 없는 가게(시장 좌판·새 가게): 설명란 이름과 주소 자리 그대로
        p = {"id": "a" + hashlib.md5(k.encode()).hexdigest()[:10], "name": name, "cat": "", "cz": "", "kind": "food",
             "addr": g["road"] or addr, "tel": "", "kakao": "", "lat": round(g["y"], 6), "lng": round(g["x"], 6),
             "s": g["s"], "gu": g["gu"], "dong": g["dong"]}
    else:
        cache["r"][k] = ""
        return None
    cache["pl"][p["id"]] = p
    cache["r"][k] = p["id"]
    return p["id"]


# ---------- 채널 영상 훑기 ----------

def iso_secs(d):
    m = re.fullmatch(r"P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", d or "")
    if not m:
        return 0
    dd, h, mi, s = (int(x or 0) for x in m.groups())
    return dd * 86400 + h * 3600 + mi * 60 + s


def channel_info(chs, cache):
    """채널 이름·사진·구독자 (핸들만 있으면 번호도 찾아 둔다)"""
    for c in chs:
        if not c.get("id") and c.get("handle"):
            it = yt("channels", part="id", forHandle=c["handle"]).get("items", [])
            if it:
                c["id"] = it[0]["id"]
    ids = [c["id"] for c in chs if c.get("id")]
    info = {}
    for i in range(0, len(ids), 50):
        for it in yt("channels", part="snippet,statistics,contentDetails", id=",".join(ids[i:i + 50])).get("items", []):
            sn, st = it["snippet"], it.get("statistics", {})
            th = sn.get("thumbnails", {})
            info[it["id"]] = {
                "name": sn.get("title", ""), "handle": sn.get("customUrl", ""),
                "thumb": (th.get("high") or th.get("medium") or th.get("default") or {}).get("url", ""),
                "subs": int(st.get("subscriberCount", 0) or 0),
                "up": it["contentDetails"]["relatedPlaylists"]["uploads"],
            }
    return info


def scan(cid, up, cache):
    """채널의 새 영상을 훑어 가게를 붙인다. 처음 한 번은 끝까지(최대 MAX_PAGES쪽)."""
    st = cache["ch"].setdefault(cid, {})
    full = st.get("full")
    vids = cache["v"]
    token, pages, new, left = "", 0, [], False
    while pages < (2 if full else MAX_PAGES):
        q = {"part": "snippet", "playlistId": up, "maxResults": 50}
        if token:
            q["pageToken"] = token
        res = yt("playlistItems", **q)
        pages += 1
        known = 0
        todo = []
        for it in res.get("items", []):
            sn = it["snippet"]
            vid = sn.get("resourceId", {}).get("videoId", "")
            if not vid or (vid in vids and not vids[vid].get("later")):
                known += 1
                continue
            found = parse(sn.get("description", ""))
            if not found:
                vids[vid] = {"c": cid, "x": 1}
                continue
            todo.append((vid, sn, found))
        pairs = list({(n, a) for _, _, f in todo for n, a in f if f"{n}|{a}" not in cache["r"]})
        if pairs:
            with ThreadPoolExecutor(6) as ex:
                list(ex.map(lambda na: resolve(na[0], na[1], cache), pairs))
        for vid, sn, found in todo:
            keys, later = [], False
            for name, addr in found:
                r = resolve(name, addr, cache)
                if r == "later":
                    later = True
                elif r:
                    keys.append(r)
            title = C.clean(sn.get("title", ""))
            vids[vid] = {"c": cid, "t": title[:90], "d": sn.get("publishedAt", "")[:10], "p": keys,
                         "sh": 1 if "#shorts" in (title + sn.get("description", "")).lower() else 0}
            if later:
                vids[vid]["later"] = 1
                left = True
            if keys:
                new.append(vid)
        token = res.get("nextPageToken", "")
        if not token or (full and known):
            break
    if not token and not left:
        st["full"] = 1
    st["seen"] = dt.date.today().isoformat()
    return new


def durations(vids, cache):
    need = [v for v in vids if "dur" not in cache["v"][v]]
    for i in range(0, len(need), 50):
        for it in yt("videos", part="contentDetails", id=",".join(need[i:i + 50])).get("items", []):
            s = iso_secs(it["contentDetails"].get("duration", ""))
            v = cache["v"][it["id"]]
            v["dur"] = s
            if s and s <= 60:
                v["sh"] = 1


# ---------- 결과 ----------

def build(chs, info, cache):
    by_ch = {}
    for vid, v in cache["v"].items():
        for k in v.get("p", []):
            by_ch.setdefault(v["c"], {}).setdefault(k, []).append(vid)
    places = {}
    for cid, ks in by_ch.items():
        nm = info.get(cid, {}).get("name", "")
        for k, vs in ks.items():
            if len(vs) >= BOILER:
                continue   # 회사·문의 주소
            p = cache["pl"].get(k)
            if not p:
                continue
            if SIDO_ONLY and not any(p["s"].startswith(x) for x in SIDO_ONLY):
                continue
            o = places.setdefault(k, {**{x: p[x] for x in ("id", "kind", "name", "cat", "cz", "addr", "tel", "kakao", "dong", "lat", "lng", "s", "gu")},
                                      "vids": [], "top": False})
            for vid in vs:
                v = cache["v"][vid]
                o["vids"].append({"id": vid, "t": v.get("t", ""), "ch": nm, "cid": cid, "date": v.get("d", ""),
                                  "dur": v.get("dur", 0), "sh": v.get("sh", 0)})
    for o in places.values():
        o["vids"].sort(key=lambda x: x["date"], reverse=True)
        o["vids"] = o["vids"][:6]
    out_ch = []
    for c in chs:
        cid = c.get("id")
        if cid not in info:
            continue
        n = sum(1 for o in places.values() if any(v["cid"] == cid for v in o["vids"]))
        out_ch.append({"id": cid, "name": info[cid]["name"], "short": c.get("name", ""), "handle": info[cid]["handle"],
                       "thumb": info[cid]["thumb"], "subs": info[cid]["subs"], "count": n})
    pl = sorted(places.values(), key=lambda o: o["vids"][0]["date"], reverse=True)
    return {"updated": dt.date.today().isoformat(), "sido": SIDO_ONLY, "channels": out_ch, "places": pl}


def debug(pairs):
    """FOLLOW_DEBUG="이름|주소;이름|주소" — 카카오가 무엇을 돌려주는지 그대로 찍어 본다"""
    for pr in pairs:
        name, addr = pr.split("|", 1)
        g = geocode(addr, {"g": {}})
        print(f"[확인] {name} | {addr} → 좌표 {g}")
        if not g:
            continue
        for d in kakao("search/keyword.json", query=name, x=g["x"], y=g["y"], radius=2000, sort="distance", size=5).get("documents", []):
            print(f"    {d.get('place_name')} | {d.get('category_name')} | {d.get('category_group_code')} | {d.get('distance')}m | {d.get('road_address_name')} | 닮음 {sim(d.get('place_name', ''), name):.2f} | 음식 {foodish(d)}")


def main():
    dbg = [x for x in os.environ.get("FOLLOW_DEBUG", "").split(";") if "|" in x]
    if dbg:
        debug(dbg)
        return
    if not C.YOUTUBE_KEY or not C.KAKAO_KEY:
        print("유튜브·카카오 키가 없어 건너뜀")
        return
    chs = C.load_json(CHANNELS, [])
    cache = C.load_json(CACHE, {})
    if cache.get("ver") != VER:
        cache = {"ver": VER, "g": cache.get("g", {})}
    for k in ("v", "g", "r", "pl", "ch"):
        cache.setdefault(k, {})
    info = channel_info(chs, cache)
    new = []
    for c in chs:
        cid = c.get("id")
        if cid not in info:
            print("채널 못 찾음:", c)
            continue
        try:
            got = scan(cid, info[cid]["up"], cache)
        except RuntimeError as e:
            print(f"{c.get('name')}: 중단 {str(e)[:120]}")
            got = []
        new += got
        print(f"{c.get('name')}: 새 가게 영상 {len(got)}개 (카카오 누적 {kakao_calls[0]})")
        C.save_json(CACHE, cache)
    try:
        durations([v for v, x in cache["v"].items() if x.get("p")], cache)
    except RuntimeError as e:
        print("영상 길이 확인 중단:", str(e)[:120])
    C.save_json(CACHE, cache)
    out = build(chs, info, cache)
    C.save_json(OUT, out)
    # 보고: 시도별 가게 수, 이름 없이 주소로만 넣은 가게 수
    by_s = {}
    for o in out["places"]:
        by_s[o["s"]] = by_s.get(o["s"], 0) + 1
    plain = sum(1 for o in out["places"] if o["id"].startswith("a"))
    print(f"따라가기: 가게 {len(out['places'])}곳 (카카오에 없는 가게 {plain}) · 시도별 {by_s} · 카카오 {kakao_calls[0]}번")
    for o in out["places"][:15]:
        print("  ", o["s"], o["gu"], o["name"], "|", o["cat"], "|", o["vids"][0]["ch"], "|", o["vids"][0]["t"][:40])


if __name__ == "__main__":
    main()
