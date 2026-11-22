"""콕플 스티커 12종 — 캐릭터(핀 모양) 표정 + 소품 + 이름표, 다이컷 흰 테두리."""
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

import pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
F = str(ROOT / 'assets/fonts') + '/'
OUT = '/tmp/sticker/out'  # 만든 뒤 256색으로 줄여 assets/stickers/ 에 넣는다
os.makedirs(OUT, exist_ok=True)
INK = (80, 17, 1, 255)
CREAM = (252, 249, 242, 255)
RED = (255, 75, 43, 255)
ORANGE = (251, 104, 20, 255)
YELLOW = (255, 197, 49, 255)
GOLD = (255, 186, 38, 255)
PINK = (255, 112, 150, 255)
BLUSH = (255, 150, 140, 170)
DROP = (110, 185, 255, 255)
WHITE = (255, 255, 255, 255)
GRAYLB = (139, 122, 112, 255)

base = Image.open(ROOT / 'tool/brand/char_full.png').convert('RGBA')  # 1254, 캐릭터 (200,80)-(1038,1191)


def blank():
    """얼굴(눈·입)을 지운 캐릭터 (재생 단추는 남김)."""
    im = base.copy()
    m = Image.new('L', im.size, 0)
    ImageDraw.Draw(m).ellipse((320, 330, 920, 760), fill=255)
    fill = Image.new('RGBA', im.size, CREAM)
    im.paste(fill, (0, 0), m)
    return im


W = 36  # 얼굴 선 굵기 (1254 기준)
EL, ER, EY = (490, 440), (765, 440), 440  # 눈 자리
MC = (625, 585)  # 입 자리 (재생 단추와 닿지 않게)


def arc_eye(d, c, up=True, w=W, r=62):
    x, y = c
    if up:  # ^ 모양 (웃는 눈)
        d.arc((x - r, y - r * 0.85, x + r, y + r * 0.85), 200, 340, fill=INK, width=w)
    else:
        d.arc((x - r, y - r * 0.85, x + r, y + r * 0.85), 20, 160, fill=INK, width=w)


def dot_eye(d, c, r=34):
    x, y = c
    d.ellipse((x - r, y - r * 1.15, x + r, y + r * 1.15), fill=INK)
    d.ellipse((x - r * 0.15, y - r * 0.85, x + r * 0.45, y - r * 0.25), fill=WHITE)


def heart(d, cx, cy, s, fill, outline=INK, ow=0):
    # 하트: 두 원 + 아래 삼각형
    pts = []
    for t in np.linspace(0, 2 * math.pi, 120):
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x * s / 17, cy - y * s / 17))
    if ow:
        d.polygon(pts, fill=outline)
        pts2 = []
        k = (s - ow * 1.2) / s
        for (x, y) in pts:
            pts2.append((cx + (x - cx) * k, cy + (y - cy) * k + ow * 0.1))
        d.polygon(pts2, fill=fill)
    else:
        d.polygon(pts, fill=fill)


def star(d, cx, cy, r, fill, rot=-90, inner=0.48, outline=None, ow=0):
    pts = []
    for i in range(10):
        a = math.radians(rot + i * 36)
        rr = r if i % 2 == 0 else r * inner
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    if outline:
        d.line(pts + [pts[0]], fill=outline, width=ow, joint='curve')
    d.polygon(pts, fill=fill)


def sparkle(d, cx, cy, r, fill):
    pts = [(cx, cy - r), (cx + r * 0.22, cy - r * 0.22), (cx + r, cy), (cx + r * 0.22, cy + r * 0.22),
           (cx, cy + r), (cx - r * 0.22, cy + r * 0.22), (cx - r, cy), (cx - r * 0.22, cy - r * 0.22)]
    d.polygon(pts, fill=fill)


def mouth_open(d, c=MC, w=240, h=150, tongue=True):
    """원래 캐릭터처럼 진한 D 모양 입 + 아래쪽에만 보이는 혀."""
    x, y = c
    box = (x - w / 2, y - h * 0.55, x + w / 2, y + h * 0.95)
    m = Image.new('L', d.im.size, 0)
    ImageDraw.Draw(m).chord(box, 0, 180, fill=255)
    d.chord(box, 0, 180, fill=INK)
    if tongue:
        t = Image.new('L', d.im.size, 0)
        ImageDraw.Draw(t).ellipse((x - w * 0.26, y + h * 0.42, x + w * 0.22, y + h * 1.25), fill=255)
        from PIL import ImageChops
        t = ImageChops.multiply(t, m)
        d.bitmap((0, 0), t, fill=(255, 107, 70, 255))


def mouth_smile(d, c=MC, w=170, h=120, ww=W):
    x, y = c
    d.arc((x - w / 2, y - h, x + w / 2, y + h * 0.4), 25, 155, fill=INK, width=ww)


def mouth_sad(d, c=MC, w=150, h=90, ww=W):
    x, y = c
    d.arc((x - w / 2, y + 10, x + w / 2, y + h * 1.6), 205, 335, fill=INK, width=ww)


def mouth_o(d, c=MC, r=54):
    x, y = c
    d.ellipse((x - r * 0.85, y - r, x + r * 0.85, y + r * 1.05), fill=INK)
    d.ellipse((x - r * 0.45, y + r * 0.15, x + r * 0.45, y + r * 0.8), fill=(255, 107, 70, 255))


def mouth_wavy(d, c=MC, w=170, ww=W):
    x, y = c
    pts = [(x - w / 2 + i * w / 40, y + 18 * math.sin(i / 40 * 4 * math.pi)) for i in range(41)]
    d.line(pts, fill=INK, width=ww, joint='curve')


def blush(img):
    lay = Image.new('RGBA', img.size, (0, 0, 0, 0))
    dd = ImageDraw.Draw(lay)
    for cx in (395, 860):
        dd.ellipse((cx - 62, 520, cx + 62, 585), fill=BLUSH)
    lay = lay.filter(ImageFilter.GaussianBlur(6))
    img.alpha_composite(lay)


def face(kind):
    im = blank()
    d = ImageDraw.Draw(im)
    if kind == 'happy':
        arc_eye(d, EL); arc_eye(d, ER); mouth_open(d)
    elif kind == 'wink':
        arc_eye(d, EL); dot_eye(d, ER); mouth_open(d, w=230, h=160)
    elif kind == 'hearts':
        heart(d, *EL, 78, RED); heart(d, *ER, 78, RED); mouth_open(d, w=230, h=150)
    elif kind == 'stars':
        star(d, *EL, 80, GOLD, inner=0.5); star(d, *ER, 80, GOLD, inner=0.5)
        star(d, *EL, 80, GOLD, inner=0.5, outline=INK, ow=14); star(d, *ER, 80, GOLD, inner=0.5, outline=INK, ow=14)
        mouth_open(d, w=260, h=160)
    elif kind == 'sad':
        dot_eye(d, (EL[0] + 10, EY + 20), r=28); dot_eye(d, (ER[0] - 10, EY + 20), r=28)
        d.line([(EL[0] - 60, EY - 60), (EL[0] + 40, EY - 85)], fill=INK, width=26)
        d.line([(ER[0] - 40, EY - 85), (ER[0] + 60, EY - 60)], fill=INK, width=26)
        mouth_sad(d, (MC[0], MC[1] + 10))
    elif kind == 'tired':
        d.line([(EL[0] - 55, EY + 10), (EL[0] + 55, EY + 10)], fill=INK, width=W)
        d.line([(ER[0] - 55, EY + 10), (ER[0] + 55, EY + 10)], fill=INK, width=W)
        mouth_wavy(d, (MC[0], MC[1] + 10))
    elif kind == 'wow':
        dot_eye(d, EL, r=40); dot_eye(d, ER, r=40); mouth_o(d, (MC[0], MC[1] + 5))
    elif kind == 'content':
        arc_eye(d, EL); arc_eye(d, ER); mouth_smile(d, (MC[0], MC[1] - 10))
    elif kind == 'bow':
        arc_eye(d, (EL[0], EY + 15), up=False); arc_eye(d, (ER[0], EY + 15), up=False); mouth_smile(d, (MC[0], MC[1] - 5), w=140)
    if kind in ('hearts', 'content', 'bow', 'happy', 'wink'):
        blush(im)
    return im


# ---- 그릇 위 소품들 (960 캔버스 기준) ----
OW = 16  # 소품 테두리 굵기


def crown(d, cx, cy, w):
    h = w * 0.62
    pts = [(cx - w / 2, cy + h / 2), (cx - w / 2, cy - h * 0.15), (cx - w * 0.25, cy + h * 0.12), (cx, cy - h / 2),
           (cx + w * 0.25, cy + h * 0.12), (cx + w / 2, cy - h * 0.15), (cx + w / 2, cy + h / 2)]
    d.polygon(pts, fill=GOLD, outline=INK)
    d.line(pts + [pts[0]], fill=INK, width=OW, joint='curve')
    for px in (cx - w / 2, cx, cx + w / 2):
        py = cy - h * 0.15 if px != cx else cy - h / 2
        d.ellipse((px - 16, py - 16, px + 16, py + 16), fill=RED, outline=INK, width=8)


def clock(d, cx, cy, r, face_fill=WHITE, ring=ORANGE):
    for sx in (-1, 1):  # 종
        d.ellipse((cx + sx * r * 0.75 - r * 0.35, cy - r * 1.05 - r * 0.2, cx + sx * r * 0.75 + r * 0.35, cy - r * 1.05 + r * 0.45), fill=ring, outline=INK, width=OW)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=ring, outline=INK, width=OW)
    d.ellipse((cx - r * 0.76, cy - r * 0.76, cx + r * 0.76, cy + r * 0.76), fill=face_fill, outline=INK, width=10)
    d.line([(cx, cy), (cx, cy - r * 0.52)], fill=INK, width=14)
    d.line([(cx, cy), (cx + r * 0.38, cy + r * 0.1)], fill=INK, width=14)
    d.ellipse((cx - 12, cy - 12, cx + 12, cy + 12), fill=INK)


def drop(d, cx, cy, r):
    pts = [(cx, cy - r * 1.6)]
    for t in np.linspace(-0.25 * math.pi, 1.25 * math.pi, 40):
        pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
    d.polygon(pts, fill=DROP, outline=INK)
    d.line(pts + [pts[0]], fill=INK, width=10, joint='curve')
    d.ellipse((cx - r * 0.45, cy - r * 0.35, cx - r * 0.05, cy + r * 0.1), fill=(255, 255, 255, 220))


def bowl(d, cx, cy, w, rice=True, steam=True):
    h = w * 0.5
    if rice:
        d.chord((cx - w * 0.42, cy - h * 1.05, cx + w * 0.42, cy + h * 0.55), 180, 360, fill=WHITE, outline=INK, width=OW)
        for i in range(9):  # 밥알 느낌
            x = cx - w * 0.28 + (i % 5) * w * 0.14
            y = cy - h * 0.55 + (i // 5) * h * 0.25 + (i % 2) * 10
            d.ellipse((x - 9, y - 5, x + 9, y + 5), fill=(235, 228, 214, 255))
    d.chord((cx - w / 2, cy - h * 0.55, cx + w / 2, cy + h), 0, 180, fill=RED, outline=INK, width=OW)
    d.line([(cx - w / 2, cy + h * 0.2), (cx + w / 2, cy + h * 0.2)], fill=INK, width=OW)
    d.rounded_rectangle((cx - w * 0.2, cy + h * 0.88, cx + w * 0.2, cy + h * 1.05), 8, fill=RED, outline=INK, width=10)
    d.arc((cx - w * 0.3, cy + h * 0.3, cx + w * 0.3, cy + h * 0.8), 20, 160, fill=(255, 255, 255, 150), width=8)
    if steam:
        for sx in (-0.18, 0.05, 0.28):
            x0 = cx + sx * w
            pts = [(x0 + 14 * math.sin(i / 12 * 2 * math.pi), cy - h * 1.15 - i * 9) for i in range(13)]
            d.line(pts, fill=(200, 190, 180, 255), width=10, joint='curve')


def coins(d, cx, cy, r):
    for i, dy in enumerate((0, -34, -68)):
        y = cy + dy
        d.ellipse((cx - r, y - r * 0.38, cx + r, y + r * 0.38 + 26), fill=GOLD, outline=INK, width=OW)
        d.ellipse((cx - r, y - r * 0.38, cx + r, y + r * 0.38), fill=YELLOW, outline=INK, width=OW)
    # 맨 위 동전에 원 표시 (W 에 가로줄 둘)
    y = cy - 68
    w2, h2 = r * 0.5, r * 0.26
    pts = [(cx - w2, y - h2), (cx - w2 * 0.5, y + h2), (cx, y - h2 * 0.2), (cx + w2 * 0.5, y + h2), (cx + w2, y - h2)]
    d.line(pts, fill=INK, width=12, joint='curve')
    d.line([(cx - w2 * 1.05, y - 2), (cx + w2 * 1.05, y - 2)], fill=INK, width=8)


def spoon(d, x, y, l, ang=-60):
    a = math.radians(ang)
    ex, ey = x + l * math.cos(a), y + l * math.sin(a)
    d.line([(x, y), (ex, ey)], fill=INK, width=30)
    d.line([(x, y), (ex, ey)], fill=(200, 205, 212, 255), width=12)
    hx, hy = ex + 40 * math.cos(a), ey + 40 * math.sin(a)
    d.ellipse((hx - 36, hy - 48, hx + 36, hy + 48), fill=(200, 205, 212, 255), outline=INK, width=OW)


def menu_board(d, cx, cy, w, h):
    d.line([(cx - w * 0.22, cy + h / 2), (cx - w * 0.3, cy + h / 2 + 60)], fill=INK, width=OW)
    d.line([(cx + w * 0.22, cy + h / 2), (cx + w * 0.3, cy + h / 2 + 60)], fill=INK, width=OW)
    d.rounded_rectangle((cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), 26, fill=(255, 247, 226, 255), outline=INK, width=OW)
    d.rounded_rectangle((cx - w / 2 + 22, cy - h / 2 + 22, cx + w / 2 - 22, cy + h / 2 - 22), 14, outline=(240, 200, 150, 255), width=6)


def stamp(img, cx, cy, r, text):
    lay = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=WHITE, outline=RED, width=16)
    d.ellipse((cx - r * 0.82, cy - r * 0.82, cx + r * 0.82, cy + r * 0.82), outline=RED, width=7)
    f = ImageFont.truetype(F + 'Pretendard-Black.otf', int(r * 0.62))
    d.text((cx, cy + 4), text, font=f, fill=RED, anchor='mm')
    lay = lay.rotate(-14, center=(cx, cy), resample=Image.BICUBIC)
    img.alpha_composite(lay)


def place_char(canvas, ch, cx, top, height):
    """캐릭터(1254 캔버스)를 키 height로 줄여 가운데 cx, 위 top에 놓는다."""
    s = height / 1111
    c = ch.crop((200, 80, 1038, 1191)).resize((round(838 * s), round(1111 * s)), Image.LANCZOS)
    canvas.alpha_composite(c, (round(cx - c.width / 2), round(top)))
    return s


S = 960


def label(img, text, color, y=None):
    """이름표: 짧은 이름은 글씨를 크게 (작은 화면에서도 읽히게), 긴 이름은 판 안에 들어가게."""
    d = ImageDraw.Draw(img)
    fs = 134
    while fs > 80:
        f = ImageFont.truetype(F + 'Pretendard-Black.otf', fs)
        if d.textlength(text, font=f) <= 770:
            break
        fs -= 2
    tw = d.textlength(text, font=f)
    w, h = tw + fs * 1.05, round(fs * 1.56)
    y = y or S - h - 34
    x = (S - w) / 2
    d.rounded_rectangle((x, y, x + w, y + h), h / 2, fill=color, outline=INK, width=14)
    d.text((S / 2, y + h / 2 + fs * 0.04), text, font=f, fill=WHITE, anchor='mm')


def diecut(img):
    """다이컷 스티커: 흰 테두리 + 아주 옅은 그림자, 480 크기로."""
    a = img.getchannel('A')
    grow = a.filter(ImageFilter.MaxFilter(29)).filter(ImageFilter.MaxFilter(9))
    grow = grow.point(lambda v: 255 if v > 30 else 0).filter(ImageFilter.GaussianBlur(1.2))
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    sh = Image.new('RGBA', img.size, (60, 30, 10, 0))
    sh.putalpha(grow.filter(ImageFilter.GaussianBlur(14)).point(lambda v: int(v * 0.16)))
    out.alpha_composite(sh, (0, 6))
    white = Image.new('RGBA', img.size, WHITE)
    white.putalpha(grow)
    out.alpha_composite(white)
    out.alpha_composite(img)
    return out.resize((360, 360), Image.LANCZOS)


def make(key, text, color, kind, extra=None, char_top=70, char_h=560, char_cx=S / 2):
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ch = face(kind)
    if extra and extra.get('before'):
        extra['before'](img)
    place_char(img, ch, char_cx, char_top, char_h)
    if extra and extra.get('after'):
        extra['after'](img)
    label(img, text, color)
    diecut(img).save(f'{OUT}/{key}.png')


def after(fn):
    def run(img):
        fn(ImageDraw.Draw(img), img)
    return run


# 1. 유튜버 입맛 인정
make('yt_ok', '유튜버 입맛 인정', RED, 'wink', {'after': after(lambda d, im: stamp(im, 760, 210, 120, '인정'))}, char_cx=430)
# 2. 또 올 집
def hearts_fn(d, im):
    heart(d, 175, 230, 70, PINK, ow=14); heart(d, 800, 170, 86, RED, ow=14); heart(d, 820, 420, 52, PINK, ow=12)
make('again', '또 올 집', RED, 'hearts', {'after': after(hearts_fn)})
# 3. 인생 맛집
def life_fn(d, im):
    crown(d, 480, 92, 230)
    sparkle(d, 170, 260, 60, GOLD); sparkle(d, 810, 300, 70, GOLD); sparkle(d, 760, 140, 36, YELLOW); sparkle(d, 200, 440, 34, YELLOW)
make('life', '인생 맛집', RED, 'stars', {'after': after(life_fn)}, char_top=110, char_h=530)
# 4. 기대보다 아쉬움 (부드럽게)
make('meh', '기대보다 아쉬움', GRAYLB, 'sad', {'after': after(lambda d, im: drop(d, 760, 250, 46))})
# 5. 웨이팅할 만함
make('wait_ok', '웨이팅할 만함', ORANGE, 'content', {'after': after(lambda d, im: (clock(d, 770, 300, 105), sparkle(d, 640, 140, 38, GOLD)))}, char_cx=400)
# 6. 웨이팅은 비추
make('wait_no', '웨이팅은 비추', GRAYLB, 'tired', {'after': after(lambda d, im: (clock(d, 770, 300, 105, ring=(205, 190, 178, 255)), drop(d, 245, 230, 40)))}, char_cx=400)
# 7. 양 많음
make('big', '양 많음', ORANGE, 'wow', {'after': after(lambda d, im: bowl(d, 700, 560, 330))}, char_cx=360, char_h=520, char_top=60)
# 8. 가성비 굿
make('value', '가성비 굿', ORANGE, 'happy', {'after': after(lambda d, im: (coins(d, 760, 520, 118), sparkle(d, 820, 230, 46, GOLD)))}, char_cx=390)
# 9. 혼밥 OK
make('solo', '혼밥 OK', ORANGE, 'content', {'after': after(lambda d, im: (bowl(d, 730, 600, 250, steam=True), spoon(d, 560, 640, 150, ang=-110)))}, char_cx=370, char_h=520)
# 10. 데이트 추천: 캐릭터 둘 + 하트
def date_make():
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    place_char(img, face('content'), 300, 170, 440)
    place_char(img, face('hearts'), 660, 170, 440)
    d = ImageDraw.Draw(img)
    heart(d, 480, 150, 92, RED, ow=14)
    sparkle(d, 330, 110, 34, GOLD); sparkle(d, 640, 96, 30, GOLD)
    label(img, '데이트 추천', RED)
    diecut(img).save(f'{OUT}/date.png')
date_make()
# 11. ○○ 꼭 시키세요 (메뉴 이름은 앱이 판 위에 씀)
# 메뉴 판을 크게 (앱이 판 안에 메뉴 이름을 큼직하게 씀) + 캐릭터가 왼쪽 아래에서 판을 받쳐 듦
def menu_make():
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    menu_board(d, 540, 268, 680, 380)  # 판: x 200~880, y 78~458
    sparkle(d, 150, 120, 46, GOLD); sparkle(d, 905, 520, 34, YELLOW)
    place_char(img, face('wink'), 215, 330, 430)
    label(img, '꼭 시키세요', RED)
    diecut(img).save(f'{OUT}/menu.png')
menu_make()
# 12. 사장님 친절
def kind_fn(d, im):
    heart(d, 790, 230, 66, PINK, ow=12); heart(d, 180, 300, 50, PINK, ow=10); sparkle(d, 760, 420, 40, GOLD)
make('kind', '사장님 친절', ORANGE, 'bow', {'after': after(kind_fn)})

# 한 장으로 모아 보기
keys = ['yt_ok', 'again', 'life', 'meh', 'wait_ok', 'wait_no', 'big', 'value', 'solo', 'date', 'menu', 'kind']
sheet = Image.new('RGBA', (4 * 250 + 40, 3 * 250 + 40), (246, 244, 241, 255))
for i, k in enumerate(keys):
    s = Image.open(f'{OUT}/{k}.png').resize((240, 240), Image.LANCZOS).convert('RGBA')
    sheet.alpha_composite(s, (20 + (i % 4) * 250, 20 + (i // 4) * 250))
sheet.convert('RGB').save(OUT + '/sheet.png')
print('완료')


# 공감 단추용 작은 하트 스티커 (이름표 없이, 웃는 얼굴)
def like_make():
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    heart(d, 480, 500, 380, RED, ow=24)
    d.ellipse((370 - 30, 430 - 36, 370 + 30, 430 + 36), fill=INK)
    d.ellipse((590 - 30, 430 - 36, 590 + 30, 430 + 36), fill=INK)
    d.ellipse((360 - 8, 410 - 16, 360 + 14, 410 + 4), fill=WHITE)
    d.ellipse((580 - 8, 410 - 16, 580 + 14, 410 + 4), fill=WHITE)
    d.arc((420, 440, 540, 560), 25, 155, fill=INK, width=26)
    d.ellipse((285, 500, 355, 540), fill=(255, 170, 160, 255)); d.ellipse((605, 500, 675, 540), fill=(255, 170, 160, 255))
    d.ellipse((300, 250, 380, 300), fill=(255, 255, 255, 120))
    diecut(img).resize((160, 160), Image.LANCZOS).save(f'{OUT}/like.png')


like_make()
