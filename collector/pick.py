"""주소를 적지 않는 유튜버(쯔양부터) 영상 → 가게 후보 뽑기.

1) 유튜브: 채널 영상 목록 · 제목 · 설명 · 채널 주인이 단 댓글(고정 댓글은 보통 이것)
2) 구글 무료 AI(제미나이): 영상에서 실제로 찾아간 가게 이름 · 지역 단서만 뽑기 (지어내지 않게)
3) 카카오 지도 검색: 뽑은 이름으로 좌표 · 주소 후보 붙이기
4) 결과는 바로 공개하지 않고 web/data/picks.json 에 「확인 대기」로 → 관리자 화면에서 맞음/틀림/제외
5) 관리자가 「맞음」으로 고른 집(파이어베이스 picks)은 follow.json 에 그 유튜버 가게로 붙인다

다른 사이트·앱의 맛집 목록은 쓰지 않는다 (영상 글·화면에서 직접 뽑기만).
글로 못 찾은 영상은 AI가 영상 화면(간판·자막·말소리)을 직접 본다 — 대표님 목록은 「어느 영상을 먼저 볼지」와 주소 대조에만 쓴다.
유튜브 사용량: 영상 목록 50개당 1 · 영상 정보 50개당 1 · 댓글 영상당 1 — 검색은 쓰지 않는다.
"""
import datetime as dt
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
CH_FILE = os.path.join(ROOT, "pick_channels.json")
CACHE = os.path.join(ROOT, "pick_cache.json")
FB_FILE = os.path.join(ROOT, "fb.json")
# 먼저 볼 가게 이름 (대표님이 준 목록에서 쯔양 영상에 실제로 나오는 것만) — 목록을 그대로 올리지 않고, 그 이름이 나오는 영상을 먼저 AI로 본다
HINTS = os.path.join(ROOT, "pick_hints.json")
# 대표님이 준 자료로 김부장이 대신 「맞음」 처리한 것 (관리자 화면에서 대표님이 정한 것이 있으면 그쪽이 먼저)
OK_FILE = os.path.join(ROOT, "pick_ok.json")
OUT = os.path.join(ROOT, "..", "web", "data", "picks.json")
FOLLOW = os.path.join(ROOT, "..", "web", "data", "follow.json")
YT = "https://www.googleapis.com/youtube/v3/"
YT_KEY = os.environ.get("YOUTUBE_KEY", "")
KAKAO = os.environ.get("KAKAO_REST_KEY", "")
GEM = os.environ.get("GEMINI_API_KEY", "")
MAX = int(os.environ.get("PICK_MAX", "120") or 120)  # 한 번에 AI로 볼 영상 수 (무료 한도 안에서)
GAP = float(os.environ.get("PICK_GAP", "4.5") or 4.5)  # AI 부르는 사이 쉬는 초 (무료 등급 분당 한도)
MINUTES = float(os.environ.get("PICK_MIN", "36") or 36)
VMAX = int(os.environ.get("PICK_VIDEO_MAX", "40") or 40)  # 글로 못 찾은 영상 중 한 번에 화면까지 볼 영상 수 (대표님 목록·확인 대기 영상은 따로 늘 봄)
VSECS = 300  # 한 집 영상은 앞 5분만 본다 (도착·간판이 보통 앞에 나옴)
VER = 1
START = time.time()

# 인천 먼저: 제목·설명에 이런 말이 있으면 앞에서 본다
INCHEON = ["인천", "송도", "영종도", "영종", "을왕리", "월미도", "차이나타운", "신포", "부평", "구월동", "주안", "청라", "검단",
           "계양", "연수구", "남동구", "미추홀", "강화도", "동인천", "작전동", "용현동", "만수동", "소래포구"]


def load(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))


def get(url, headers=None, data=None, tries=3, timeout=30):
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, data=data, headers=headers or {})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")[:300]
            if e.code in (400, 401, 403, 404):
                raise RuntimeError(f"{e.code} {body}")
            last = RuntimeError(f"{e.code} {body}")
            time.sleep(3 + i * 5)
        except Exception as e:
            last = e
            time.sleep(2 + i * 3)
    raise last


def yt(path, **q):
    q["key"] = YT_KEY
    return get(YT + path + "?" + urllib.parse.urlencode(q))


def iso_secs(d):
    m = re.match(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", d or "")
    return (int(m.group(1) or 0) * 3600 + int(m.group(2) or 0) * 60 + int(m.group(3) or 0)) if m else 0


# ---- 1. 유튜브 ----
def channel(c, cache):
    h = cache["ch"].setdefault(c["handle"], {})
    if not h.get("id"):
        j = yt("channels", part="id,snippet,contentDetails", forHandle=c["handle"])
        it = (j.get("items") or [None])[0]
        if not it:
            raise RuntimeError(f"채널을 못 찾음: {c['handle']}")
        h.update({"id": it["id"], "up": it["contentDetails"]["relatedPlaylists"]["uploads"],
                  "title": it["snippet"]["title"],
                  "thumb": (it["snippet"]["thumbnails"].get("high") or it["snippet"]["thumbnails"].get("default") or {}).get("url", "")})
    return h


def new_videos(h, cache):
    """영상 목록: 처음엔 전부, 다음부터는 아는 영상이 나올 때까지만."""
    known = set(h.get("vids", []))
    got, token = [], ""
    while True:
        q = {"part": "contentDetails", "playlistId": h["up"], "maxResults": 50}
        if token:
            q["pageToken"] = token
        j = yt("playlistItems", **q)
        ids = [it["contentDetails"]["videoId"] for it in j.get("items", [])]
        fresh = [v for v in ids if v not in known]
        got += fresh
        token = j.get("nextPageToken", "")
        if not token or (known and len(fresh) < len(ids)):
            break
    h["vids"] = got + h.get("vids", [])
    # 새 영상 정보 (제목·설명·길이)
    for i in range(0, len(got), 50):
        j = yt("videos", part="snippet,contentDetails", id=",".join(got[i:i + 50]))
        for it in j.get("items", []):
            s = it["snippet"]
            cache["v"][it["id"]] = {"t": s["title"], "d": s.get("description", "")[:2500], "date": s["publishedAt"][:10],
                                    "dur": iso_secs(it["contentDetails"].get("duration")), "cid": h["id"]}
    return got


def owner_comments(vid, cid):
    try:
        j = yt("commentThreads", part="snippet", videoId=vid, maxResults=20, order="relevance", textFormat="plainText")
    except Exception:
        return []  # 댓글이 닫힌 영상
    out = []
    for it in j.get("items", []):
        s = it["snippet"]["topLevelComment"]["snippet"]
        if (s.get("authorChannelId") or {}).get("value") == cid:
            out.append(s.get("textOriginal", "")[:1200])
    return out


# ---- 2. 구글 무료 AI ----
def gem_model():
    j = get(f"https://generativelanguage.googleapis.com/v1beta/models?pageSize=200&key={GEM}")
    ms = [m["name"] for m in j.get("models", []) if "generateContent" in m.get("supportedGenerationMethods", [])]

    def rank(n):
        odd = any(x in n for x in ("exp", "preview", "image", "tts", "live", "audio", "thinking", "embed", "learnlm", "gemma"))
        v = re.findall(r"gemini-(\d+(?:\.\d+)?)", n)
        return (not odd, "flash" in n, "lite" in n, float(v[0]) if v else 0.0)

    ms.sort(key=rank, reverse=True)
    if not ms:
        raise RuntimeError("쓸 수 있는 AI 모델이 없음")
    return ms[0]


PROMPT = """너는 한국 먹방 유튜브 영상에서 실제로 찾아간 음식점·카페를 찾아 주는 도우미야.
아래 영상 제목·설명·채널 주인 댓글만 보고 답해.
- 글에 가게 이름이 그대로 나온 것만 뽑아. 추측해서 이름을 지어내지 마.
- 지역 단서(시·구·동·역·시장 이름, 주소 일부)가 있으면 같이 적어.
- 집에서 먹는 영상, 배달·편의점·밀키트·협찬 상품 소개, 광고 문구 속 브랜드는 가게가 아니야.
- 여러 곳을 갔으면 모두.
JSON으로만 답해: {"places":[{"name":"가게 이름","region":"지역 단서 또는 빈칸","evidence":"근거가 된 짧은 구절","confidence":0~1}]}
찾아간 가게가 없으면 {"places":[]}

제목: %s
설명: %s
채널 주인 댓글: %s"""


class AiStop(Exception):
    pass


def ask_ai(model, v):
    text = PROMPT % (v["t"], v["d"][:1800], " / ".join(v.get("cmt", []))[:1500] or "없음")
    body = json.dumps({"contents": [{"role": "user", "parts": [{"text": text}]}],
                       "generationConfig": {"responseMimeType": "application/json", "temperature": 0.1}}).encode("utf-8")
    url = f"https://generativelanguage.googleapis.com/v1beta/{model}:generateContent?key={GEM}"
    for i in range(3):
        try:
            j = get(url, headers={"Content-Type": "application/json"}, data=body, tries=1, timeout=60)
            t = j["candidates"][0]["content"]["parts"][0]["text"]
            return json.loads(t).get("places", [])
        except RuntimeError as e:
            if str(e).startswith("429") or "RESOURCE_EXHAUSTED" in str(e):
                if i == 2:
                    raise AiStop("AI 무료 한도에 닿음 — 다음에 이어서")
                time.sleep(65)
                continue
            raise
        except (KeyError, IndexError, json.JSONDecodeError):
            return []
    return []


PROMPT_V = """이 영상은 한국 먹방 유튜버가 음식점을 찾아간 영상이야. 영상 제목: %s
화면의 간판·현수막·메뉴판·자막과 말소리에서 실제로 찾아간 가게 이름을 찾아.
- 화면에 보이거나 말로 들린 이름만 적어. 추측해서 지어내지 마. 지나가다 보인 다른 가게 간판은 빼.
- 지점명(○○점)이 보이면 이름에 같이 적어.
- 지역 단서(시·구·동·역·시장 이름, 주소 일부)가 보이거나 들리면 같이 적어. 제목에 나온 지역도 써도 돼.
- 여러 곳을 갔으면 모두.
JSON으로만 답해: {"places":[{"name":"가게 이름","region":"지역 단서 또는 빈칸","how":"간판|자막|메뉴판|말","evidence":"본 것·들은 것 짧게","confidence":0~1}]}
가게 이름을 확인하지 못하면 {"places":[]}"""

MULTI = re.compile(r"털기|털었|털러|투어|3대|어디가|모음|시장|골목|길거리")


def vclip(v):
    """볼 구간: 한 집 영상은 앞 5분, 여러 집을 도는 영상은 처음부터 끝까지 듬성듬성."""
    dur = int(v.get("dur") or 0)
    if MULTI.search(v.get("t", "")) and dur > VSECS:
        return 0, min(dur, 1800), 0.2
    return 0, (min(dur, VSECS) if dur else VSECS), 0.4


def ask_video(model, vid, v):
    a, b, fps = vclip(v)
    body = json.dumps({"contents": [{"role": "user", "parts": [
        {"fileData": {"fileUri": f"https://www.youtube.com/watch?v={vid}"},
         "videoMetadata": {"startOffset": f"{a}s", "endOffset": f"{b}s", "fps": fps}},
        {"text": PROMPT_V % v.get("t", "")}]}],
        "generationConfig": {"responseMimeType": "application/json", "temperature": 0.1}}).encode("utf-8")
    url = f"https://generativelanguage.googleapis.com/v1beta/{model}:generateContent?key={GEM}"
    for i in range(3):
        try:
            j = get(url, headers={"Content-Type": "application/json"}, data=body, tries=1, timeout=300)
            t = json.loads(j["candidates"][0]["content"]["parts"][0]["text"])
            ps = t.get("places", []) if isinstance(t, dict) else t
            return [x for x in ps if isinstance(x, dict)] if isinstance(ps, list) else []
        except RuntimeError as e:
            busy = str(e).startswith("503") or "UNAVAILABLE" in str(e)
            if str(e).startswith("429") or "RESOURCE_EXHAUSTED" in str(e) or busy:
                if i == 2:
                    if busy:
                        raise
                    raise AiStop("AI 무료 한도에 닿음 — 영상 보기는 다음에 이어서")
                time.sleep(25 if busy else 65)
                continue
            raise
        except (KeyError, IndexError, json.JSONDecodeError):
            return []
    return []


# ---- 3. 카카오 ----
def norm(s):
    s = re.sub(r"\s+|본점|[0-9]+호점|직영점|\(.*?\)", "", s or "")
    return s.lower()


def sim(a, b):
    a, b = norm(a), norm(b)
    if not a or not b:
        return 0.0
    if a in b or b in a:
        return 1.0
    sa, sb = set(a), set(b)
    return len(sa & sb) / max(len(sa), len(sb))


def tight(a, b):
    """지점명을 떼고 비교: 같으면 1, 한쪽이 다른 쪽에 들어 있고 길이가 비슷하면 0.9, 아니면 글자 겹침."""
    cut = lambda x: norm(re.sub(r"\s*[가-힣A-Za-z0-9]+점$", "", (x or "").strip()) or x)
    a, b = cut(a), cut(b)
    if not a or not b:
        return 0.0
    if a == b:
        return 1.0
    sh, lo = sorted((a, b), key=len)
    if sh in lo:
        return 0.9 if len(sh) / len(lo) >= 0.6 else 0.5
    sa, sb = set(a), set(b)
    return len(sa & sb) / max(len(sa), len(sb))


def kakao(q):
    url = "https://dapi.kakao.com/v2/local/search/keyword.json?" + urllib.parse.urlencode({"query": q, "size": 5})
    j = get(url, headers={"Authorization": f"KakaoAK {KAKAO}"})
    return [{"id": d["id"], "name": d["place_name"], "addr": d.get("road_address_name") or d.get("address_name", ""),
             "jibun": d.get("address_name", ""),
             "cat": d.get("category_name", ""), "g": d.get("category_group_code", ""), "lat": float(d["y"]), "lng": float(d["x"]),
             "url": d.get("place_url", "")} for d in j.get("documents", [])]


def match(p):
    name, region = (p.get("name") or "").strip(), (p.get("region") or "").strip()
    cands = []
    for q in ([f"{region} {name}"] if region else []) + [name]:
        try:
            cands = kakao(q)
        except Exception as e:
            print("카카오 찾기 실패", q, str(e)[:80])
            cands = []
        if not re.search(r"시장|골목|거리", name):  # 시장·골목 영상은 시장 자체를 찾는다
            cands = [c for c in cands if c["g"] in ("FD6", "CE7")] or cands
        if cands:
            break
    best, score = -1, 0.0
    for i, c in enumerate(cands):
        s = sim(name, c["name"]) + (0.15 if region and any(t in c["addr"] for t in region.split()) else 0)
        if s > score:
            best, score = i, s
    conf = float(p.get("confidence") or 0) * 0.5 + min(score, 1.0) * 0.5
    return rescore({"name": name, "region": region, "why": (p.get("evidence") or "")[:120], "conf": round(conf, 2),
                    "cands": cands[:5], "best": best, "check": best < 0 or conf < 0.7})


# 지역 단서가 주소와 맞는지: 시·군·구·도 같은 큰 이름이 하나도 안 맞으면 다른 곳으로 본다
# (동·역·골목 같은 작은 이름은 도로명 주소에 안 나오는 일이 많아 맞을 때만 쓴다)
BIG = re.compile(r"^(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)|(?:특별시|광역시|특별자치도|특별자치시|도|시|군|구)$")


def region_ok(region, addr):
    toks = [t for t in re.split(r"[\s/,·()]+", region or "") if len(t) >= 2]
    if not toks:
        return None
    big = False
    for t in toks:
        cut = re.sub(r"(특별시|광역시|특별자치도|특별자치시|역|점|시장|골목|도)$", "", t)
        if t in addr or (len(cut) >= 2 and cut in addr):
            return True
        if BIG.search(t) or not re.search(r"(동|로|길|역|점|시장|골목|거리|리)$", t):
            big = True
    return False if big else None


def auto_ok(p, v):
    """사람 확인 없이 맞음으로 해도 되는 확실한 후보: 의심 표시 없음 + 고른 가게 이름(지점명 뺀)이 영상 제목에 그대로 있음
    + 음식점·카페(또는 시장) + 여러 지점 광고가 아님."""
    if p.get("check") or p.get("manual") or p.get("best", -1) < 0 or float(p.get("conf") or 0) < 0.8:
        return False
    c = p["cands"][p["best"]]
    core = norm(re.sub(r"\s*([가-힣A-Za-z0-9]+점)$", "", c.get("name", "")))
    if len(core) < 2 or core not in norm(v.get("t", "")):
        return False
    if re.search(r"털기|털었|털러|투어|3대|어디가|모음|여러", v.get("t", "")):  # 여러 집을 도는 영상은 어느 집인지 사람이 봐야
        return False
    if c.get("g") not in ("FD6", "CE7") and "시장" not in c.get("name", ""):
        return False
    if "유료광고" in v.get("d", "") and sum(1 for x in p.get("cands", []) if sim(p.get("name", ""), x.get("name", "")) >= 0.9) >= 2:
        return False
    return True


def addr_keys(s):
    """주소에서 도로명+건물번호, 동+지번을 뽑는다 (띄어쓰기 없이)."""
    s = s or ""
    out = set()
    for m in re.finditer(r"([가-힣0-9]+(?:로|길))\s*(\d+(?:-\d+)?)", s):
        out.add(m.group(1) + m.group(2))
    for m in re.finditer(r"([가-힣]+[0-9]*(?:동|가|리))\s+(\d+(?:-\d+)?)", s):
        out.add(m.group(1) + m.group(2))
    return out


def addr_close(ha, c):
    """대표님 목록의 주소와 카카오 주소가 같은 건물인지. 'weak' = 목록 주소가 「○○구 일대」처럼 흐릴 때 구까지만 맞음."""
    ca = (c.get("addr", "") or "") + " " + (c.get("jibun", "") or "")
    hk, ck = addr_keys(ha), addr_keys(ca)
    if hk:
        return "same" if hk & ck else None
    gus = [t for t in re.split(r"[\s(),/]+", ha or "") if len(t) >= 2 and re.search(r"(구|군|시)$", t)]
    return "weak" if gus and all(t in ca for t in gus) else None


def hint_pick(p, hints):
    """AI가 영상에서 읽은 이름이 대표님 목록의 가게와 같고, 카카오 후보 주소도 목록 주소와 맞으면 그 후보."""
    for h in hints:
        hn, ha = h.get("name", ""), h.get("addr", "")
        if not hn or not ha or max(sim(p.get("name", ""), hn), sim(p.get("vname", ""), hn)) < 0.75:
            continue
        br = re.search(r"([가-힣A-Za-z0-9]+)점$", hn.strip())  # 지점이 적힌 체인점은 영상에서도 그 지점 단서가 보여야
        if br and br.group(1) not in ("본", "직영") and br.group(1)[:2] not in (p.get("name", "") + p.get("region", "") + p.get("_t", "")):
            continue
        for c in p.get("cands") or []:
            if sim(c.get("name", ""), hn) < 0.75:
                continue
            how = addr_close(ha, c)
            if how == "same" or (how == "weak" and tight(c.get("name", ""), hn) >= 0.85 and max(sim(p.get("name", ""), hn), sim(p.get("vname", ""), hn)) >= 0.9):
                return c, h
    return None


def video_ok(p):
    """영상 화면에서 읽은 가게의 자동 맞음: 간판·자막·메뉴판에서 읽음 + 카카오 이름이 거의 같음 + 지역이 맞거나 같은 이름이 하나뿐."""
    if p.get("src") != "video" or p.get("check") or p.get("best", -1) < 0 or float(p.get("conf") or 0) < 0.8:
        return False
    if not any(w in (p.get("how") or "") for w in ("간판", "자막", "메뉴판")):
        return False
    c = p["cands"][p["best"]]
    if tight(p.get("name", ""), c.get("name", "")) < 0.85:
        return False
    if c.get("g") not in ("FD6", "CE7") and "시장" not in c.get("name", ""):
        return False
    rk = region_ok(p.get("region", ""), c.get("addr", "") + " " + c.get("jibun", ""))
    if rk is False:
        return False
    if rk is None and len(p.get("cands") or []) != 1:  # 지역 단서가 없으면 카카오에 그 이름이 딱 한 곳일 때만
        return False
    return True


def seen_ok(p):
    """글로 찾은 후보를 영상 화면에서도 같은 가게(같은 카카오 장소)로 읽었고, 읽은 이름이 카카오 이름과 맞으면."""
    if not p.get("vseen") or p.get("best", -1) < 0 or not any(w in p.get("vseen", "") for w in ("간판", "자막", "메뉴판")):
        return False
    if "지역이 다름" in (p.get("note") or "") or "같은 이름이 여러 곳" in (p.get("note") or ""):
        return False
    return tight(p.get("vname", ""), p["cands"][p["best"]].get("name", "")) >= 0.8


def rescore(m):
    """뽑은 후보를 다시 따져 「확인 필요」와 그 까닭을 단다 (카카오를 다시 부르지 않음)."""
    cands, best = m.get("cands") or [], m.get("best", -1)
    notes = []
    if best < 0 or best >= len(cands):
        notes.append("카카오에서 못 찾음")
    else:
        c = cands[best]
        if region_ok(m.get("region", ""), c.get("addr", "") + " " + c.get("jibun", "")) is False:
            notes.append("지역이 다름")
        if c.get("g") not in ("FD6", "CE7") and not re.search(r"시장|골목|거리", m.get("name", "") + c.get("name", "")):
            notes.append("음식점이 아님")
        if sim(m.get("name", ""), c.get("name", "")) < 0.6:
            notes.append("이름이 다름")
        if "시장" in m.get("name", "") and "시장" not in c.get("cat", ""):
            notes.append("시장 안 가게로 찾음")
        if not m.get("region") and sum(1 for x in cands if sim(m.get("name", ""), x.get("name", "")) >= 0.9) >= 2:
            notes.append("같은 이름이 여러 곳")
    m["note"] = " · ".join(notes)
    m["check"] = bool(notes) or float(m.get("conf") or 0) < 0.7
    return m


# ---- 5. 관리자가 고른 집 → 따라가기 자료에 붙이기 ----
def fs_value(v):
    for k in ("stringValue", "booleanValue", "doubleValue", "timestampValue"):
        if k in v:
            return v[k]
    if "integerValue" in v:
        return int(v["integerValue"])
    if "arrayValue" in v:
        return [fs_value(x) for x in v["arrayValue"].get("values", [])]
    if "mapValue" in v:
        return {k: fs_value(x) for k, x in v["mapValue"].get("fields", {}).items()}
    return None


def decisions():
    fb = load(FB_FILE, {})
    if not fb.get("projectId"):
        return {}
    out, token = {}, ""
    for _ in range(40):
        url = (f"https://firestore.googleapis.com/v1/projects/{fb['projectId']}/databases/(default)/documents/picks?pageSize=300"
               + (f"&key={fb['apiKey']}" if fb.get("apiKey") else "") + (f"&pageToken={urllib.parse.quote(token)}" if token else ""))
        j = get(url)
        for d in j.get("documents", []):
            out[d["name"].rsplit("/", 1)[1]] = {k: fs_value(x) for k, x in d.get("fields", {}).items()}
        token = j.get("nextPageToken", "")
        if not token:
            break
    return out


def publish(cache, chans, dec):
    """맞음으로 고른 집을 follow.json 에 그 유튜버 가게로 붙인다 (이미 있는 가게면 영상만 더함)."""
    ok = [d for d in dec.values() if d.get("status") == "ok" and isinstance(d.get("place"), dict)]
    if not ok:
        return 0
    f = load(FOLLOW, {})
    if not f.get("places"):
        return 0
    places = f["places"]
    by_id = {str(p.get("id")): p for p in places}
    rows = {c.get("id"): c for c in f.setdefault("channels", [])}
    added = 0
    for d in ok:
        pl, vid = d["place"], d.get("vid", "")
        v = cache["v"].get(vid, {})
        cid = v.get("cid") or d.get("cid", "")
        ch = next((c for c in chans if c.get("id") == cid), {})
        video = {"id": vid, "t": v.get("t", d.get("t", "")), "ch": ch.get("name", ""), "cid": cid, "date": v.get("date", ""),
                 "dur": v.get("dur", 0), "sh": 1 if 0 < v.get("dur", 0) <= 60 else 0}
        pid = str(pl.get("id", ""))
        if not pid:
            continue
        p = by_id.get(pid)
        if not p:
            addr = pl.get("addr", "")
            parts = addr.split()
            cats = [x.strip() for x in (pl.get("cat") or "").split(">")]
            p = {"id": pid, "kind": "cafe" if pl.get("g") == "CE7" else "food", "name": pl.get("name", ""), "cat": cats[-1] if cats else "",
                 "cz": cats[1] if len(cats) > 1 else "", "addr": addr, "tel": "", "kakao": pl.get("url", ""), "dong": "",
                 "lat": pl.get("lat", 0), "lng": pl.get("lng", 0), "s": parts[0] if parts else "", "gu": parts[1] if len(parts) > 1 else "",
                 "vids": [], "top": False, "pick": True}
            places.append(p)
            by_id[pid] = p
            added += 1
        if not any(x.get("id") == vid for x in p.setdefault("vids", [])):
            p["vids"].append(video)
        if cid and ch and cid not in rows:
            row = {"id": cid, "name": ch.get("name", ""), "short": ch.get("name", ""), "handle": "@" + ch.get("handle", ""),
                   "thumb": ch.get("thumb", ""), "subs": 0, "count": 0}
            f["channels"].append(row)
            rows[cid] = row
    for c in f["channels"]:
        c["count"] = sum(1 for p in places if any(x.get("cid") == c.get("id") for x in p.get("vids", [])))
    save(FOLLOW, f)
    return added


def main():
    if not (YT_KEY and KAKAO):
        print("열쇠가 없습니다: YOUTUBE_KEY · KAKAO_REST_KEY")
        return
    chans = load(CH_FILE, [])
    cache = load(CACHE, {})
    if cache.get("ver") != VER:
        cache = {"ver": VER, "ch": {}, "v": {}, "ai": {}}
    rows = []
    for c in chans:
        try:
            h = channel(c, cache)
            n = new_videos(h, cache)
            c["id"], c["thumb"] = h["id"], h.get("thumb", "")
            print(f"{c['name']}: 영상 {len(h.get('vids', []))}개 (새 영상 {len(n)})")
            rows += [(vid, c) for vid in h.get("vids", [])]
        except Exception as e:
            print("유튜브 받기 실패", c.get("name"), str(e)[:200])
    save(CACHE, cache)

    if GEM:
        model = gem_model()
        print("AI 모델:", model)

        # 아직 안 본 영상: 인천 먼저, 그다음 최근 영상부터 (1분 넘는 영상만 — 쇼츠는 정보가 거의 없음)
        hint_rows = load(HINTS, [])
        hints = [norm(h.get("name", "")) for h in hint_rows if norm(h.get("name", ""))]
        areas = [a for h in hint_rows for a in h.get("areas", []) if a]  # 이름은 안 나와도 그 동네 영상은 고정 댓글까지 먼저 본다

        def key(vc):
            v = cache["v"].get(vc[0], {})
            text = v.get("t", "") + " " + v.get("d", "")[:600]
            raw = v.get("t", "") + " " + v.get("d", "")
            full = norm(raw)
            return (any(h in full for h in hints), any(a in raw for a in areas), any(k in text for k in INCHEON), v.get("date", ""))

        todo = [vc for vc in rows if vc[0] in cache["v"] and vc[0] not in cache["ai"] and cache["v"][vc[0]].get("dur", 0) > 60]
        todo.sort(key=key, reverse=True)
        done = 0
        for vid, c in todo[:MAX]:
            if time.time() - START > MINUTES * 60:
                print("시간이 다 되어 다음에 이어서")
                break
            v = cache["v"][vid]
            v["cmt"] = owner_comments(vid, c["id"])
            try:
                ps = ask_ai(model, v)
            except AiStop as e:
                print(e)
                break
            except Exception as e:
                print("AI 실패", vid, str(e)[:160])
                time.sleep(GAP)
                continue
            cache["ai"][vid] = {"at": dt.date.today().isoformat(), "p": [match(p) for p in ps if (p.get("name") or "").strip()]}
            v["d"] = v.get("d", "")[:600]  # 본 영상은 설명 앞부분만 남긴다 (저장소가 불어나지 않게)
            v.pop("cmt", None)
            done += 1
            if done % 10 == 0:
                save(CACHE, cache)
            time.sleep(GAP)
        save(CACHE, cache)
        print(f"AI로 본 영상 {done}개 · 남은 영상 {max(0, len(todo) - done)}개")
    else:
        print("구글 AI 키(GEMINI_API_KEY)가 아직 없어 후보 뽑기는 건너뜀")

    # 4. 후보 목록 (확인 대기) — 관리자가 이미 정한 것도 그대로 실어 둔다 (화면에서 정한 표시)
    try:
        dec = decisions()
    except Exception as e:
        print("관리자 결정 받기 실패:", str(e)[:120])
        dec = {}
    # 김부장이 대표님 위임으로 정한 것 (관리자 화면에서 대표님이 정한 것이 있으면 그쪽이 먼저)
    auto = {k: v for k, v in load(OK_FILE, {}).items() if k not in dec}
    # 「다시 찾아 맞음」: 카카오로 다시 찾아 주소에 그 말이 든 첫 가게를 그 영상의 가게로 (처음 뽑힌 틀린 후보는 제외)
    for qk, e in list(auto.items()):
        if e.get("status") != "ok_query":
            continue
        del auto[qk]
        vid = e.get("vid", "")
        a = cache["ai"].setdefault(vid, {"at": dt.date.today().isoformat(), "p": []})
        found = next((x["cands"][0] for x in a["p"] if x.get("manual") and x.get("name") == e.get("query", "") and x.get("cands")), None)
        try:
            for dd in ([] if found else kakao(e.get("query", ""))):
                if e.get("addr", "") in (dd.get("addr", "") + " " + dd.get("jibun", "")):
                    found = dd
                    break
        except Exception as ex:
            print("다시 찾기 실패:", e.get("query"), str(ex)[:80])
        if not found:
            print("다시 찾기 — 카카오에 없음 (처음 후보는 제외):", e.get("query"))
            for rk in e.get("replace", []):
                if rk not in dec and rk not in auto:
                    auto[rk] = {"status": "skip", "vid": vid, "why": "카카오에서 찾지 못함 — 문을 닫았을 수 있음", "by": e.get("by", "")}
            continue
        idx = next((i for i, x in enumerate(a["p"]) if x.get("manual") and x.get("cands") and x["cands"][0].get("id") == found.get("id")), -1)
        if idx < 0:
            a["p"].append({"name": e.get("query", ""), "region": e.get("addr", ""), "why": "김부장이 다시 찾음", "conf": 1.0,
                           "cands": [found], "best": 0, "check": False, "note": "", "manual": True})
            idx = len(a["p"]) - 1
        key = f"{vid}_{idx}"
        if key not in dec:
            auto[key] = {"status": "ok", "vid": vid, "cid": e.get("cid", ""), "t": e.get("t", ""), "place": found, "by": e.get("by", "")}
        for rk in e.get("replace", []):
            if rk != key and rk not in dec and rk not in auto:
                auto[rk] = {"status": "skip", "vid": vid, "why": "다시 찾은 가게로 바꿈", "by": e.get("by", "")}
        print("다시 찾아 맞음:", e.get("query"), "→", found.get("name"), found.get("addr"))
    # 관리자가 「직접 연결」로 적은 가게 이름: 카카오로 찾아 그 영상의 후보로 더한다 (다시 확인)
    for k, d in dec.items():
        q = (d.get("query") or "").strip()
        vid = d.get("vid", "")
        if d.get("status") != "manual" or not q or not vid:
            continue
        a = cache["ai"].setdefault(vid, {"at": dt.date.today().isoformat(), "p": []})
        if not any(x.get("name") == q and x.get("manual") for x in a["p"]):
            m = match({"name": q, "region": d.get("region", ""), "confidence": 1})
            m["manual"] = True
            a["p"].append(m)
            print("직접 연결 후보:", q)
    save(CACHE, cache)

    # 2-2. 영상 화면 보기: 대표님 목록이 가리킨 영상 → 아직 못 정한 후보 영상 → 글로 못 찾은 영상(하루 VMAX개)
    hint_rows = load(HINTS, [])
    if GEM:
        vchk = cache.setdefault("vchk", {})
        by_vid = {vid: c for vid, c in rows}
        want = []
        for h in hint_rows:
            want += h.get("vids", [])
        for vid, a in cache["ai"].items():
            if any(f"{vid}_{i}" not in dec and f"{vid}_{i}" not in auto for i in range(len(a.get("p", [])))):
                want.append(vid)
        general = [vid for vid, a in sorted(cache["ai"].items(), key=lambda x: cache["v"].get(x[0], {}).get("date", ""), reverse=True)
                   if not a.get("p")][:VMAX]
        seen, order = set(), []
        for vid in want + general:
            if vid in by_vid and vid in cache["v"] and vid not in vchk and vid not in seen:
                seen.add(vid)
                order.append(vid)
        print(f"영상 화면 볼 영상 {len(order)}개")
        vdone, vfail = 0, 0
        for vid in order:
            if time.time() - START > MINUTES * 60:
                print("시간이 다 되어 영상 보기는 다음에 이어서")
                break
            v, c = cache["v"][vid], by_vid[vid]
            today = dt.date.today().isoformat()
            try:
                if vid not in cache["ai"]:  # 글도 아직 안 봤으면 글 먼저
                    v["cmt"] = owner_comments(vid, c["id"])
                    ps0 = ask_ai(model, v)
                    cache["ai"][vid] = {"at": today, "p": [match(x) for x in ps0 if (x.get("name") or "").strip()]}
                    v["d"] = v.get("d", "")[:600]
                    v.pop("cmt", None)
                    time.sleep(GAP)
                ps = ask_video(model, vid, v)
            except AiStop as e:
                print(e)
                break
            except Exception as e:
                vfail += 1
                print("영상 보기 실패", vid, str(e)[:200])
                if vdone and str(e).startswith(("400", "403", "404")):  # 비공개·막힌 영상은 다시 보지 않음
                    vchk[vid] = {"at": today, "err": str(e)[:80]}
                if vfail >= 4 and vdone == 0:
                    print("영상 보기가 되지 않아 멈춤")
                    break
                time.sleep(GAP)
                continue
            a = cache["ai"][vid]
            ids = {x["cands"][x["best"]]["id"]: x for x in a["p"] if x.get("best", -1) >= 0 and x.get("cands")}
            got = []
            for x in ps:
                if not (x.get("name") or "").strip():
                    continue
                m = match(x)
                m["src"], m["how"] = "video", (x.get("how") or "")[:6]
                bid = m["cands"][m["best"]]["id"] if m.get("best", -1) >= 0 and m.get("cands") else None
                if bid and bid in ids:  # 글로 찾은 것과 같은 가게 → 그 후보에 영상으로도 확인했다고 표시
                    ids[bid]["vseen"], ids[bid]["vname"] = m["how"] or "영상", (x.get("name") or "")[:40]
                    got.append(f"{x.get('name')}({m['how']}·글과 같음)")
                    continue
                if not bid or sim(m["name"], m["cands"][m["best"]]["name"]) < 0.6:  # 카카오에 없거나 이름이 다르면 후보로 올리지 않고 기록만
                    got.append(f"{x.get('name')}({m['how']}) → " + ("카카오에 없음" if not bid else f"맞는 가게 없음 ({m['cands'][m['best']]['name']})"))
                    continue
                a["p"].append(m)
                ids[bid] = m
                got.append(f"{x.get('name')}({m['how']}) → " + (f"{m['cands'][m['best']]['name']} {m['cands'][m['best']]['addr']}" if bid else "카카오에 없음"))
            vchk[vid] = {"at": today, "n": len(ps)}
            vdone += 1
            print("영상 보기:", vid, v.get("t", "")[:28], "→", " / ".join(got) or "이름 못 읽음")
            if vdone % 5 == 0:
                save(CACHE, cache)
            time.sleep(GAP)
        save(CACHE, cache)
        print(f"영상 화면 본 영상 {vdone}개")

    items, nofind = [], []
    for vid, c in rows:
        a = cache["ai"].get(vid)
        v = cache["v"].get(vid, {})
        if a is None:
            continue
        if not a["p"]:
            text = v.get("t", "") + " " + v.get("d", "")[:600]
            nofind.append({"vid": vid, "t": v.get("t", ""), "date": v.get("date", ""), "ch": c["name"], "inc": any(k in text for k in INCHEON)})
            continue
        for i, p in enumerate(a["p"]):
            if not p.get("manual"):
                rescore(p)
            key = f"{vid}_{i}"
            it = {"key": key, "vid": vid, "t": v.get("t", ""), "date": v.get("date", ""), "ch": c["name"], "cid": c.get("id", ""),
                  **p, "inc": any(k in (v.get("t", "") + v.get("d", "")[:600]) for k in INCHEON)}
            if key not in dec and key not in auto:
                hp = hint_pick({**p, "_t": v.get("t", "")}, hint_rows)
                base = {"status": "ok", "vid": vid, "cid": c.get("id", ""), "t": v.get("t", "")}
                if hp:  # 영상에서 읽은 이름 = 대표님 목록 가게, 주소도 맞음
                    auto[key] = {**base, "place": hp[0], "by": "김부장 확인 (대표님 목록 주소 + 영상 " + ("화면)" if p.get("src") == "video" else "글)")}
                elif auto_ok(p, v):  # 제목에 가게 이름이 그대로 나오는 확실한 것은 바로 맞음
                    auto[key] = {**base, "place": p["cands"][p["best"]], "by": "김부장 자동 확인 (제목에 가게 이름)"}
                elif video_ok(p):  # 영상 간판·자막에서 읽고 카카오도 하나로 맞음
                    auto[key] = {**base, "place": p["cands"][p["best"]], "by": "김부장 자동 확인 (영상 간판·자막)"}
                elif seen_ok(p):  # 글로 찾은 가게를 영상 간판·자막으로도 확인
                    auto[key] = {**base, "place": p["cands"][p["best"]], "by": "김부장 자동 확인 (영상 간판·자막과 같음)"}
            if key in auto:  # 김부장이 대신 정한 것 — 관리자 화면에서 「정한 것」으로 보이게
                a2 = auto[key]
                it["auto"] = {"status": a2.get("status", "ok"), "by": a2.get("by", ""), "why": a2.get("why", ""), "place": a2.get("place")}
            items.append(it)
    # 영상에서 맞는 가게를 찾은 영상은, 아직 안 정한 의심 후보를 빼 둔다 (틀리게 붙은 처음 후보)
    good = {it["vid"] for it in items if (auto.get(it["key"]) or dec.get(it["key"]) or {}).get("status") == "ok"}
    for it in items:
        k = it["key"]
        if it["vid"] in good and k not in dec and k not in auto and it.get("check"):
            auto[k] = {"status": "skip", "vid": it["vid"], "why": "영상에서 확인한 가게로 바꿈", "by": "김부장 자동 확인"}
            it["auto"] = {"status": "skip", "by": "김부장 자동 확인", "why": "영상에서 확인한 가게로 바꿈", "place": None}
    items.sort(key=lambda x: (x["check"], x["inc"], x["date"]), reverse=True)
    save(OUT, {"updated": dt.datetime.now(dt.timezone(dt.timedelta(hours=9))).strftime("%Y-%m-%d %H:%M"),
               "items": items, "nofind": sorted(nofind, key=lambda x: (x["inc"], x["date"]), reverse=True)[:400]})
    print(f"후보 {len(items)}개 (확인 필요 {sum(1 for x in items if x['check'])}) · 못 찾은 영상 {len(nofind)}개")
    dec.update(auto)
    save(CACHE, cache)
    try:
        n = publish(cache, chans, dec)
        if n:
            print(f"맞음으로 고른 집 {n}곳을 따라가기 지도에 붙임")
    except Exception as e:
        print("따라가기에 붙이기 실패:", str(e)[:160])
    save(CH_FILE, chans)


if __name__ == "__main__":
    main()
