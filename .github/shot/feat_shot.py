"""추가 기능 1단계 점검: 핀 크기·숫자·지금도 ○%, 2명 이상, 방영 후, 콕플러 추천 메뉴, 후기 「방영 후 지금은?」, 룰렛 카톡으로 보내기.
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

    def tap_rank1():
        shot("순위_열림")
        r = pg.get_by_role("button", name=re.compile(r"^1위 "))
        if r.count() == 0:
            r = pg.get_by_label(re.compile(r"^1위 "))
        if r.count():
            b = r.first.bounding_box()
            pg.mouse.click(b["x"] + b["width"] / 2, b["y"] + b["height"] / 2)
        else:
            log.append("못 찾음: 1위 → 첫 줄 자리를 누름")
            pg.mouse.click(195, 392)
        time.sleep(4)
        return True

    # 6) 홈 룰렛 → 결과 → 카톡으로 보내기
    tap("홈", 2.5)
    for i in range(10):
        b = find("오늘 뭐 먹지?")
        if b and 80 < b["y"] < H - 140:
            break
        wheel(195, 500, 260, 0.8)
    if tap("오늘 뭐 먹지?", 3):
        shot("룰렛_처음")
        b = find("가운데를 눌러 돌려 보세요", exact=False)
        log.append(f"룰렛 안내 {b}")
        cy = (b["y"] - 215) if b else 545
        pg.mouse.click(W / 2, cy)
        time.sleep(5.5)
        shot("룰렛_결과_카톡")
        if tap("카톡으로 보내기", 1.5):
            shot("룰렛_카톡_누름")
        pg.mouse.click(W / 2, 40)
        time.sleep(1.2)

    # 1) 지도 → 서울 강남구: 핀 크기 3단계·숫자·지금도 ○% · 카드 사진 위 방영 후
    tap("지도", 3)
    if tap("지역 검색", 2.5):
        tap("서울 ", 1.5, exact=False)
        tap("강남구 ", 5, exact=False)
    shot("지도_강남구_핀")
    pg.mouse.move(195, 430)
    pg.mouse.wheel(0, -300)
    time.sleep(2.5)
    shot("지도_강남구_가까이")
    # 2) 유튜버 2명 이상만
    if tap("유튜버 2명 이상 다녀간 집만", 3):
        shot("지도_2명이상")
        tap("유튜버 2명 이상 다녀간 집만", 2)
    # 3) 가게 화면: 방영 후 · 지금도 맛있다 · 콕플러 추천 메뉴
    if tap("순위", 2.5) and tap_rank1():
        shot("가게_방영후_투표")
        drag(120, 560, 260, 2)
        shot("가게_추천메뉴")
        drag(120, 260, 640, 1.5)
        # 4) 후기 쓰기: 방영 후 지금은?
        for i in range(8):
            b = find("후기 남기기")
            if b and b["y"] < H - 200:
                break
            drag(120, 650, 350, 1.2)
        if tap("후기 남기기", 2.5):
            shot("후기쓰기_처음")
            wheel(195, 500, 260, 1)
            shot("후기쓰기_방영후")
            tap("지금도 맛있어요", 0.8, exact=False)
            shot("후기쓰기_지금도_고름")
            pg.keyboard.press("Escape")
            time.sleep(1.5)
        pg.mouse.click(W / 2, 40)
        time.sleep(1.2)
    # 5) 인천 연수구 (별점 있는 집)
    if tap("지역 검색", 2.5):
        tap("인천 ", 1.5, exact=False)
        tap("연수구 ", 5, exact=False)
        shot("지도_연수구_핀")
        if tap("순위", 2.5) and tap_rank1():
            shot("가게_자세한집_방영후")
            pg.mouse.click(W / 2, 40)
            time.sleep(1.2)


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
