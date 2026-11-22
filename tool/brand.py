"""자동 제작 때 콕플 얼굴을 입힌다: 앱 이름 · 아이콘 · 시작 화면.

    python3 tool/brand.py android   # flutter create 뒤, 안드로이드 아이콘·시작 화면
    python3 tool/brand.py web       # flutter create 뒤, 웹 아이콘·홈 화면 이름·첫 화면

그림은 tool/brand/ 에 미리 만들어 둔 것을 복사만 한다 (제작 서버에 그림 도구가 없어도 되게).
웹은 지난번 화면을 꺼내 쓰는 저장분이 있으면 이 단계를 건너뛰므로, 이 파일이 바뀌면 화면을 새로 만든다.
"""
import json
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "brand")
NAME = "콕플"
FULL = "콕플 – 유튜브 맛집 지도"
DESC = "유튜버가 다녀간 맛집을 지도에서 한눈에 — 콕플"
SPLASH = "#F7721C"  # 시작 화면 바탕 (인트로 그림 위쪽 색)


def copy_tree(src, dst):
    n = 0
    for base, _, files in os.walk(src):
        for f in files:
            s = os.path.join(base, f)
            d = os.path.join(dst, os.path.relpath(s, src))
            os.makedirs(os.path.dirname(d), exist_ok=True)
            shutil.copyfile(s, d)
            n += 1
    return n


def android():
    res = "android/app/src/main/res"
    n = copy_tree(os.path.join(SRC, "android", "res"), res)
    print(f"안드로이드 아이콘·시작 화면 {n}개 넣음")


def web():
    n = copy_tree(os.path.join(SRC, "web"), "web")
    # 홈 화면 바로가기 이름·색
    mp = "web/manifest.json"
    m = json.load(open(mp, encoding="utf-8"))
    m.update({"name": FULL, "short_name": NAME, "description": DESC, "background_color": SPLASH, "theme_color": SPLASH})
    json.dump(m, open(mp, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    # 첫 화면 (index.html)
    ip = "web/index.html"
    h = open(ip, encoding="utf-8").read()
    h = re.sub(r'<meta name="description" content="[^"]*">', f'<meta name="description" content="{DESC}">', h)
    h = re.sub(r'<meta name="apple-mobile-web-app-title" content="[^"]*">', f'<meta name="apple-mobile-web-app-title" content="{NAME}">', h)
    h = re.sub(r"<title>.*?</title>", f"<title>{FULL}</title>", h, flags=re.S)
    if 'name="theme-color"' not in h:
        h = h.replace("</head>", f'  <meta name="theme-color" content="{SPLASH}">\n'
                                 '  <link rel="preload" as="image" href="assets/assets/brand/mark.png">\n'
                                 '  <link rel="preload" as="image" href="assets/assets/brand/intro.jpg">\n</head>', 1)
    # 앱이 뜨기 전 첫 화면: 주황 바탕 가운데 캐릭터 (앱 인트로의 첫 장면과 똑같은 자리·크기)
    splash = f"""
  <!-- 콕플 첫 화면 -->
  <style id="kok-splash-css">
    html, body {{ background: {SPLASH}; margin: 0; }}
    #kok-splash {{ position: fixed; inset: 0; background: {SPLASH}; z-index: 9999; pointer-events: none; }}
    #kok-splash img {{ position: absolute; left: 50%; top: 50%; width: 109.5px; height: 145px; transform: translate(-50%, -50%); }}
  </style>
  <div id="kok-splash"><img src="assets/assets/brand/mark.png" alt=""></div>
  <script>
    (function () {{
      var gone = false;
      function off() {{
        if (gone) return; gone = true;
        var s = document.getElementById('kok-splash'); if (s) s.remove();
        document.documentElement.style.background = ''; document.body.style.background = '';
        var c = document.getElementById('kok-splash-css'); if (c) c.remove();
      }}
      window.addEventListener('flutter-first-frame', off);
      setTimeout(off, 15000);
    }})();
  </script>
"""
    if "kok-splash" not in h:
        h = re.sub(r"<body>", "<body>" + splash, h, count=1)
    open(ip, "w", encoding="utf-8").write(h)
    print(f"웹 아이콘 {n}개 · 이름 「{NAME}」 · 첫 화면 넣음")


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else ""
    if what == "android":
        android()
    elif what == "web":
        web()
    else:
        print("사용: python3 tool/brand.py android|web")
        sys.exit(1)
