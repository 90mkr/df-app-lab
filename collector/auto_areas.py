"""지역 넓혀 가기: 블로그·별점·영업시간까지 모을 동네를 정해진 순서대로 한 곳씩 더하고,
지역마다 수집 진행 상황을 web/data/progress.json에 적는다 (관리자 화면 「지역 수집」에서 봄).

순서: 인천 → 서울 → 경기 (수도권 먼저) → 광역시 (부산·대구·대전·광주·울산·세종, 큰 도시부터) → 그 밖의 시·군
같은 시·도 안에서는 앱에서 많이 고르거나 오래 본 곳(regionViews) → 유튜버가 많이 다녀간 곳 순.

실제 수집은 collect.py가 한다. 구글 조회 안전 상한(GOOGLE_MONTH)은 그대로 지킨다:
이번 달 무료량이 새 동네를 시작할 만큼 남았을 때만 다음 동네를 더하고, 모자라면 다음 달 1일에 이어 간다.

  python3 collector/auto_areas.py           수집 전 — 다음 동네 더하기 + 진행 상황 적기
  python3 collector/auto_areas.py --report  수집 뒤 — 진행 상황만 다시 적기
"""
import datetime as dt
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from collect import (fs_docs, load_json, save_json, REGIONS, DATA_DIR, USAGE, GOOGLE_MONTH, GOOGLE_MONTH_B, GOOGLE_PAID,  # noqa: E402
                     GOOGLE_NEW_MAX, GOOGLE_NEW_CAP, GOOGLE_YT_REST, google_left)

NEW_MIN = 120  # collect.py가 새 동네를 시작하는 최소 남은 구글 조회 수 (같은 값)
MAX_ADD = int(os.environ.get("AUTO_MAX_ADD", "6"))  # 한 번 수집에 새로 더하는 동네 수 (수집 시간 안에 끝나게)
PROGRESS = os.path.join(DATA_DIR, "progress.json")
GROUP = {"서울": "서울", "부산": "부산", "제주": "제주", "경기": "경기", "인천": "인천", "강원": "강원",
         "경북": "경상", "경남": "경상", "대구": "경상", "울산": "경상",
         "전북": "전라", "광주·전남": "전라", "충북": "충청", "충남": "충청", "대전": "충청", "세종": "충청"}
SHORT = {"제주특별자치도": "제주", "강원특별자치도": "강원", "전북특별자치도": "전북", "전남광주통합특별시": "광주·전남",
         "세종특별자치시": "세종", "서울특별시": "서울", "인천광역시": "인천", "경기도": "경기", "부산광역시": "부산",
         "대구광역시": "대구", "대전광역시": "대전", "울산광역시": "울산", "광주광역시": "광주·전남"}
METRO = ["부산", "대구", "대전", "광주·전남", "울산", "세종"]  # 큰 도시부터 (광주는 「구」만)
PHASES = ["인천", "서울", "경기", "광역시", "그 밖의 시·군"]
# 인천 동네 ↔ 시·군·구 (2026년 개편 이름 포함) — 정해 둔 동네가 없으면 시·군·구 이름으로 센다
INCHEON_GU = {"bupyeong": ["부평구"], "namdong": ["남동구"], "michuhol": ["미추홀구"], "seogu": ["서해구", "검단구", "서구"],
              "gyeyang": ["계양구"], "ganghwa": ["강화군", "옹진군"], "donggu": ["동구"]}


def short(s):
    return SHORT.get(s or "", s or "")


def city_of(gu):
    w = [x for x in (gu or "").split(" ") if x]
    return w[0] if w else ""


def phase_of(sido, city):
    if sido in ("인천", "서울", "경기"):
        return PHASES.index(sido)
    if sido in METRO and (sido != "광주·전남" or city.endswith("구")):
        return 3
    return 4


def box_of(pts, center=None):
    """가게가 모인 범위(가운데 90%) + 여유. 가게가 적으면 가운데에서 3~4km."""
    if len(pts) >= 5:
        la = sorted(x[0] for x in pts)
        ln = sorted(x[1] for x in pts)
        i0, i1 = int(len(pts) * 0.05), max(0, int(len(pts) * 0.95) - 1)
        s_, n_, w_, e_ = la[i0], la[i1], ln[i0], ln[i1]
        if center:
            s_, n_ = min(s_, center[0] - 0.012), max(n_, center[0] + 0.012)
            w_, e_ = min(w_, center[1] - 0.015), max(e_, center[1] + 0.015)
        dla, dln = max(0.012, (n_ - s_) * 0.12), max(0.015, (e_ - w_) * 0.12)
        return [round(w_ - dln, 4), round(s_ - dla, 4), round(e_ + dln, 4), round(n_ + dla, 4)]
    if center:
        return [round(center[1] - 0.04, 4), round(center[0] - 0.03, 4), round(center[1] + 0.04, 4), round(center[0] + 0.03, 4)]
    return None


def inside(b, lat, lng):
    return b and b[0] <= lng <= b[2] and b[1] <= lat <= b[3]


def area_stats(a):
    """모은 동네 자료에서: 별점 있는 집, 영업시간 있는 집, 블로그 글이 있는 집 수"""
    js = load_json(os.path.join(DATA_DIR, f"{a['id']}.json"), {})
    pl = js.get("places", [])
    return {
        "all": len(pl),
        "rated": sum(1 for p in pl if (p.get("greviews") or 0) > 0),
        "hours": sum(1 for p in pl if p.get("hours") or p.get("week")),
        "blog": sum(1 for p in pl if (p.get("posts") or p.get("blog") or 0)),
        "vid": sum(1 for p in pl if p.get("vids")),
    }


def build(regions, follow, views):
    """순서 매긴 목록: 인천은 정해 둔 동네, 나머지는 시·군·구 하나가 한 동네"""
    places = [(short(p.get("s")), city_of(p.get("gu")), p["lat"], p["lng"]) for p in follow.get("places", []) if p.get("lat")]
    areas = [a for s in regions.get("sido", []) for a in s.get("areas", [])]
    rows = []
    # 인천: regions.json의 동네
    for a in next((s["areas"] for s in regions.get("sido", []) if s.get("name") == "인천"), []):
        gus = INCHEON_GU.get(a["id"], [a.get("gu", "")])
        mine = [(la, ln) for s, c, la, ln in places if s == "인천" and c in gus]
        b = a.get("bbox") or box_of(mine, (a["lat"], a["lng"]))
        # 손으로 정해 둔 범위(신포 등) 안에 가운데가 들어가는 동네는 따로 모으지 않음 (모으는 중이거나 다 모은 동네는 제외)
        covered = "" if (a.get("collect") or a.get("ready")) else next(
            (o["name"] for o in areas if o is not a and o.get("bbox") and not o.get("bbox_auto") and o.get("collect")
             and inside(o["bbox"], a["lat"], a["lng"])), "")
        yt = len(mine) if mine else (sum(1 for s, c, la, ln in places if inside(b, la, ln)) if b else 0)
        rows.append({"sido": "인천", "city": a.get("gu", ""), "name": a["name"], "id": a["id"], "area": a, "bbox": b,
                     "yt": yt, "views": sum(int(v.get("n", 0)) for k, v in views.items() if k.startswith("인천_") and k.split("_", 1)[1] in gus),
                     "phase": 0, "covered": covered})
    # 그 밖: 시·군·구마다
    by = {}
    for s, c, la, ln in places:
        if s and c and s != "인천":
            by.setdefault((s, c), []).append((la, ln))
    auto = {a.get("auto_key"): a for a in areas if a.get("auto_key")}
    for (s, c), pts in by.items():
        if len(pts) < 3:
            continue
        key = f"{s} {c}"
        a = auto.get(key)
        rows.append({"sido": s, "city": c, "name": c, "id": a["id"] if a else "r" + hashlib.md5(key.encode("utf-8")).hexdigest()[:8],
                     "area": a, "bbox": (a or {}).get("bbox") or box_of(pts), "pts": pts, "yt": len(pts),
                     "views": int((views.get(f"{s}_{c}") or {}).get("n", 0)), "phase": phase_of(s, c), "covered": ""})

    rank = {"done": 0, "run": 1, "queue": 2, "covered": 3}

    def order(r):
        metro = METRO.index(r["sido"]) if r["phase"] == 3 and r["sido"] in METRO else 0
        return (r["phase"], metro, rank[state_of(r)], -r["views"], -r["yt"], r["name"])

    rows.sort(key=order)
    return rows


def state_of(r):
    a = r.get("area")
    if r.get("covered"):
        return "covered"
    if a and a.get("ready"):
        return "done"
    if a and a.get("collect"):
        return "run"
    return "queue"


def plan(r):
    """새 동네 하나에 드는 구글 조회 수 (collect.py와 같은 셈): 유튜버 집 전부 + 블로그 인기 집"""
    if r["phase"] == 0:
        return GOOGLE_NEW_MAX
    return min(GOOGLE_NEW_CAP, max(GOOGLE_NEW_MAX, r["yt"] + GOOGLE_YT_REST))


def has_data(r):
    a = r.get("area") or {}
    return os.path.exists(os.path.join(DATA_DIR, f"{a.get('id', r['id'])}.json"))


def add_one(regions, r):
    if r["area"] is not None:  # 인천처럼 이미 적어 둔 동네: 수집만 켠다
        r["area"]["collect"] = True
        if not r["area"].get("bbox"):
            r["area"]["bbox"] = r["bbox"]
            r["area"]["bbox_auto"] = True
        r["area"].setdefault("q", f"인천 {r['area'].get('gu', '')}".strip())
        return
    group = GROUP.get(r["sido"], r["sido"])
    sido = next((s for s in regions["sido"] if s["name"] == group), None)
    if sido is None:
        sido = {"name": group, "areas": []}
        regions["sido"].append(sido)
    la = sorted(x[0] for x in r["pts"])
    ln = sorted(x[1] for x in r["pts"])
    a = {"id": r["id"], "name": r["city"], "gu": r["city"],
         "lat": round(la[len(la) // 2], 5), "lng": round(ln[len(ln) // 2], 5), "zoom": 13,
         "ready": False, "collect": True, "auto": True, "auto_key": f"{r['sido']} {r['city']}",
         "bbox": r["bbox"], "q": f"{r['sido'].split('·')[0]} {r['city']}"}
    sido["areas"].append(a)
    r["area"] = a


def add_next(regions, rows, left):
    """이번 달 남은 구글 조회 안에서 순서대로 여러 동네를 더한다 (아직 안 모은 동네 몫은 먼저 뺀다)"""
    pending = [r for r in rows if state_of(r) == "run" and not has_data(r)]
    room = left - sum(plan(r) for r in pending)
    added = []
    for r in rows:
        if len(added) >= MAX_ADD:
            break
        if state_of(r) != "queue" or not r.get("bbox"):
            continue
        need = plan(r)
        if room < max(NEW_MIN, need):
            break
        add_one(regions, r)
        room -= need
        added.append(r)
    if added:
        save_json(REGIONS, regions)
        print("이번에 새로 모을 동네:", ", ".join(f"{r['sido']} {r['name']}(약 {plan(r)}번)" for r in added))
    else:
        print(f"새로 더할 동네 없음 (남은 구글 조회 {left}번, 모으는 중인 동네 몫 {left - room}번)")
    return added


def write_progress(rows, usage):
    today = dt.date.today()
    nxt = (today.replace(day=1) + dt.timedelta(days=32)).replace(day=1)
    out = []
    k = 0
    for r in rows:
        st = state_of(r)
        row = {"s": r["sido"], "n": r["name"], "id": r["id"], "st": st, "yt": r["yt"], "v": r["views"], "p": r["phase"]}
        if st == "queue":
            k += 1
            row["o"] = k  # 기다리는 순서
        if r.get("covered"):
            row["in"] = r["covered"]
        a = r.get("area")
        if a and (a.get("ready") or a.get("collect")):
            row.update(area_stats(a))
            row["up"] = a.get("updated", "")
        out.append(row)
    m = today.strftime("%Y-%m")
    left = google_left(usage, m)
    paid = GOOGLE_PAID.get(m, 0)
    used = usage.get(m, 0) + usage.get(m + ":B", 0)
    data = {
        "updated": dt.datetime.now(dt.timezone(dt.timedelta(hours=9))).strftime("%Y-%m-%d %H:%M"),
        "google": {"month": m, "used": used, "limit": GOOGLE_MONTH + GOOGLE_MONTH_B + paid, "free": GOOGLE_MONTH + GOOGLE_MONTH_B,
                   "paid": paid, "left": left, "new_min": NEW_MIN, "per_area": GOOGLE_NEW_MAX, "refill": nxt.isoformat()},
        "wait": left < NEW_MIN,
        "phases": PHASES,
        "rows": out,
    }
    save_json(PROGRESS, data)
    done = sum(1 for r in out if r["st"] == "done")
    print(f"진행 상황 저장: 완료 {done}곳 · 모으는 중 {sum(1 for r in out if r['st'] == 'run')}곳 · 대기 {sum(1 for r in out if r['st'] == 'queue')}곳")


def main():
    report = "--report" in sys.argv
    regions = load_json(REGIONS, {})
    follow = load_json(os.path.join(DATA_DIR, "follow.json"), {})
    try:
        views = fs_docs("regionViews")
    except Exception as e:  # 규칙이 아직 없으면 읽지 못함 → 유튜버 많은 순으로만
        print("자주 찾는 지역 기록을 받지 못했습니다:", str(e)[:100])
        views = {}
    usage = load_json(USAGE, {})
    rows = build(regions, follow, views)
    if not report:
        add_next(regions, rows, google_left(usage))
    write_progress(rows, usage)


if __name__ == "__main__":
    main()
