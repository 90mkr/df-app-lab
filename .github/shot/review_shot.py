"""후기 화면 점검: 예시 후기(?demo=1)로 메인 카드 · 가게 화면 · 후기 쓰기 · 축하 · 내가 쓴 후기 · 영상 맨 위를 찍는다. 사용: review_shot.py 주소 저장폴더"""
import os
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
        for t in (lambda: pg.get_by_role("button", name=text, exact=exact), lambda: pg.get_by_text(text, exact=exact), lambda: pg.get_by_label(text, exact=exact)):
            try:
                loc = t()
                for i in range(loc.count()):
                    b = loc.nth(i).bounding_box()
                    if b and b["width"] > 0 and 0 <= b["y"] < H:
                        return b
            except Exception as e:
                log.append(f"찾기 오류 {text}: {e}")
        return None

    def tap_text(text, wait=2.0, exact=True):
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

    def scroll_find(text, exact=True, step=300, tries=14, x=195, y=520):
        for _ in range(tries):
            b = find(text, exact)
            if b and 60 < b["y"] and b["y"] + b["height"] < H - 100:
                return b
            wheel(x, y, step, 0.7)
        return None

    # 1) 메인: 방금 올라온 후기
    b = scroll_find("올라온 후기", exact=False)
    log.append(f"후기 칸 위치 {b}")
    if b:
        wheel(195, 500, b["y"] - 150, 1.5)
    shot("메인_후기칸")
    wheel(195, 500, 120, 1)
    shot("메인_후기칸_아래")
    # 카드 옆으로 넘기기
    b = find("올라온 후기", exact=False)
    if b:
        drag_y = b["y"] + 150
        pg.mouse.move(330, drag_y)
        pg.mouse.wheel(500, 0)
        time.sleep(1.2)
        shot("메인_후기칸_옆으로")
        pg.mouse.wheel(-1500, 0)
        time.sleep(1)
    # 2) 카드 누르기 → 그 집 가게 화면
    b = find("후기:", exact=False)
    log.append(f"후기 카드 {b}")
    if b:
        pg.mouse.click(b["x"] + b["width"] / 2, b["y"] + b["height"] / 2)
        time.sleep(4)
        shot("카드_가게")
        c = find("길찾기")
        top = (c["y"] - 20) if c else 600
        drag(120, top, 90, 2.5)
        shot("가게_위_순위")
        for i in range(8):
            if find("후기 남기기") and find("후기 남기기")["y"] < H - 200:
                break
            drag(120, 650, 350, 1.2)
        shot("가게_후기남기기")
        drag(120, 650, 330, 1.5)
        shot("가게_후기목록")
        drag(120, 650, 330, 1.5)
        shot("가게_후기목록_2")
        drag(120, 300, 650, 1.0)
        # 3) 후기 쓰기 창
        if tap_text("후기 남기기", 2.5):
            shot("쓰기_처음")
            for t in ["또 올 집", "가성비 굿", "웨이팅할 만함"]:
                tap_text(t, 0.25)
            time.sleep(0.2)
            shot("쓰기_스티커_튀는중")
            time.sleep(1.0)
            shot("쓰기_스티커3")
            m = find("꼭 시키세요", exact=False)
            log.append(f"메뉴 스티커 {m}")
            if not m or m["y"] > H - 260:
                wheel(195, 500, 260, 1)
                m = find("꼭 시키세요", exact=False)
            if m:
                pg.mouse.click(m["x"] + m["width"] + 90, m["y"] + m["height"] / 2)
                time.sleep(0.8)
                pg.keyboard.type("묵은지 김치찜", delay=60)
                time.sleep(1.2)
                shot("쓰기_메뉴")
            tap_text("인생 맛집", 0.3)
            tap_text("혼밥 OK", 0.3)
            time.sleep(1.2)
            shot("쓰기_다섯개_넘침")
            wheel(195, 500, 600, 1.2)
            shot("쓰기_아래")
            st = find("별 4개")
            if st:
                pg.mouse.click(st["x"] + st["width"] / 2, st["y"] + st["height"] / 2)
                time.sleep(0.5)
            shot("쓰기_별점")
            if tap_text("후기 올리기", 0.35):
                shot("축하_처음")
                time.sleep(0.5)
                shot("축하_가운데")
                time.sleep(2.4)
                shot("축하_뒤_가게")
        pg.keyboard.press("Escape")
        time.sleep(1.5)
    # 4) 메인으로: 내 후기가 맨 앞
    tap_text("홈", 2)
    wheel(195, 400, -9000, 1)
    b = scroll_find("올라온 후기", exact=False)
    if b:
        wheel(195, 500, b["y"] - 150, 1.5)
    shot("메인_내후기_맨앞")
    # 5) 내 콕 → 내가 쓴 후기
    if tap_text("내 콕", 2):
        if tap_text("내가 쓴 후기", 2):
            shot("내콕_내가쓴후기")
            wheel(195, 600, 500, 1)
            shot("내콕_내가쓴후기_아래")
        pg.set_viewport_size({"width": 360, "height": 780})
        time.sleep(1.5)
        shot("내콕_360")
        pg.set_viewport_size({"width": W, "height": H})
        time.sleep(1.5)
    # 6) 영상 맨 위
    if tap_text("영상", 2.5):
        shot("영상_맨위")
        b = find("전체 영상", exact=False)
        log.append(f"유튜버 줄 {b}")
        if b:
            pg.mouse.click(b["x"] + b["width"] + 40, b["y"] + b["height"] / 2)
            time.sleep(2)
            shot("영상_유튜버고름")
    # 7) 작은 휴대폰에서 메인 후기 칸
    tap_text("홈", 2)
    pg.set_viewport_size({"width": 360, "height": 780})
    time.sleep(1.5)
    b = scroll_find("올라온 후기", exact=False)
    if b:
        wheel(195, 500, b["y"] - 140, 1.5)
    shot("메인_후기칸_360")
    pg.set_viewport_size({"width": W, "height": H})


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
