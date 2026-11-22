"""후기 모음: 가게마다 「지금도 맛있어요 / 예전만 못해요」 표 수와 「○○ 꼭 시키세요」 메뉴별 수를 web/data/rstats.json에 적는다.
지도 핀의 「지금도 ○%」와 가게 화면의 「콕플러 추천 메뉴」가 이 값을 쓴다 (가게 화면을 열면 앱이 후기를 직접 받아 새로 셈)."""
import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from collect import fs_docs, save_json, DATA_DIR  # noqa: E402


def main():
    try:
        docs = fs_docs("reviews")
    except Exception as e:
        print("후기를 받지 못했습니다:", str(e)[:120])
        return
    votes, menus = {}, {}
    for r in docs.values():
        if r.get("hidden") or not r.get("pid"):
            continue
        pid = str(r["pid"])
        st = r.get("st") or []
        if "still" in st or "worse" in st:
            v = votes.setdefault(pid, [0, 0])
            v[0 if "still" in st else 1] += 1
        m = (r.get("menu") or "").strip()
        if "menu" in st and m:
            mm = menus.setdefault(pid, {})
            mm[m] = mm.get(m, 0) + 1
    out = {"updated": dt.datetime.now(dt.timezone(dt.timedelta(hours=9))).strftime("%Y-%m-%d %H:%M"), "v": votes,
           "m": {k: dict(sorted(v.items(), key=lambda x: -x[1])[:5]) for k, v in menus.items()}}
    save_json(os.path.join(DATA_DIR, "rstats.json"), out)
    print(f"후기 모음: 후기 {len(docs)}개 · 투표 있는 가게 {len(votes)}곳 · 메뉴 스티커 있는 가게 {len(menus)}곳")


if __name__ == "__main__":
    main()
