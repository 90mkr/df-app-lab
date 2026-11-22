"""앱 화면 점검: 지역 검색(전부 열림) → 유튜버 집 가게 화면 → 길안내 고르기 → 자세한 동네 가게 → 내 주변 → 룰렛 → 내 콕 → 설정 → 관리자 지역 수집.
사용: app_shot.py 주소(?demo=1) 저장폴더"""
import os
import re
import sys
import time

from playwright.sync_api import sync_playwright

URL, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
W, H = 390, 844
log = []
n = [0]


def run(pg):
    def shot(name):
        n[0] += 1
        pg.screenshot(path=f"{OUT}/{n[0]:02d}_{name}.png")
        log.append(f"사진 {n[0]:02d}_{name}")

    def find(text, exact=True):
        for t in (lambda: pg.get_by_role("button", name=text, exact=exact), lambda: pg.get_by_label(text, exact=exact), lambda: pg.get_by_text(text, exact=exact)):
            try:
                loc = t()
                for i in range(loc.count()):
                    b = loc.nth(i).bounding_box()
                    if b and b["width"] > 0 and 0 <= b["y"] < H:
                        return b
            except Exception as e:
                log.append(f"찾기 오류 {text}: {e}")
        return None

    def tap(text, wait=2.0, exact=True):
        b = find(text, exact)
        if not b:
            log.append(f"못 찾음: {text}")
            return None
        pg.mouse.click(b["x"] + b["width"] / 2, b["y"] + b["height"] / 2)
        time.sleep(wait)
        return b

    def wheel(x, y, dy, wait=1.2):
        pg.mouse.move(x, y)
        pg.mouse.wheel(0, dy)
        time.sleep(wait)

    def drag(x, y0, y1, wait=2.0, steps=14):
        pg.mouse.move(x, y0)
        pg.mouse.down()
        for i in range(1, steps + 1):
            pg.mouse.move(x, y0 + (y1 - y0) * i / steps)
            time.sleep(0.02)
        pg.mouse.up()
        time.sleep(wait)

    def close_sheet():
        pg.mouse.click(W / 2, 40)  # 창 바깥 (위쪽)
        time.sleep(1.2)

    shot("홈")
    # 1) 홈 지역 단추 → 전국 지역 검색 (준비 중 표시 없이)
    if tap("지역 ", 2.5, exact=False):
        shot("홈_지역검색")
        if tap("서울 ", 1.5, exact=False):
            shot("지역검색_서울")
            if tap("강남구 ", 5, exact=False):
                shot("지도_강남구_유튜버집")
                # 2) 순위 → 1위 (별점 없는 유튜버 집)
                if tap("순위", 2.5):
                    shot("순위_강남구")
                    r = pg.get_by_role("button", name=re.compile(r"^1위 "))
                    if r.count():
                        b = r.first.bounding_box()
                        pg.mouse.click(b["x"] + b["width"] / 2, b["y"] + b["height"] / 2)
                        time.sleep(4)
                        shot("가게_유튜버집")
                        drag(120, 520, 220, 2)
                        shot("가게_유튜버집_아래")
                        drag(120, 260, 640, 1.5)
                        # 3) 길안내 → 고르는 창
                        if tap("길안내", 2):
                            shot("길안내_고르기")
                            tap("다음부터 이 앱으로 바로 열기", 0.8)
                            shot("길안내_바로열기_체크")
                            close_sheet()
                        close_sheet()
    # 4) 지도에서 지역 검색 → 인천 연수구 (자세히)
    if tap("지역 검색", 2.5):
        shot("지도_지역검색")
        if tap("인천 ", 1.5, exact=False):
            shot("지역검색_인천")
            if tap("연수구 ", 5, exact=False):
                shot("지도_연수구")
                if tap("순위", 2.5):
                    shot("순위_연수구")
                    r = pg.get_by_role("button", name=re.compile(r"^1위 "))
                    if r.count():
                        b = r.first.bounding_box()
                        pg.mouse.click(b["x"] + b["width"] / 2, b["y"] + b["height"] / 2)
                        time.sleep(4)
                        shot("가게_자세한집")
                        close_sheet()
    # 5) 가운데 「내 주변」
    if tap("내 주변", 6):
        shot("내주변")
        drag(195, 470, 120, 2)
        shot("내주변_끌어올림")
        drag(195, 140, 520, 2)
        if tap("고민되면 룰렛", 3):
            shot("내주변_룰렛")
            close_sheet()
        tap("뒤로", 2)
    # 6) 내 콕
    if tap("내 콕", 2.5):
        shot("내콕")
        wheel(195, 600, 600, 1.2)
        shot("내콕_메뉴")
        wheel(195, 600, 900, 1.2)
        shot("내콕_메뉴_아래")
        wheel(195, 400, -3000, 1)
        # 7) 설정 → 길안내 앱
        if tap("설정", 2.5):
            shot("설정")
            if tap("길안내 앱", 2, exact=False):
                shot("설정_길안내앱")
                close_sheet()
    # 8) 관리자 「지역 수집」 (예시 모드 전용 화면)
    pg.goto(URL + "&view=progress", wait_until="load", timeout=120000)
    time.sleep(10)
    shot("관리자_지역수집")
    wheel(195, 600, 700, 1.2)
    shot("관리자_지역수집_아래")
    pg.set_viewport_size({"width": 360, "height": 780})
    time.sleep(1.5)
    wheel(195, 400, -3000, 1)
    shot("관리자_지역수집_360")


with sync_playwright() as p:
    br = p.chromium.launch(args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
    ctx = br.new_context(viewport={"width": W, "height": H}, device_scale_factor=2, locale="ko-KR", timezone_id="Asia/Seoul",
                         geolocation={"latitude": 37.3925, "longitude": 126.6390}, permissions=["geolocation"])
    pg = ctx.new_page()
    pg.on("console", lambda m: log.append(f"[콘솔 {m.type}] {m.text[:300]}"))
    pg.on("pageerror", lambda e: log.append(f"[페이지 오류] {str(e)[:300]}"))
    try:
        pg.goto(URL, wait_until="load", timeout=120000)
        time.sleep(13)
        pg.evaluate("() => { const e = document.querySelector('flt-semantics-placeholder'); if (e) e.click(); }")
        time.sleep(2)
        run(pg)
    except Exception as e:
        log.append(f"[중단] {e}")
        try:
            pg.screenshot(path=f"{OUT}/99_중단.png")
        except Exception:
            pass
    br.close()

with open(f"{OUT}/log.txt", "w", encoding="utf-8") as f:
    f.write("\n".join(log))
print("\n".join(log[-60:]))
