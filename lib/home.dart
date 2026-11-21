part of 'main.dart';

// ---------------- 콕플 시안: 홈 · 영상 · 내 콕 · 아래 탭 ----------------

const kAccent = Color(0xFFFF4B2B); // 콕플 대표색 (시안)
const kSub = Color(0xFF6B6B75); // 보조 글색 (시안)
const kHair = Color(0xFFECECF0); // 가는 구분선
const kPillLine = Color(0xFFDCDCE2);

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

// 오늘의 영상: 유튜버가 많이 찾은 집 가운데 날마다 돌아가며
Place? todaysPlace(SongdoData d) {
  final l = ytRank(d).take(7).toList();
  if (l.isEmpty) return null;
  final t = nowKst();
  final day = t.difference(DateTime(t.year)).inDays;
  return l[day % l.length];
}

String metaOf(Place p) {
  final o = openInfo(p);
  return [if (p.dong.isNotEmpty) p.dong, if (p.cat.isNotEmpty) p.cat, if (o != null) o.short].join(' · ');
}

String subsText(int s) {
  if (s <= 0) return '';
  if (s >= 10000) return '구독자 ${(s / 10000).toStringAsFixed(s >= 100000 ? 0 : 1)}만';
  return '구독자 ${commas(s)}';
}

// ---- 가는 선 아이콘 (시안의 선 굵기 1.4) ----
class LineIcon extends StatelessWidget {
  final String name; // home video map kok search pin play
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
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter o) => o.name != name || o.color != color;
}

// 유튜브 큰 사진 (4:3 사진의 위아래 검은 띠를 잘라 16:9로)
Widget ytWide(String id, {Widget? fallback}) => ClipRect(
      child: Transform.scale(
        scale: 1.34,
        child: Image.network(
          'https://i.ytimg.com/vi/$id/hqdefault.jpg',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
          errorBuilder: (_, __, ___) => fallback ?? Container(color: const Color(0xFFE9E9EC)),
        ),
      ),
    );

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
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('유튜브 맛집 지도', style: TextStyle(fontSize: 11, color: kSub)),
          ),
        ] else
          Text(title!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.4)),
        const Spacer(),
        // 지역 (누르면 지역 메뉴)
        InkWell(
          onTap: onRegion,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 32,
            padding: const EdgeInsets.only(left: 12, right: 10),
            decoration: BoxDecoration(
              color: open ? kInk : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: open ? kInk : kPillLine, width: 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              LineIcon('pin', size: 14, color: open ? Colors.white : kInk),
              const SizedBox(width: 4),
              Text('${area.sido} · ${area.name}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: open ? Colors.white : kInk)),
              Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 16, color: open ? Colors.white : kInk),
            ]),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(onPressed: onSearch, tooltip: '검색', icon: const LineIcon('search', size: 20)),
      ]),
    );
  }
}

// ---- 홈 ----
class HomeView extends StatelessWidget {
  final SongdoData? data;
  final String? error;
  final Area area;
  final bool regionOpen;
  final Widget regionPanel;
  final VoidCallback onRegion, onSearch, onRetry;
  final ValueChanged<Place> onWhere; // 이 집 어디야 → 지도
  final ValueChanged<Chan> onChannel;
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
    required this.onWhere,
    required this.onChannel,
    required this.onAllChannels,
    required this.onRankAll,
  });

  @override
  Widget build(BuildContext context) {
    final d = data;
    return SafeArea(
      bottom: false,
      child: Column(children: [
        KokHeader(area: area, open: regionOpen, onRegion: onRegion, onSearch: onSearch),
        if (regionOpen) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: regionPanel),
        Expanded(
          child: d == null
              ? Center(
                  child: error == null
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton(onPressed: onRetry, child: const Text('자료를 받지 못했습니다 · 다시 불러오기')),
                )
              : ListView(padding: const EdgeInsets.only(bottom: 20), children: [
                  _hero(d),
                  const SizedBox(height: 26),
                  _creators(d),
                  const SizedBox(height: 26),
                  _tops(d),
                ]),
        ),
      ]),
    );
  }

  Widget _hero(SongdoData d) {
    final p = todaysPlace(d);
    if (p == null) return const SizedBox();
    final v = p.vids.first;
    final n = ytCount(p);
    final o = openInfo(p);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => openUrl('https://www.youtube.com/watch?v=${v.id}'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 9.6,
              child: Stack(fit: StackFit.expand, children: [
                ytWide(v.id,
                    fallback: Container(
                      decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [Color(0xFF8A5A3C), Color(0xFFC98A52), Color(0xFFE8C08A)])),
                    )),
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
              const Text('오늘의 영상', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: kAccent)),
              const SizedBox(height: 3),
              Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.4, height: 1.3)),
              const SizedBox(height: 3),
              Text([v.channel, if (p.dong.isNotEmpty) p.dong, if (o != null) o.short].where((x) => x.isNotEmpty).join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w300, color: kSub)),
            ]),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => onWhere(p),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(17)),
              child: const Text('이 집 어디야', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _creators(SongdoData d) {
    final list = channelsOf(d).take(12).toList();
    if (list.isEmpty) return const SizedBox();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          mixTitle('유튜버 ', '따라 먹기'),
          const Spacer(),
          GestureDetector(onTap: onAllChannels, child: const Text('전체 보기', style: TextStyle(fontSize: 11, color: kSub))),
        ]),
      ),
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
    ]);
  }

  Widget _tops(SongdoData d) {
    final list = ytRank(d).take(5).toList();
    if (list.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          mixTitle('유튜버가 ', '많이 찾은 집'),
          const Spacer(),
          GestureDetector(onTap: onRankAll, child: const Text('순위 전체', style: TextStyle(fontSize: 11, color: kSub))),
        ]),
        const SizedBox(height: 10),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE4E4E9), width: 1),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)],
          ),
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
}

// 유튜버 동그란 사진 + 이름 + 다녀간 수
class ChanAvatar extends StatelessWidget {
  final Chan c;
  final Color ring;
  const ChanAvatar(this.c, {super.key, this.ring = kPillLine});
  static const _bgs = [Color(0xFF3D3D46), Color(0xFF5A4A3C), Color(0xFF46505A), Color(0xFF4F4652), Color(0xFF3F4D45)];
  @override
  Widget build(BuildContext context) {
    final bg = _bgs[c.name.hashCode.abs() % _bgs.length];
    final initial = Container(
      color: bg,
      alignment: Alignment.center,
      child: Text(c.initial, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
    );
    return SizedBox(
      width: 62,
      child: Column(children: [
        Container(
          width: 58,
          height: 58,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 1)),
          child: ClipOval(
            child: c.thumb.isEmpty
                ? initial
                : Image.network(c.thumb, fit: BoxFit.cover, webHtmlElementStrategy: WebHtmlElementStrategy.fallback, errorBuilder: (_, __, ___) => initial),
          ),
        ),
        const SizedBox(height: 6),
        Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: kInk)),
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
            child: Text('$rank', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: rank == 1 ? kAccent : kInk)),
          ),
          const SizedBox(width: 10),
          ytSmall(place, 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Text(metaOf(place), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w300, color: kSub)),
            ]),
          ),
          const SizedBox(width: 8),
          if (n > 0) _Pill('유튜버 $n명'),
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
      child: Column(children: [
        KokHeader(area: area, open: regionOpen, onRegion: onRegion, onSearch: onSearch, title: '영상'),
        if (regionOpen) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: regionPanel),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('아직 모인 영상이 없습니다.', style: TextStyle(fontSize: 13, color: kSub)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 20),
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
                              ytWide(v.id),
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
                      Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk, height: 1.35)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Expanded(
                          child: Text('${v.channel} · ${p.name}', maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w300, color: kSub)),
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
      ]),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                                  ? kindFill('${k['k'] ?? 'food'}', 26)
                                  : Image.network(th, fit: BoxFit.cover, webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                                      errorBuilder: (_, __, ___) => kindFill('${k['k'] ?? 'food'}', 26)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${k['n'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
                              const SizedBox(height: 2),
                              Text('${k['an'] ?? ''} · ${k['c'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w300, color: kSub)),
                            ]),
                          ),
                          IconButton(onPressed: () => onRemove(k), tooltip: '콕 빼기', icon: const Icon(Icons.close_rounded, size: 18, color: kSub)),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
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
        child: SizedBox(
          height: 58,
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
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
          ]),
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
    return InkWell(
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
    );
  }
}

// ---- 유튜버 한 명의 집 목록 / 유튜버 전체 / 유튜버 순위 전체 ----
class SheetList extends StatelessWidget {
  final Widget head;
  final List<Widget> rows;
  const SheetList({super.key, required this.head, required this.rows});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: [
        const SizedBox(height: 10),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 8), child: head),
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 24), children: rows)),
      ]),
    );
  }
}
