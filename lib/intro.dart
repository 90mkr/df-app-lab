part of 'main.dart';

// ---------------- 시작 화면 (인트로) ----------------
// 안드로이드 시작 화면(가운데 캐릭터)·웹 첫 화면과 똑같은 장면에서 이어서:
// 캐릭터가 위로 올라가며 작아지고, 아래에서 맛집 지도 그림이 떠오르고, 「콕플」 글자가 나타난 뒤 앱으로 넘어간다.
// 화면을 누르면 바로 넘어간다. 움직임 줄이기를 켠 휴대폰은 움직임 없이 잠깐 보여 준다.

const kIntroBg = Color(0xFFF7721C); // 인트로 그림 위쪽 색 (안드로이드·웹 시작 화면 바탕과 같음)
const kIntroArt = 'assets/brand/intro.jpg'; // 941 x 2160 (위쪽 빈 주황을 늘려 긴 화면도 잘리지 않게)
const kIntroMark = 'assets/brand/mark.png'; // 캐릭터만 (438 x 580)
const kIntroWord = 'assets/brand/word.png'; // 「콕플」 + 「유튜브 맛집 지도」 (3배로 그린 것)
const _kArtW = 941.0, _kArtH = 2160.0, _kArtMapTop = 1161.0; // 그림에서 지도(남산타워 끝)가 시작되는 줄
const _kMarkW = 438.0, _kMarkH = 580.0;
const _kWordW = 111.33, _kWordH = 71.0; // 글자 그림의 1배 크기
const _kSplashW = 109.5, _kSplashH = 145.0; // 시작 화면 캐릭터 크기 (안드로이드 288dp 상자 안 크기와 같게)
const _kHold = 0.45, _kFade = 0.80; // 움직임이 끝나는 때 · 사라지기 시작하는 때 (전체 2초 중)

// 시작 화면 그림을 먼저 읽어 둔다: 첫 장면부터 캐릭터가 바로 보이게 (늦어도 1.5초만 기다림)
Future<void> introWarmUp() async {
  Future<void> one(String a) {
    final done = Completer<void>();
    final s = AssetImage(a).resolve(ImageConfiguration.empty);
    late final ImageStreamListener l;
    void fin() {
      if (!done.isCompleted) done.complete();
    }

    l = ImageStreamListener((_, __) => fin(), onError: (_, __) => fin());
    s.addListener(l);
    return done.future.whenComplete(() => s.removeListener(l));
  }

  try {
    await Future.wait([one(kIntroMark), one(kIntroWord), one(kIntroArt)]).timeout(const Duration(milliseconds: 1500));
  } catch (_) {}
}

class KokIntro extends StatefulWidget {
  final Widget child;
  const KokIntro({super.key, required this.child});
  @override
  State<KokIntro> createState() => _KokIntroState();
}

class _KokIntroState extends State<KokIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _done = true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) _c.value = _kHold;
      _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _skip() {
    if (!_done && _c.value < _kFade) _c.forward(from: _kFade);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return Stack(alignment: Alignment.topLeft, children: [
      widget.child,
      Positioned.fill(
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _skip,
            child: AnimatedBuilder(animation: _c, builder: (context, _) => _scene(context)),
          ),
        ),
      ),
    ]);
  }

  double _iv(double a, double b, Curve c) => c.transform(((_c.value - a) / (b - a)).clamp(0.0, 1.0));

  Widget _scene(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width, h = mq.size.height;
    if (w <= 0 || h <= 0) return const ColoredBox(color: kIntroBg);
    // 넓은 화면(태블릿 가로·PC)은 휴대폰 비율 틀 안에 그린다
    final fw = w / h > 0.75 ? h * 0.5625 : w;
    // 그림: 틀을 가득 채우고 아래에 맞춘다 (위쪽은 빈 주황이라 잘려도 그만)
    final s = math.max(h, fw * _kArtH / _kArtW);
    final iw = s * _kArtW / _kArtH;
    final mapTop = h - s + s * _kArtMapTop / _kArtH;
    // 로고 묶음 (캐릭터 + 글자): 상태 표시줄 아래 ~ 지도 시작 사이 가운데, 살짝 위로
    final k = (fw / 390).clamp(0.9, 1.25).toDouble();
    final mh = 84 * k, mw = mh * _kMarkW / _kMarkH;
    final ww = _kWordW * k, wh = _kWordH * k, gap = 18 * k;
    final cy = (mq.padding.top + mapTop) / 2 - 8 * k;
    final end = Rect.fromLTWH((w - mw) / 2, cy - (mh + gap + wh) / 2, mw, mh);
    final start = Rect.fromCenter(center: Offset(w / 2, h / 2), width: _kSplashW, height: _kSplashH);
    final mark = Rect.lerp(start, end, _iv(0, 0.32, Curves.easeInOutCubic))!;
    final art = _iv(0.08, 0.36, Curves.easeOutCubic);
    final word = _iv(0.25, 0.45, Curves.easeOutCubic);
    final out = _iv(_kFade, 1.0, Curves.easeIn);
    return Opacity(
      opacity: 1 - out,
      child: ColoredBox(
        color: kIntroBg,
        child: Stack(alignment: Alignment.topLeft, children: [
          Positioned(
            left: (w - iw) / 2,
            top: h - s + (1 - art) * 26 * k,
            width: iw,
            height: s,
            child: Opacity(opacity: art, child: Image.asset(kIntroArt, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium)),
          ),
          Positioned.fromRect(rect: mark, child: Image.asset(kIntroMark, fit: BoxFit.fill, filterQuality: FilterQuality.medium)),
          Positioned(
            left: (w - ww) / 2,
            top: end.bottom + gap + (1 - word) * 10 * k,
            width: ww,
            height: wh,
            child: Opacity(opacity: word, child: Image.asset(kIntroWord, fit: BoxFit.fill, filterQuality: FilterQuality.medium)),
          ),
        ]),
      ),
    );
  }
}
