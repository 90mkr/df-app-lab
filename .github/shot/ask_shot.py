"""콕플 문의함 점검: 글쓰기(제휴·광고) → 보내기 → 접수 화면, 내 문의 목록(답변 펼침), 관리자 문의함(펼쳐서 답변 칸).
사용: ask_shot.py 주소(?demo=1) 저장폴더"""
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

    def open_view(v, wait=9):
        pg.goto(URL + "&view=" + v, wait_until="load", timeout=120000)
        time.sleep(wait)
        pg.evaluate("() => { const e = document.querySelector('flt-semantics-placeholder'); if (e) e.click(); }")
        time.sleep(1.5)

    def type_in(label, text):
        b = find(label, exact=False)
        if not b:
            log.append(f"입력 칸 못 찾음: {label}")
            return
        pg.mouse.click(b["x"] + b["width"] / 2, b["y"] + b["height"] / 2)
        time.sleep(0.6)
        pg.keyboard.type(text, delay=20)
        time.sleep(0.6)

    # 1) 글쓰기 (제휴·광고)
    shot("문의_글쓰기_처음")
    type_in("예) ○○식당 광고 문의", "송도 브런치 카페 광고 문의")
    type_in("회사·가게 이름과 제안 내용", "송도에서 브런치 카페를 하고 있어요. 광고 방법과 비용이 궁금합니다.")
    type_in("010-0000-0000", "010-1234-5678")
    pg.mouse.click(W / 2, 120)
    time.sleep(0.8)
    shot("문의_글쓰기_채움")
    if tap("보내기", 2.5):
        shot("문의_접수됨")
    # 2) 종류 바꾸기 (개선 제안)
    open_view("ask")
    tap("개선 제안", 1.2)
    shot("문의_종류_개선제안")
    # 3) 내 문의
    open_view("myask")
    shot("내문의_목록")
    tap("지도에서 가게 이름이 겹쳐 보여요", 1.2, exact=False)
    shot("내문의_답변펼침")
    # 4) 관리자 문의함
    open_view("asks")
    shot("관리자_문의함")
    tap("군봉묵은지김치찜 정보 수정", 1.2, exact=False)
    shot("관리자_문의함_펼침")
    tap("전체", 1.0, exact=False)
    shot("관리자_문의함_전체")
    # 5) 내 콕 아래 메뉴 (메일 대신 글쓰기 · 내 문의 줄)
    pg.goto(URL, wait_until="load", timeout=120000)
    time.sleep(12)
    pg.evaluate("() => { const e = document.querySelector('flt-semantics-placeholder'); if (e) e.click(); }")
    time.sleep(1.5)
    tap("내 콕", 2.5)
    b = scroll_find("콕플 안내", exact=False)
    if b:
        wheel(195, 500, b["y"] - 90, 1.5)
    shot("내콕_콕플안내")


with sync_playwright() as p:
    br = p.chromium.launch(args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
    ctx = br.new_context(viewport={"width": W, "height": H}, device_scale_factor=2, locale="ko-KR", timezone_id="Asia/Seoul",
                         geolocation={"latitude": 37.3925, "longitude": 126.6390}, permissions=["geolocation"])
    pg = ctx.new_page()
    pg.on("console", lambda m: log.append(f"[콘솔 {m.type}] {m.text[:300]}"))
    pg.on("pageerror", lambda e: log.append(f"[페이지 오류] {str(e)[:300]}"))
    try:
        pg.goto(URL + "&view=ask", wait_until="load", timeout=120000)
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
