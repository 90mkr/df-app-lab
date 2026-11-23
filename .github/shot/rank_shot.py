"""순위 50위 점검: 홈 「순위 전체」(20위까지 + 더 보기) → 펼침 → 지도 연수구(가게가 늘어난 모습) → 지도 「순위」(더 보기) → 순위 밖 방송 집 가게 화면.
사용: rank_shot.py 주소(?demo=1) 저장폴더"""
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
        pg.mouse.click(W / 2, 40)
        time.sleep(1.2)

    def scroll_to(text, x=195, y=600, step=500, tries=12):
        for _ in range(tries):
            if find(text, exact=False):
                return True
            wheel(x, y, step, 0.8)
        return False

    shot("홈")
    # 1) 홈 「순위 전체」: 20위까지 + 「21위부터 더 보기」
    for _ in range(24):
        if find("순위 전체"):
            break
        wheel(195, 600, 500, 0.8)
    if tap("순위 전체", 2.5):
        shot("순위전체_위")
        if scroll_to("21위부터 더 보기"):
            shot("순위전체_더보기단추")
            tap("21위부터 더 보기", 1.5, exact=False)
            shot("순위전체_펼침")
            wheel(195, 600, 2500, 1)
            shot("순위전체_펼침_끝")
        else:
            log.append("더 보기 단추 없음 (순위가 23곳 이하)")
        close_sheet()
    # 2) 지도 → 인천 연수구 (50위 자료)
    if tap("지도", 3):
        shot("지도_처음")
    if tap("지역 검색", 2.5):
        if tap("인천 ", 1.5, exact=False):
            if tap("연수구 ", 6, exact=False):
                shot("지도_연수구")
                wheel(195, 470, -240, 3)
                shot("지도_연수구_확대")
                wheel(195, 470, -240, 3)
                shot("지도_연수구_더확대")
                wheel(195, 470, 480, 3)
                # 3) 지도 「순위」: 20위까지 + 더 보기
                if tap("순위", 2.5):
                    shot("지도순위_위")
                    if scroll_to("21위부터 더 보기", y=620):
                        shot("지도순위_더보기단추")
                        tap("21위부터 더 보기", 1.5, exact=False)
                        wheel(195, 620, 600, 1)
                        shot("지도순위_펼침")
                    close_sheet()
    # 4) 순위 밖 방송 집: 이름으로 찾아 가게 화면
    if tap("가게 이름 검색", 1.5):
        pg.keyboard.type("동남누룽지", delay=60)
        time.sleep(2.5)
        shot("찾기_방송집")
        pg.keyboard.press("Enter")
        time.sleep(3)
        shot("찾기_방송집_지도")
        drag(330, 790, 140, 2.5)   # 아래 가게 칸 안쪽을 잡고 끌어올려 전체로
        shot("방송집_가게")
        drag(330, 760, 260, 2)
        shot("방송집_가게_아래")
        drag(330, 760, 260, 2)
        shot("방송집_가게_더아래")
    # 5) 관리자 「지역 수집」: 구글 조회 + 오늘 블로그 검색
    pg.goto(URL + "&view=progress", wait_until="load", timeout=120000)
    time.sleep(10)
    shot("관리자_지역수집")
    pg.set_viewport_size({"width": 360, "height": 780})
    time.sleep(1.5)
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
