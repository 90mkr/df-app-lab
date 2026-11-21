part of 'main.dart';

// ---------------- 콕플 시안: 홈 · 영상 · 내 콕 · 아래 탭 · 룰렛 · 테마 코스 ----------------

const kAccent = Color(0xFFFF4B2B); // 콕플 대표색 (시안)
const kSub = Color(0xFF6B6B75); // 보조 글색 (시안)
const kHair = Color(0xFFECECF0); // 가는 구분선
const kPillLine = Color(0xFFDCDCE2);
const kCardLine = Color(0xFFE4E4E9);
const kAccentTint = Color(0xFFFFF1EE);
const kHomeMax = 560.0; // 넓은 화면에서 홈·영상·내 콕 폭

// 요리 경연 방송 (코스를 묶을 때만 씀 — 방송 이름은 코스명·배지에 쓰지 않는다)
const kCookShows = {'흑백요리사', '한식대첩', '마스터셰프 코리아', '냉장고를 부탁해'};

BoxDecoration kokCard() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: kCardLine, width: 1),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)],
    );

// 넓은 화면에서는 가운데 좁은 폭으로
Widget narrow(Widget child) => LayoutBuilder(
      builder: (_, c) => Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: math.min(c.maxWidth, kHomeMax), height: c.maxHeight, child: child),
      ),
    );

// 유튜버 (채널)
class Chan {
  final String id, name, thumb;
  final int subs;
  final List<String> places; // 다녀간 가게 id
  Chan(this.id, this.name, this.thumb, this.subs, this.places);
  factory Chan.fromJson(Map<String, dynamic> j) => Chan(
        '${j['id'] ?? ''}',
        '${j['name'] ?? ''}',
        '${j['thumb'] ?? ''}',
        (j['subs'] ?? 0) as int,
        ((j['places'] ?? []) as List).map((e) => '$e').toList(),
      );
  String get initial => name.isEmpty ? '?' : String.fromCharCode(name.runes.first);
}

// 가게에 다녀간 유튜버 수 (채널 id가 있으면 id로, 없으면 채널 이름으로)
int ytCount(Place p) => p.vids.map((v) => v.cid.isNotEmpty ? v.cid : v.channel).where((x) => x.isNotEmpty).toSet().length;

// 동네 유튜버 목록: 수집기가 만든 목록이 있으면 그것, 없으면 영상의 채널 이름으로 묶는다
List<Chan> channelsOf(SongdoData d) {
  if (d.channels.isNotEmpty) return d.channels;
  final m = <String, List<String>>{};
  for (final p in d.places.where((p) => p.top)) {
    for (final ch in p.vids.map((v) => v.channel).where((x) => x.isNotEmpty).toSet()) {
      m.putIfAbsent(ch, () => []).add(p.id);
    }
  }
  final out = [for (final e in m.entries) Chan(e.key, e.key, '', 0, e.value)];
  out.sort((a, b) => b.places.length.compareTo(a.places.length));
  return out;
}

// 유튜버가 많이 찾은 순
List<Place> ytRank(SongdoData d) {
  final l = d.places.where((p) => p.top && p.vids.isNotEmpty).toList();
  l.sort((a, b) {
    final c = ytCount(b).compareTo(ytCount(a));
    return c != 0 ? c : b.score.compareTo(a.score);
  });
  return l;
}

// 인기 순 (영상이 아직 없는 동네용)
List<Place> popRank(SongdoData d) => d.places.where((p) => p.top && p.score > 0).toList()..sort((a, b) => b.score.compareTo(a.score));

// 오늘의 영상: 유튜버가 많이 찾은 집 가운데 날마다 돌아가며 (영상이 없는 동네는 인기 맛집)
Place? todaysPlace(SongdoData d) {
  var l = ytRank(d).take(7).toList();
  if (l.isEmpty) l = popRank(d).take(7).toList();
  if (l.isEmpty) return null;
  final t = nowKst();
  final day = t.difference(DateTime.utc(t.year)).inDays;
  return l[day % l.length];
}

// 동 이름 (없으면 주소의 구·군)
String dongOf(Place p) {
  if (p.dong.isNotEmpty) return p.dong;
  for (final t in p.addr.split(' ').skip(1)) {
    if (t.endsWith('구') || t.endsWith('군')) return t;
  }
  return '';
}

String metaOf(Place p) {
  final o = openInfo(p);
  final dn = dongOf(p);
  return [if (dn.isNotEmpty) dn, if (p.cat.isNotEmpty) p.cat, if (o != null) o.short].join(' · ');
}

String subsText(int s) {
  if (s <= 0) return '';
  if (s >= 10000) return '구독자 ${(s / 10000).toStringAsFixed(s >= 100000 ? 0 : 1)}만';
  return '구독자 ${commas(s)}';
}

// ---- 테마 코스 ----
class Course {
  final String id, bold, light; // 이름: 굵은 앞말 + 가는 뒷말
  final List<Place> stops;
  Course(this.id, this.bold, this.light, this.stops);
  String get name => '$bold$light';
  double get length {
    var m = 0.0;
    for (var i = 1; i < stops.length; i++) {
      m += meters(stops[i - 1].point, stops[i].point);
    }
    return m;
  }

  // 직선 거리로 어림한 이동 시간
  String get trip {
    final m = length;
    int r5(double x) => math.max(5, (x / 5).ceil() * 5);
    return m <= 2500 ? '도보 약 ${r5(m / 70)}분' : '차로 약 ${r5(m / 350)}분';
  }
}

// 테마에 맞는 집들로 3~4곳 코스: 맛집에서 시작해 카페·맛집을 번갈아 가까운 집으로 잇는다
Course? makeCourse(String id, String bold, String light, Iterable<Place> theme, {int size = 4, double within = 2500}) {
  final ps = theme.toList();
  if (ps.length < 3) return null;
  final anchor = ps.firstWhere((p) => p.kind == 'food', orElse: () => ps.first);
  final cand = ps.where((p) => !identical(p, anchor) && meters(anchor.point, p.point) <= within).toList();
  final out = [anchor];
  var want = 'cafe';
  while (out.length < size && cand.isNotEmpty) {
    final last = out.last.point;
    cand.sort((a, b) => meters(last, a.point).compareTo(meters(last, b.point)));
    final i = cand.indexWhere((p) => p.kind == want);
    out.add(cand.removeAt(i >= 0 ? i : 0));
    want = out.last.kind == 'food' ? 'cafe' : 'food';
  }
  return out.length >= 3 ? Course(id, bold, light, out) : null;
}

// 동네 테마 코스 (유명인·방송 이름은 코스 이름에 쓰지 않는다)
List<Course> coursesOf(SongdoData d) {
  final top = d.places.where((p) => p.top).toList();
  final cook = top.where((p) => p.tv.any(kCookShows.contains)).toList();
  final tv = top.where((p) => p.tv.isNotEmpty).toList();
  final out = <Course?>[
    makeCourse('yt', '먹방 유튜버 ', '코스', ytRank(d).where((p) => ytCount(p) >= 2)),
    makeCourse('cook', '요리 경연 방송 ', '코스', cook),
    if (tv.length > cook.length) makeCourse('tv', '방송 맛집 ', '코스', tv),
    makeCourse('view', '뷰 맛집 ', '코스', top.where((p) => p.view)),
    makeCourse('big', '대형 카페 ', '투어', top.where((p) => p.kind == 'cafe' && p.big)),
    makeCourse('rise', '새로 뜨는 집 ', '코스', d.places.where((p) => p.rise)),
    makeCourse('pop', '인기 맛집 ', '하루 코스', popRank(d)),
  ];
  return out.whereType<Course>().toList();
}

// ---- 가는 선 아이콘 (시안의 선 굵기 1.4) ----
class LineIcon extends StatelessWidget {
  final String name; // home video map kok search pin play wheel
  final double size;
  final Color color;
  const LineIcon(this.name, {super.key, this.size = 22, this.color = kInk});
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _LinePainter(name, color));
}

class _LinePainter extends CustomPainter {
  final String name;
  final Color color;
  _LinePainter(this.name, this.color);
  @override
  void paint(Canvas c, Size s) {
    final k = s.width / 24;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (name == 'pin' ? 1.6 : 1.4) * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    Offset o(double x, double y) => Offset(x * k, y * k);
    ui.Path pin() => ui.Path()
      ..moveTo(12 * k, 21 * k)
      ..cubicTo(12 * k, 21 * k, 5 * k, 14.8 * k, 5 * k, 9.5 * k)
      ..arcToPoint(o(19, 9.5), radius: Radius.circular(7 * k))
      ..cubicTo(19 * k, 14.8 * k, 12 * k, 21 * k, 12 * k, 21 * k)
      ..close();
    switch (name) {
      case 'home':
        c.drawPath(
            ui.Path()
              ..moveTo(4 * k, 10.5 * k)
              ..lineTo(12 * k, 4 * k)
              ..lineTo(20 * k, 10.5 * k)
              ..lineTo(20 * k, 20 * k)
              ..lineTo(15 * k, 20 * k)
              ..lineTo(15 * k, 15 * k)
              ..lineTo(9 * k, 15 * k)
              ..lineTo(9 * k, 20 * k)
              ..lineTo(4 * k, 20 * k)
              ..close(),
            p);
      case 'video':
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(6 * k, 3 * k, 12 * k, 18 * k), Radius.circular(2.5 * k)), p);
        c.drawPath(
            ui.Path()
              ..moveTo(10.5 * k, 9.5 * k)
              ..lineTo(10.5 * k, 14.5 * k)
              ..lineTo(14.5 * k, 12 * k)
              ..close(),
            p);
      case 'map':
        c.drawPath(
            ui.Path()
              ..moveTo(3.5 * k, 6.5 * k)
              ..lineTo(9 * k, 4.5 * k)
              ..lineTo(15 * k, 6.5 * k)
              ..lineTo(20.5 * k, 4.5 * k)
              ..lineTo(20.5 * k, 17.5 * k)
              ..lineTo(15 * k, 19.5 * k)
              ..lineTo(9 * k, 17.5 * k)
              ..lineTo(3.5 * k, 19.5 * k)
              ..close(),
            p);
        c.drawLine(o(9, 4.5), o(9, 17.5), p);
        c.drawLine(o(15, 6.5), o(15, 19.5), p);
      case 'kok':
        c.drawPath(pin(), p);
        c.drawPath(
            ui.Path()
              ..moveTo(9.5 * k, 9.5 * k)
              ..lineTo(11.3 * k, 11.3 * k)
              ..lineTo(14.7 * k, 7.9 * k),
            p);
      case 'search':
        c.drawCircle(o(11, 11), 6.5 * k, p);
        c.drawLine(o(16, 16), o(20.5, 20.5), p);
      case 'pin':
        c.drawPath(pin(), p);
        c.drawCircle(o(12, 9.5), 2.5 * k, p);
      case 'play':
        c.drawPath(
            ui.Path()
              ..moveTo(8 * k, 5.5 * k)
              ..lineTo(8 * k, 18.5 * k)
              ..lineTo(18.5 * k, 12 * k)
              ..close(),
            Paint()..color = color);
      case 'wheel': // 룰렛: 원판 + 칸 + 위쪽 바늘
        c.drawCircle(o(12, 13.2), 8.3 * k, p);
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3 + math.pi / 6;
          c.drawLine(o(12, 13.2), o(12 + 8.3 * math.cos(a), 13.2 + 8.3 * math.sin(a)), p);
        }
        c.drawCircle(o(12, 13.2), 2.2 * k, Paint()..color = color);
        c.drawPath(
            ui.Path()
              ..moveTo(9.6 * k, 1.8 * k)
              ..lineTo(14.4 * k, 1.8 * k)
              ..lineTo(12 * k, 5.4 * k)
              ..close(),
            Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter o) => o.name != name || o.color != color;
}

// hqdefault(4:3)에는 16:9 영상 위아래로 검은 띠가 있어서, 띠를 빼고 영상 부분만 꽉 차게 자른다
Widget _hqCrop(String id, Widget fb) => LayoutBuilder(builder: (_, c) {
      final s = math.max(c.maxWidth / 480, c.maxHeight / 270);
      return ClipRect(
        child: OverflowBox(
          minWidth: 480 * s,
          maxWidth: 480 * s,
          minHeight: 360 * s,
          maxHeight: 360 * s,
          child: Image.network(
            'https://i.ytimg.com/vi/$id/hqdefault.jpg',
            fit: BoxFit.fill,
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            errorBuilder: (_, __, ___) => fb,
          ),
        ),
      );
    });

// 유튜브 큰 사진: 고화질(maxres)이 있다고 확인된 영상은 그것으로, 아니면 띠를 자른 hqdefault
Widget ytWide(Video v, {Widget? fallback}) {
  final fb = fallback ?? Container(color: const Color(0xFFE9E9EC));
  if (!v.hd) return _hqCrop(v.id, fb);
  return Image.network(
    'https://i.ytimg.com/vi/${v.id}/maxresdefault.jpg',
    fit: BoxFit.cover,
    width: double.infinity,
    height: double.infinity,
    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
    errorBuilder: (_, __, ___) => _hqCrop(v.id, fb),
  );
}

Widget ytSmall(Place p, double size, {double r = 8}) => ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: SizedBox(
        width: size,
        height: size,
        child: p.vids.isEmpty
            ? kindFill(p.kind, size * 0.5)
            : Image.network(
                'https://i.ytimg.com/vi/${p.vids.first.id}/mqdefault.jpg',
                fit: BoxFit.cover,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                errorBuilder: (_, __, ___) => kindFill(p.kind, size * 0.5),
              ),
      ),
    );

// 시안의 작은 테두리 알약
class _Pill extends StatelessWidget {
  final String text;
  const _Pill(this.text);
  @override
  Widget build(BuildContext context) => Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), border: Border.all(color: kPillLine, width: 1)),
        child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF44444C))),
      );
}

// 작은 고르기 알약 (룰렛)
class _SegChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _SegChip({required this.label, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? kInk : Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: on ? kInk : kPillLine, width: 1),
            ),
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? Colors.white : kInk)),
          ),
        ),
      );
}

// 제목: 굵은 앞말 + 가는 뒷말 (시안)
Widget mixTitle(String bold, String light, {double size = 15}) => Text.rich(TextSpan(children: [
      TextSpan(text: bold, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.3)),
      TextSpan(text: light, style: TextStyle(fontSize: size, fontWeight: FontWeight.w300, color: kInk, letterSpacing: -0.3)),
    ]));

// 콕플 머리말 (로고 + 지역 + 검색)
class KokHeader extends StatelessWidget {
  final Area area;
  final bool open;
  final VoidCallback onRegion, onSearch;
  final String? title; // 탭 이름 (홈은 로고)
  const KokHeader({super.key, required this.area, required this.open, required this.onRegion, required this.onSearch, this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(children: [
        if (title == null) ...[
          const Text('콕', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: kAccent, letterSpacing: -1, height: 1.1)),
          const Text('플', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w300, color: kInk, letterSpacing: -1, height: 1.1)),
          const SizedBox(width: 8),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('유튜브 맛집 지도', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: kSub)),
            ),
          ),
        ] else
          Expanded(child: Text(title!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.4))),
        // 지역 (누르면 지역 메뉴)
        Semantics(
          button: true,
          label: '지역 ${area.sido} ${area.name}',
          excludeSemantics: true,
          child: InkWell(
            onTap: onRegion,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 32,
              constraints: const BoxConstraints(maxWidth: 200),
              padding: const EdgeInsets.only(left: 12, right: 10),
              decoration: BoxDecoration(
                color: open ? kInk : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: open ? kInk : kPillLine, width: 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                LineIcon('pin', size: 14, color: open ? Colors.white : kInk),
                const SizedBox(width: 4),
                Flexible(
                  child: Text('${area.sido} · ${area.name}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: open ? Colors.white : kInk)),
                ),
                Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 16, color: open ? Colors.white : kInk),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(onPressed: onSearch, tooltip: '검색', icon: const LineIcon('search', size: 20)),
      ]),
    );
  }
}

// 섹션 제목 줄 (굵은 앞말 + 가는 뒷말 + 오른쪽 작은 링크)
Widget sectionHead(String bold, String light, {String? link, VoidCallback? onLink}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        mixTitle(bold, light),
        const Spacer(),
        if (link != null) GestureDetector(onTap: onLink, child: Text(link, style: const TextStyle(fontSize: 11, color: kSub))),
      ]),
    );

// ---- 홈 ----
class HomeView extends StatelessWidget {
  final SongdoData? data;
  final String? error;
  final Area area;
  final bool regionOpen;
  final Widget regionPanel;
  final VoidCallback onRegion, onSearch, onRetry, onRoulette;
  final ValueChanged<Place> onWhere; // 이 집 어디야 → 지도
  final ValueChanged<Chan> onChannel;
  final ValueChanged<Course> onCourse;
  final VoidCallback onAllChannels, onRankAll;
  const HomeView({
    super.key,
    required this.data,
    required this.error,
    required this.area,
    required this.regionOpen,
    required this.regionPanel,
    required this.onRegion,
    required this.onSearch,
    required this.onRetry,
    required this.onRoulette,
    required this.onWhere,
    required this.onChannel,
    required this.onCourse,
    required this.onAllChannels,
    required this.onRankAll,
  });

  @override
  Widget build(BuildContext context) {
    final d = data;
    return SafeArea(
      bottom: false,
      child: narrow(Column(children: [
        KokHeader(area: area, open: regionOpen, onRegion: onRegion, onSearch: onSearch),
        if (regionOpen) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: regionPanel),
        Expanded(
          child: d == null
              ? Center(
                  child: error == null
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton(onPressed: onRetry, child: const Text('자료를 받지 못했습니다 · 다시 불러오기')),
                )
              : ListView(padding: const EdgeInsets.only(bottom: 28), children: [
                  _hero(d),
                  const SizedBox(height: 18),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: RouletteBanner(onTap: onRoulette)),
                  _creators(d),
                  _tops(d),
                  _courses(d),
                ]),
        ),
      ])),
    );
  }

  Widget _hero(SongdoData d) {
    final p = todaysPlace(d);
    if (p == null) return const SizedBox();
    final v = p.vids.isEmpty ? null : p.vids.first;
    final n = ytCount(p);
    final o = openInfo(p);
    final tint = kindTint(p.kind);
    final plain = Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint, tint.withValues(alpha: 0.72)])),
      alignment: Alignment.center,
      child: KindGlyph(kind: p.kind, size: 64, bg: tint),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () {
            if (v == null) {
              onWhere(p);
            } else {
              openUrl('https://www.youtube.com/watch?v=${v.id}');
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 9.6,
              child: Stack(fit: StackFit.expand, children: [
                if (v == null) plain else ytWide(v, fallback: plain),
                if (n > 0)
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(11)),
                      child: Text('유튜버 $n명 방문', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: kAccent)),
                    ),
                  ),
                if (v != null)
                  Center(
                    child: Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), shape: BoxShape.circle),
                      child: const LineIcon('play', size: 20),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v == null ? '오늘의 추천' : '오늘의 영상', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: kAccent)),
              const SizedBox(height: 3),
              Text(p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.4, height: 1.3)),
              const SizedBox(height: 3),
              Text([if (v != null) v.channel, if (dongOf(p).isNotEmpty) dongOf(p), if (v == null && p.cat.isNotEmpty) p.cat, if (o != null) o.short].where((x) => x.isNotEmpty).join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w300, color: kSub)),
            ]),
          ),
          const SizedBox(width: 12),
          Semantics(
            button: true,
            label: '이 집 어디야',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => onWhere(p),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(17)),
                child: const Text('이 집 어디야', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _creators(SongdoData d) {
    final list = channelsOf(d).take(12).toList();
    if (list.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sectionHead('유튜버 ', '따라 먹기', link: '전체 보기', onLink: onAllChannels),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) => GestureDetector(onTap: () => onChannel(list[i]), child: ChanAvatar(list[i], ring: i == 0 ? kAccent : kPillLine)),
          ),
        ),
      ]),
    );
  }

  Widget _tops(SongdoData d) {
    final yt = ytRank(d);
    final list = (yt.isNotEmpty ? yt : popRank(d)).take(5).toList();
    if (list.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        yt.isNotEmpty
            ? sectionHead('유튜버가 ', '많이 찾은 집', link: '순위 전체', onLink: onRankAll)
            : sectionHead('지금 ', '인기 많은 집', link: '순위 전체', onLink: onRankAll),
        if (yt.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text('이 동네 유튜브 영상은 모으는 중이라, 구글 별점·리뷰 순으로 보여 드려요', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w300, color: kSub)),
          ),
        const SizedBox(height: 10),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          clipBehavior: Clip.antiAlias,
          decoration: kokCard(),
          child: Column(children: [
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, color: kHair),
              YtRow(place: list[i], rank: i + 1, onTap: () => onWhere(list[i])),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _courses(SongdoData d) {
    final list = coursesOf(d);
    if (list.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sectionHead('테마 ', '코스'),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => CourseCard(list[i], onTap: () => onCourse(list[i])),
          ),
        ),
      ]),
    );
  }
}

// 오늘 뭐 먹지? (홈 띠)
class RouletteBanner extends StatelessWidget {
  final VoidCallback onTap;
  const RouletteBanner({super.key, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '오늘 뭐 먹지?',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: kokCard(),
            child: Row(children: [
              const LineIcon('wheel', size: 30, color: kAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  mixTitle('오늘 ', '뭐 먹지?', size: 14),
                  const SizedBox(height: 2),
                  const Text('유튜버·방송 맛집 가운데 한 곳을 뽑아 드려요',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w300, color: kSub)),
                ]),
              ),
              const SizedBox(width: 8),
              Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(15)),
                child: const Text('돌리기', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ]),
          ),
        ),
      );
}

// 테마 코스 카드
class CourseCard extends StatelessWidget {
  final Course c;
  final VoidCallback onTap;
  const CourseCard(this.c, {super.key, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = c.stops;
    return Semantics(
      button: true,
      label: c.name,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 236,
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
          decoration: kokCard(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            mixTitle(c.bold, c.light, size: 14),
            const SizedBox(height: 2),
            Text('${s.length}곳 · ${c.trip}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w300, color: kSub)),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: Stack(children: [
                for (var i = 0; i < s.length; i++)
                  Positioned(
                    left: i * 30.0,
                    child: Container(
                      width: 40,
                      height: 40,
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: ClipOval(child: ytSmall(s[i], 36, r: 18)),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 9),
            Text([for (var i = 0; i < s.length; i++) '${i + 1} ${s[i].name}'].join('  '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kInk, height: 1.3)),
          ]),
        ),
      ),
    );
  }
}

// 지도 위 코스 띠 (코스 보는 중)
class CourseBar extends StatelessWidget {
  final Course course;
  final VoidCallback onList, onClose;
  const CourseBar({super.key, required this.course, required this.onList, required this.onClose});
  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.only(left: 14, right: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kAccent, width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10)],
        ),
        child: Row(children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onList,
              behavior: HitTestBehavior.opaque,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: course.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
                  TextSpan(text: '   ${course.stops.length}곳 · ${course.trip} · 순서 보기', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w300, color: kSub)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(onPressed: onClose, tooltip: '코스 닫기', visualDensity: VisualDensity.compact, icon: const Icon(Icons.close_rounded, size: 18, color: kInk)),
        ]),
      );
}

// ---- 오늘 뭐 먹지 룰렛 ----
class RouletteSheet extends StatefulWidget {
  final List<Place> Function(String kind, bool near) poolOf;
  final Future<bool> Function() locate; // 내 위치 확인 (되면 true)
  final bool located;
  final String areaName;
  final ValueChanged<Place> onWhere;
  const RouletteSheet({super.key, required this.poolOf, required this.locate, required this.located, required this.areaName, required this.onWhere});
  @override
  State<RouletteSheet> createState() => _RouletteSheetState();
}

class _RouletteSheetState extends State<RouletteSheet> with SingleTickerProviderStateMixin {
  late final AnimationController ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3800));
  final rnd = math.Random();
  String kind = 'all';
  late bool located = widget.located;
  late bool near = widget.located;
  bool busy = false;
  String note = '';
  List<Place> picks = [];
  int? win;
  double from = 0, to = 0;
  int tick = -1;

  @override
  void initState() {
    super.initState();
    deal();
    ctl.addListener(() {
      final i = under();
      if (i != tick) {
        tick = i;
        HapticFeedback.selectionClick();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  double get angle => from + (to - from) * Curves.easeOutQuart.transform(ctl.value);

  // 지금 바늘 아래 칸
  int under() {
    final n = picks.length;
    if (n == 0) return -1;
    final seg = 2 * math.pi / n;
    return (((-angle) % (2 * math.pi)) / seg).floor() % n;
  }

  void deal() {
    final pool = widget.poolOf(kind, near)..shuffle(rnd);
    picks = pool.take(8).toList();
    win = null;
    note = picks.length < 2 ? (near ? '내 주변 3km 안에 뽑을 집이 부족합니다' : '뽑을 집이 아직 부족합니다') : '';
  }

  void spin() {
    if (picks.length < 2 || ctl.isAnimating) return;
    final n = picks.length, w = rnd.nextInt(n), seg = 2 * math.pi / n;
    final target = -(w + 0.5 + (rnd.nextDouble() - 0.5) * 0.6) * seg;
    final delta = (target - to) % (2 * math.pi);
    setState(() {
      win = null;
      from = to;
      to = to + 2 * math.pi * 6 + delta;
    });
    ctl.forward(from: 0).then((_) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => win = w);
    });
  }

  Future<void> toggleNear() async {
    if (ctl.isAnimating || busy) return;
    if (!near && !located) {
      setState(() => busy = true);
      final ok = await widget.locate();
      if (!mounted) return;
      setState(() => busy = false);
      if (!ok) {
        setState(() => note = '내 위치를 확인하지 못했습니다. 위치 사용을 허용해 주세요.');
        return;
      }
      located = true;
    }
    setState(() {
      near = !near;
      deal();
    });
  }

  @override
  Widget build(BuildContext context) {
    final done = win != null && !ctl.isAnimating;
    final p = done ? picks[win!] : null;
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + MediaQuery.of(context).padding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              mixTitle('오늘 ', '뭐 먹지?', size: 18),
              const Spacer(),
              Text(near ? '내 주변 3km' : widget.areaName, style: const TextStyle(fontSize: 11, color: kSub)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              for (final k in const [('all', '전체'), ('food', '맛집'), ('cafe', '카페')]) ...[
                _SegChip(
                    label: k.$2,
                    on: kind == k.$1,
                    onTap: () {
                      if (ctl.isAnimating) return;
                      setState(() {
                        kind = k.$1;
                        deal();
                      });
                    }),
                const SizedBox(width: 6),
              ],
              const Spacer(),
              _SegChip(label: busy ? '위치 확인 중' : '내 주변', on: near, onTap: toggleNear),
            ]),
            const SizedBox(height: 18),
            if (picks.length < 2)
              Padding(padding: const EdgeInsets.symmetric(vertical: 70), child: Text(note, style: const TextStyle(fontSize: 13, color: kSub)))
            else
              SizedBox(
                width: 280,
                height: 292,
                child: Stack(alignment: Alignment.topCenter, children: [
                  Positioned(
                    top: 12,
                    child: SizedBox(width: 280, height: 280, child: CustomPaint(painter: _WheelPainter(picks, angle, done ? win : null))),
                  ),
                  Positioned(top: 0, child: CustomPaint(size: const Size(22, 20), painter: _PointerPainter())),
                  Positioned(
                    top: 118,
                    child: Semantics(
                      button: true,
                      label: '룰렛 돌리기',
                      excludeSemantics: true,
                      child: GestureDetector(
                        onTap: spin,
                        child: Container(
                          width: 68,
                          height: 68,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: kAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10)],
                          ),
                          child: Text(ctl.isAnimating ? '···' : (done ? '다시' : '돌리기'),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: p == null
                  ? SizedBox(
                      key: const ValueKey('none'),
                      height: 76,
                      child: Center(
                        child: Text(picks.length < 2 ? '' : (ctl.isAnimating ? '두근두근…' : (note.isNotEmpty ? note : '가운데를 눌러 돌려 보세요')),
                            style: const TextStyle(fontSize: 12.5, color: kSub)),
                      ),
                    )
                  : Container(
                      key: ValueKey(p.id),
                      height: 76,
                      padding: const EdgeInsets.all(12),
                      decoration: kokCard(),
                      child: Row(children: [
                        ytSmall(p, 52),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
                            const SizedBox(height: 2),
                            Text([if (ytCount(p) > 0) '유튜버 ${ytCount(p)}명', metaOf(p)].join(' · '),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w300, color: kSub)),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Semantics(
                          button: true,
                          label: '뽑은 집 어디야',
                          excludeSemantics: true,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              widget.onWhere(p);
                            },
                            child: Container(
                              height: 32,
                              padding: const EdgeInsets.symmetric(horizontal: 13),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(16)),
                              child: const Text('이 집 어디야', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                          ),
                        ),
                      ]),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final List<Place> picks;
  final double angle;
  final int? win;
  _WheelPainter(this.picks, this.angle, this.win);
  @override
  void paint(Canvas c, Size s) {
    final n = picks.length;
    if (n == 0) return;
    final r = s.width / 2;
    final seg = 2 * math.pi / n;
    final rect = Rect.fromCircle(center: Offset.zero, radius: r - 1);
    final line = Paint()
      ..color = kPillLine
      ..strokeWidth = 1;
    c.save();
    c.translate(r, r);
    c.rotate(angle);
    for (var i = 0; i < n; i++) {
      final start = -math.pi / 2 + i * seg;
      final on = win == i;
      c.drawArc(rect, start, seg, true, Paint()..color = on ? kAccent : (i.isEven ? Colors.white : kAccentTint));
      c.drawLine(Offset.zero, Offset(math.cos(start) * (r - 1), math.sin(start) * (r - 1)), line);
      final nm = picks[i].name;
      final label = nm.length > 7 ? '${nm.substring(0, 7)}…' : nm;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontFamily: 'Pretendard', fontSize: 12, fontWeight: FontWeight.w600, color: on ? Colors.white : kInk),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: r * 0.64);
      c.save();
      c.rotate(start + seg / 2);
      tp.paint(c, Offset(r * 0.3 + (r * 0.64 - tp.width) / 2, -tp.height / 2));
      c.restore();
    }
    c.restore();
    c.drawCircle(
        Offset(r, r),
        r - 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = kPillLine
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter o) => o.angle != angle || o.win != win || !identical(o.picks, picks);
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final path = ui.Path()
      ..moveTo(1, 1)
      ..lineTo(s.width - 1, 1)
      ..lineTo(s.width / 2, s.height - 1)
      ..close();
    c.drawPath(path, Paint()..color = kAccent);
    c.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}

// 유튜버 동그라미 + 이름 + 다녀간 수
// 사진은 유튜브 공식 연동(채널 정보)으로 받은 프로필 이미지 — 수집기가 30일 안에 새로 받고, 못 받은 채널은 이름 첫 글자
// (스토어 소개 사진·광고에는 유튜버 이미지를 쓰지 않는다)
class ChanAvatar extends StatelessWidget {
  final Chan c;
  final Color ring;
  final bool label;
  const ChanAvatar(this.c, {super.key, this.ring = kPillLine, this.label = true});
  static const _bgs = [Color(0xFF3D3D46), Color(0xFF5A4A3C), Color(0xFF46505A), Color(0xFF4F4652), Color(0xFF3F4D45)];
  @override
  Widget build(BuildContext context) {
    final bg = _bgs[c.name.hashCode.abs() % _bgs.length];
    final initial = Container(
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(c.initial, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
    );
    final circle = Container(
      width: 58,
      height: 58,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 1)),
      child: c.thumb.isEmpty
          ? initial
          : ClipOval(
              child: Image.network(
                c.thumb,
                fit: BoxFit.cover,
                width: 52,
                height: 52,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                errorBuilder: (_, __, ___) => initial,
              ),
            ),
    );
    if (!label) return circle;
    return SizedBox(
      width: 62,
      child: Column(children: [
        circle,
        const SizedBox(height: 6),
        Text(c.name,
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: kInk)),
        Text('${c.places.length}곳', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w300, color: kSub)),
      ]),
    );
  }
}

// 유튜버가 찾은 집 한 줄 (시안)
class YtRow extends StatelessWidget {
  final Place place;
  final int rank;
  final VoidCallback onTap;
  const YtRow({super.key, required this.place, required this.rank, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final n = ytCount(place);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          SizedBox(
            width: 18,
            child: Text('$rank', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: rank == 1 ? kAccent : kInk)),
          ),
          const SizedBox(width: 10),
          ytSmall(place, 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(place.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Text(metaOf(place), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w300, color: kSub)),
            ]),
          ),
          const SizedBox(width: 8),
          if (n > 0)
            _Pill('유튜버 $n명')
          else if (place.grate > 0)
            _Pill('★ ${place.grate.toStringAsFixed(1)}'),
        ]),
      ),
    );
  }
}

// ---- 영상 ----
class VideoView extends StatelessWidget {
  final SongdoData? data;
  final Area area;
  final bool regionOpen;
  final Widget regionPanel;
  final VoidCallback onRegion, onSearch;
  final ValueChanged<Place> onWhere;
  const VideoView({
    super.key,
    required this.data,
    required this.area,
    required this.regionOpen,
    required this.regionPanel,
    required this.onRegion,
    required this.onSearch,
    required this.onWhere,
  });
  @override
  Widget build(BuildContext context) {
    final d = data;
    final items = <(Video, Place)>[];
    final seen = <String>{};
    for (final p in d?.places.where((p) => p.top) ?? const <Place>[]) {
      for (final v in p.vids) {
        if (seen.add(v.id)) items.add((v, p));
      }
    }
    items.sort((a, b) => b.$1.date.compareTo(a.$1.date));
    return SafeArea(
      bottom: false,
      child: narrow(Column(children: [
        KokHeader(area: area, open: regionOpen, onRegion: onRegion, onSearch: onSearch, title: '영상'),
        if (regionOpen) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: regionPanel),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(d == null ? '' : '${area.name} 유튜브 영상은 모으는 중입니다.', style: const TextStyle(fontSize: 13, color: kSub)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 22),
                  itemBuilder: (_, i) {
                    final (v, p) = items[i];
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      GestureDetector(
                        onTap: () => openUrl('https://www.youtube.com/watch?v=${v.id}'),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Stack(fit: StackFit.expand, children: [
                              ytWide(v),
                              Center(
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), shape: BoxShape.circle),
                                  child: const LineIcon('play', size: 17),
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(v.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk, height: 1.35)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Expanded(
                          child: Text('${v.channel} · ${p.name}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w300, color: kSub)),
                        ),
                        GestureDetector(
                          onTap: () => onWhere(p),
                          child: const Text('이 집 어디야', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kAccent)),
                        ),
                      ]),
                    ]);
                  },
                ),
        ),
      ])),
    );
  }
}

// ---- 내 콕 (저장한 집) ----
class SavedView extends StatelessWidget {
  final List<Map<String, dynamic>> koks;
  final ValueChanged<Map<String, dynamic>> onOpen, onRemove;
  const SavedView({super.key, required this.koks, required this.onOpen, required this.onRemove});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: narrow(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Text('내 콕', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.4)),
        ),
        Expanded(
          child: koks.isEmpty
              ? const Center(
                  child: Text('마음에 드는 집을 「콕」 눌러 저장해 두세요.\n가게 화면 오른쪽 위에 있습니다.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kSub, height: 1.5)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: koks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, thickness: 1, color: kHair),
                  itemBuilder: (_, i) {
                    final k = koks[i];
                    final th = '${k['th'] ?? ''}';
                    final kd = '${k['k'] ?? 'food'}';
                    return InkWell(
                      onTap: () => onOpen(k),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 52,
                              height: 52,
                              child: th.isEmpty
                                  ? kindFill(kd, 26)
                                  : Image.network(th,
                                      fit: BoxFit.cover, webHtmlElementStrategy: WebHtmlElementStrategy.fallback, errorBuilder: (_, __, ___) => kindFill(kd, 26)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${k['n'] ?? ''}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
                              const SizedBox(height: 2),
                              Text('${k['an'] ?? ''} · ${k['c'] ?? ''}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w300, color: kSub)),
                            ]),
                          ),
                          IconButton(onPressed: () => onRemove(k), tooltip: '콕 빼기', icon: const Icon(Icons.close_rounded, size: 18, color: kSub)),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ])),
    );
  }
}

// ---- 아래 탭 ----
class KokNav extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onTap;
  const KokNav({super.key, required this.tab, required this.onTap});
  @override
  Widget build(BuildContext context) {
    const items = [('home', '홈'), ('video', '영상'), ('map', '지도'), ('kok', '내 콕')];
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kHair, width: 1))),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kHomeMax),
            child: SizedBox(
              height: 60,
              child: Row(children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: items[i].$2,
                      excludeSemantics: true,
                      child: InkWell(
                        onTap: () => onTap(i),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          LineIcon(items[i].$1, size: 22, color: tab == i ? kAccent : kSub),
                          const SizedBox(height: 3),
                          Text(items[i].$2,
                              style: TextStyle(fontSize: 10, fontWeight: tab == i ? FontWeight.w700 : FontWeight.w400, color: tab == i ? kAccent : kSub)),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- 가게 화면의 「콕」 단추 ----
class KokButton extends StatefulWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const KokButton({super.key, required this.on, required this.onChanged});
  @override
  State<KokButton> createState() => _KokButtonState();
}

class _KokButtonState extends State<KokButton> {
  late bool on = widget.on;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: on ? '콕 했어요' : '콕 하기',
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          setState(() => on = !on);
          widget.onChanged(on);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 32,
          padding: const EdgeInsets.only(left: 9, right: 12),
          decoration: BoxDecoration(
            color: on ? kAccent : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? kAccent : kPillLine, width: 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            LineIcon('kok', size: 16, color: on ? Colors.white : kInk),
            const SizedBox(width: 3),
            Text(on ? '콕 했어요' : '콕', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? Colors.white : kInk)),
          ]),
        ),
      ),
    );
  }
}

// ---- 시트 목록 (유튜버 한 명 · 유튜버 전체 · 순위 전체 · 코스 순서) ----
class SheetList extends StatelessWidget {
  final Widget head;
  final List<Widget> rows;
  const SheetList({super.key, required this.head, required this.rows});
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.72,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(2))),
            Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 8), child: head),
            Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 24), children: rows)),
          ]),
        ),
      ),
    );
  }
}
