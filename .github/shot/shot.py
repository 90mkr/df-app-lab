"""올라간 앱을 휴대폰 크기(390×844)로 열어 화면마다 사진을 찍는다. 사용: shot.py 주소 저장폴더"""
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
        tries = [
            lambda: pg.get_by_role("button", name=text, exact=exact),
            lambda: pg.get_by_text(text, exact=exact),
            lambda: pg.get_by_label(text, exact=exact),
        ]
        for t in tries:
            try:
                loc = t()
                for i in range(loc.count()):
                    el = loc.nth(i)
                    b = el.bounding_box()
                    if b and b["width"] > 0 and 0 <= b["y"] < H:
                        return b
            except Exception as e:
                log.append(f"찾기 오류 {text}: {e}")
        return None

    def tap_text(text, wait=2.5, exact=True):
        b = find(text, exact)
        if not b:
            log.append(f"못 찾음: {text}")
            return False
        pg.mouse.click(b["x"] + b["width"] / 2, b["y"] + b["height"] / 2)
        time.sleep(wait)
        return True

    def tap(x, y, wait=2.5):
        pg.mouse.click(x, y)
        time.sleep(wait)

    def wheel(x, y, dy, wait=2.5):
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

    # 아래로 내려 가며 찾기 (아래 탭에 가리지 않는 자리까지)
    def scroll_find(text, exact=True, step=350, tries=16):
        for _ in range(tries):
            b = find(text, exact)
            if b and b["y"] + b["height"] < H - 90:
                return b
            wheel(195, 500, step, 0.8)
        return None

    def tap_scroll(text, wait=2.5, exact=True):
        b = scroll_find(text, exact)
        if not b:
            log.append(f"못 찾음: {text}")
            return False
        pg.mouse.click(b["x"] + b["width"] / 2, b["y"] + b["height"] / 2)
        time.sleep(wait)
        return True

    def labels():
        try:
            return pg.evaluate("""() => Array.from(document.querySelectorAll('flt-semantics, [role]'))
                .map(e => (e.getAttribute('aria-label') || e.textContent || '').trim()).filter(s => s).slice(0, 120)""")
        except Exception as e:
            return [f"오류 {e}"]

    shot("홈")
    log.append("홈 글자: " + " / ".join(labels()[:80]))
    # 위쪽 사람 단추 → 로그인 창
    if tap_text("로그인", 2):
        shot("로그인창")
        pg.keyboard.press("Escape")
        time.sleep(1.2)
    # 작은 휴대폰(360) 머리줄
    pg.set_viewport_size({"width": 360, "height": 780})
    time.sleep(2)
    shot("홈_360")
    pg.set_viewport_size({"width": W, "height": H})
    time.sleep(2)
    # 아래로 당겨 새로 고침
    drag(195, 240, 600, wait=0.35, steps=12)
    shot("새로고침")
    time.sleep(2.5)
    shot("새로고침_끝")
    for i in range(1, 7):
        wheel(195, 560, 600, 1.6)
        shot(f"홈_{i}")
    wheel(195, 400, -9000, 1)
    # 오늘 뭐 먹지 룰렛
    if tap_text("오늘 뭐 먹지?", 2):
        shot("룰렛")
        if tap_text("룰렛 돌리기", 5.5):
            shot("룰렛_결과")
            if tap_text("뽑은 집 어디야", 4):
                shot("룰렛_가게")
        pg.keyboard.press("Escape")
        time.sleep(1.5)
    # 음식 종류: 홈에서 「양식」 → 지도
    tap_text("홈", 1.5)
    wheel(195, 400, -9000, 1)
    if tap_scroll("양식", 5):
        shot("음식종류_양식_지도")
    # 테마 코스
    tap_text("홈", 1.5)
    wheel(195, 400, -4000, 1)
    if tap_scroll("먹방 유튜버 코스", 5) or tap_scroll("인기 맛집 하루 코스", 5):
        shot("코스_지도")
        if tap_text("순서 보기", 2.5, exact=False):
            shot("코스_순서")
            pg.keyboard.press("Escape")
            time.sleep(1.5)
        tap_text("코스 닫기", 2)
    # 지도 축소 (− 단추)
    tap_text("지도", 3)
    for _ in range(4):
        tap(356, 732, 1.2)
    time.sleep(3)
    shot("지도_축소_동네")
    for _ in range(3):
        tap(356, 732, 1.2)
    time.sleep(3)
    shot("지도_축소_시도")
    # 영상
    tap_text("영상")
    shot("영상")
    pg.set_viewport_size({"width": 820, "height": 1180})
    time.sleep(3)
    shot("태블릿_영상")
    pg.set_viewport_size({"width": W, "height": H})
    time.sleep(2)
    # 유튜버 따라 먹기 (전국)
    tap_text("홈", 1.5)
    wheel(195, 400, -4000, 1)
    wheel(195, 560, 650, 2)
    shot("홈_따라먹기")
    b = find("올라온 영상", exact=False)
    if b:
        log.append(f"새로 올라온 영상 위치 {b}")
    log.append("따라먹기 글자: " + " / ".join(x for x in labels() if "따라" in x or "전국" in x)[:600])
    ok = tap_text("전국 지도", 5)
    if not ok:
        b = find("따라 먹기", exact=False)
        log.append(f"따라 먹기 제목 위치 {b}")
        tap(352, 413, 5)  # 제목 줄 오른쪽 「전국 지도」 자리
        ok = True
    if ok:
        shot("따라가기_처음")
        for _ in range(4):
            tap(356, 732, 1.0)
        time.sleep(2.5)
        shot("따라가기_전국")
        for _ in range(2):
            tap(356, 690, 1.0)
        time.sleep(2.5)
        shot("따라가기_확대")
        if tap_text("성시경", 5):
            shot("따라가기_성시경")
        tap_text("따라가기 닫기", 2)
        shot("따라가기_닫음")
    tap_text("홈", 1.5)
    wheel(195, 400, -4000, 1)
    wheel(195, 560, 650, 2)
    b = find("올라온 영상", exact=False)
    if b:
        tap(120, b["y"] + 110, 5)
        shot("새영상_가게")
        pg.keyboard.press("Escape")
        time.sleep(1.5)
    # 이 집 어디야 + 콕
    tap_text("홈")
    wheel(195, 400, -4000, 1.5)
    if not tap_text("이 집 어디야", 4):
        tap(325, 290, 4)  # 오늘의 영상 「이 집 어디야」 자리
    if True:
        shot("가게")
        if tap_text("콕 하기", 1.5):
            shot("가게_콕")
        b = find("길찾기")
        log.append(f"길찾기 단추 위치 {b}")
        top = (b["y"] - 20) if b else 620
        drag(120, top, 90, 2.5)   # 시트(왼쪽 요약 글)를 잡고 끌어올려 끝까지
        shot("가게_끝까지")
        drag(120, 700, 300, 2.0)  # 안에서 위로 넘기기
        shot("가게_아래")
        if tap_text("정보 수정 신고", 2):
            tap_text("영업시간", 0.8)
            shot("정보수정신고")
            pg.keyboard.press("Escape")
            time.sleep(1.2)
        pg.keyboard.press("Escape")
        time.sleep(1.5)
    tap_text("내 콕")
    shot("내콕")
    if tap_text("최근 본 집", 1.5, exact=False):
        shot("내콕_최근")
    if tap_text("콕한 집", 1.5, exact=False):
        shot("내콕_콕한집")
    if tap_text("설정", 2):
        shot("설정")
        wheel(195, 600, 900, 1.5)
        shot("설정_아래")
        tap_text("뒤로", 1.5)
    # 지역 메뉴 → 영종도
    tap_text("홈")
    b = find("지역", exact=False)
    if b:
        pg.mouse.click(b["x"] + b["width"] / 2, b["y"] + b["height"] / 2)
        time.sleep(2)
        shot("지역메뉴")
        if tap_text("영종도", 4, exact=False):
            shot("홈_영종도")
            wheel(195, 560, 2500)
            shot("홈_영종도_아래")
            wheel(195, 400, -4000, 1)

with sync_playwright() as p:
    br = p.chromium.launch(args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
    ctx = br.new_context(
        viewport={"width": W, "height": H},
        device_scale_factor=2,
        locale="ko-KR",
        timezone_id="Asia/Seoul",
        geolocation={"latitude": 37.3925, "longitude": 126.6390},
        permissions=["geolocation"],
    )
    pg = ctx.new_page()
    pg.on("console", lambda m: log.append(f"[콘솔 {m.type}] {m.text[:300]}"))
    pg.on("pageerror", lambda e: log.append(f"[페이지 오류] {str(e)[:300]}"))
    try:
        pg.goto(URL, wait_until="load", timeout=120000)
        time.sleep(12)
        pg.evaluate("() => { const e = document.querySelector('flt-semantics-placeholder'); if (e) e.click(); }")
        time.sleep(2)
        run(pg)
    except Exception as e:
        log.append(f"[중단] {e}")
        try:
            pg.screenshot(path=f"{OUT}/99_중단.png")
        except Exception:
            pass
    # 넓은 화면도 한 장
    try:
        pg.set_viewport_size({"width": 1280, "height": 800})
        time.sleep(3)
        pg.screenshot(path=f"{OUT}/98_넓은화면.png")
    except Exception as e:
        log.append(f"[넓은 화면] {e}")
    # 약관 페이지
    try:
        pg.set_viewport_size({"width": W, "height": H})
        pg.goto(URL.rstrip("/") + "/policy/terms.html", wait_until="load", timeout=60000)
        time.sleep(2)
        pg.screenshot(path=f"{OUT}/97_이용약관.png", full_page=True)
    except Exception as e:
        log.append(f"[약관] {e}")
    # 내 위치가 영종도일 때 홈 첫 동네
    try:
        c2 = br.new_context(
            viewport={"width": W, "height": H},
            device_scale_factor=2,
            locale="ko-KR",
            timezone_id="Asia/Seoul",
            geolocation={"latitude": 37.4920, "longitude": 126.4930},
            permissions=["geolocation"],
        )
        p2 = c2.new_page()
        p2.goto(URL, wait_until="load", timeout=120000)
        time.sleep(14)
        p2.screenshot(path=f"{OUT}/96_내위치_영종도.png")
        c2.close()
    except Exception as e:
        log.append(f"[내 위치 영종도] {e}")
    br.close()

with open(f"{OUT}/log.txt", "w", encoding="utf-8") as f:
    f.write("\n".join(log))
print("\n".join(log[-80:]))
