"""유튜버 따라 먹기 줄 점검: 3개 반 보임 · 저절로 한 칸씩 · 쯔양 셋째 칸 · 손으로 넘기면 한 칸에 딱 · 폭 390/412/360.
사용: follow_shot.py 주소(?demo=1) 저장폴더"""
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

    def scroll_find(text, exact=True, step=300, tries=16, x=195, y=520):
        for _ in range(tries):
            b = find(text, exact)
            if b and 60 < b["y"] and b["y"] + b["height"] < H - 100:
                return b
            wheel(x, y, step, 0.7)
        return None

    def hdrag(y, x0, x1, wait=2.0, steps=12):
        pg.mouse.move(x0, y)
        pg.mouse.down()
        for i in range(1, steps + 1):
            pg.mouse.move(x0 + (x1 - x0) * i / steps, y)
            time.sleep(0.02)
        pg.mouse.up()
        time.sleep(wait)

    def to_follow(top=110):
        b = scroll_find("따라 먹기", exact=False)
        log.append(f"따라 먹기 칸 {b}")
        if b:
            wheel(195, 500, b["y"] - top, 1.2)
        return find("따라 먹기", exact=False)

    b = to_follow()
    shot("따라_390_처음")
    time.sleep(3.6)
    shot("따라_390_한칸뒤")
    time.sleep(3.4)
    shot("따라_390_두칸뒤")
    if b:
        y = b["y"] + 110
        hdrag(y, 330, 120, 1.6)
        shot("따라_손으로_넘김")
    pg.set_viewport_size({"width": 412, "height": 915})
    time.sleep(1.5)
    to_follow()
    shot("따라_412")
    pg.set_viewport_size({"width": 360, "height": 780})
    time.sleep(1.5)
    to_follow()
    shot("따라_360")


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
