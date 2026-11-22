part of 'main.dart';

// ---------------- 지역 검색 (지도 위 작은 단추 → 전국 시·도 → 시·군·구) ----------------
// 목록은 유튜버 따라 먹기 가게 주소에서 만든다 (가게가 있는 곳만, 가게 수와 함께).
// 별점·영업시간·순위까지 모은 동네(지금은 인천 일부)는 「자세히」 표시.

const kSidoOrder = ['서울', '경기', '인천', '부산', '대구', '광주·전남', '대전', '울산', '세종', '강원', '충북', '충남', '전북', '경북', '경남', '제주'];

class RegionSpot {
  final String sido, city; // 시·도(짧은 이름), 시·군·구 (안양시 만안구 → 안양시)
  final List<LatLng> pts = [];
  Area? detail; // 자세한 자료가 있는 동네
  RegionSpot(this.sido, this.city);
  int get n => pts.length;
  String get label => city.isEmpty ? sido : city;

  // 가게들이 모인 범위 (멀리 떨어진 몇 곳은 빼고 가운데 90%만)
  List<LatLng> get core {
    if (pts.length < 6) return pts;
    final la = [for (final p in pts) p.latitude]..sort();
    final ln = [for (final p in pts) p.longitude]..sort();
    final i0 = (pts.length * 0.05).floor(), i1 = (pts.length * 0.95).ceil() - 1;
    return [LatLng(la[i0], ln[i0]), LatLng(la[i1], ln[i1])];
  }
}

class RegionIndex {
  final List<String> sidos; // 순서대로
  final Map<String, List<RegionSpot>> bySido;
  final Map<String, RegionSpot> whole; // 시·도 전체
  RegionIndex(this.sidos, this.bySido, this.whole);

  static String cityOf(String gu) {
    final w = gu.split(' ').where((x) => x.isNotEmpty).toList();
    if (w.isEmpty) return '';
    // 「수원시 영통구」처럼 시 아래 구가 있으면 시로 묶는다 (서울 강남구 등은 그대로)
    return (w.length >= 2 && w.first.endsWith('시')) ? w.first : w.first;
  }

  factory RegionIndex.from(Iterable<Place> places, List<Area> ready) {
    final spots = <String, RegionSpot>{};
    final whole = <String, RegionSpot>{};
    for (final p in places) {
      final s = sidoShort(p.sido);
      if (s.isEmpty) continue;
      final c = cityOf(p.gu);
      (whole[s] ??= RegionSpot(s, '')).pts.add(p.point);
      if (c.isEmpty) continue;
      (spots['$s|$c'] ??= RegionSpot(s, c)).pts.add(p.point);
    }
    // 자세한 동네: 그 동네 범위 안 가게가 가장 많은 시·군·구에 붙인다
    for (final a in ready) {
      final cnt = <String, int>{};
      for (final p in places) {
        if (!a.contains(p.point)) continue;
        final k = '${sidoShort(p.sido)}|${cityOf(p.gu)}';
        cnt[k] = (cnt[k] ?? 0) + 1;
      }
      if (cnt.isEmpty) continue;
      final top = (cnt.entries.toList()..sort((x, y) => y.value.compareTo(x.value))).first.key;
      spots[top]?.detail ??= a;
    }
    final by = <String, List<RegionSpot>>{};
    for (final sp in spots.values) {
      (by[sp.sido] ??= []).add(sp);
    }
    for (final l in by.values) {
      l.sort((a, b) => a.city.compareTo(b.city));
    }
    final order = [
      for (final s in kSidoOrder)
        if (whole.containsKey(s)) s,
      for (final s in whole.keys)
        if (!kSidoOrder.contains(s)) s,
    ];
    return RegionIndex(order, by, whole);
  }

  bool hasDetail(String sido) => (bySido[sido] ?? const []).any((r) => r.detail != null);
}

// 고른 결과: 지역 하나 · 내 위치 · 전국
class RegionPick {
  final RegionSpot? spot;
  final bool me, all;
  const RegionPick({this.spot, this.me = false, this.all = false});
}

class RegionSearchSheet extends StatefulWidget {
  final RegionIndex index;
  final String current; // 지금 지도 가운데 시·도
  const RegionSearchSheet({super.key, required this.index, this.current = ''});
  @override
  State<RegionSearchSheet> createState() => _RegionSearchSheetState();
}

class _RegionSearchSheetState extends State<RegionSearchSheet> {
  late String sido = widget.index.sidos.contains(widget.current) ? widget.current : (widget.index.sidos.isEmpty ? '' : widget.index.sidos.first);
  final q = TextEditingController();
  String query = '';

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  Widget detailTag() => Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: kAccentTint, borderRadius: BorderRadius.circular(6)),
        child: const Text('자세히', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: kPointText, height: 1.3)),
      );

  Widget spotBtn(RegionSpot r, {bool withSido = false}) => Semantics(
        button: true,
        label: '${withSido ? '${r.sido} ' : ''}${r.label} ${r.n}곳${r.detail != null ? ', 자세한 정보 있음' : ''}',
        onTap: () => Navigator.pop(context, RegionPick(spot: r)),
        excludeSemantics: true,
        child: InkWell(
          onTap: () => Navigator.pop(context, RegionPick(spot: r)),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(11, 9, 8, 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: r.detail != null ? const Color(0xFFFFC9B8) : kLine, width: 1),
            ),
            child: Row(children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    if (withSido) TextSpan(text: '${r.sido} ', style: const TextStyle(fontWeight: FontWeight.w400, color: kSub)),
                    TextSpan(text: r.label),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kInk, height: 1.2),
                ),
              ),
              if (r.detail != null) detailTag(),
              const SizedBox(width: 5),
              Text('${r.n}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: kSub)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final idx = widget.index;
    final all = [for (final s in idx.sidos) ...?idx.bySido[s]];
    final hits = query.isEmpty ? const <RegionSpot>[] : all.where((r) => r.city.contains(query) || r.sido.contains(query)).toList();
    final list = idx.bySido[sido] ?? const <RegionSpot>[];
    Widget quick(String label, IconData icon, VoidCallback onTap) => Semantics(
          button: true,
          label: label,
          onTap: onTap,
          excludeSemantics: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(17),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(17), border: Border.all(color: kPillLine, width: 1)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 16, color: kInk),
                const SizedBox(width: 5),
                Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kInk)),
              ]),
            ),
          ),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kHomeMax),
          child: Container(
            height: math.min(mq.size.height * 0.82, mq.size.height - mq.viewInsets.bottom - mq.padding.top - 10),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(margin: const EdgeInsets.only(top: 8), width: 36, height: 4, decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(2)))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 8, 2),
                child: Row(children: [
                  Expanded(child: mixTitle('지역 ', '검색', size: 19)),
                  IconButton(onPressed: () => Navigator.pop(context), tooltip: '닫기', icon: const Icon(Icons.close_rounded, size: 24, color: kInk)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: TextField(
                  controller: q,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 14.5, color: kInk),
                  decoration: InputDecoration(
                    hintText: '시·군·구 이름 (예: 강남, 해운대, 수원)',
                    hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFA5A9B2)),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: kSub),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF5F5F7),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) => setState(() => query = v.trim()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(children: [
                  quick('내 위치 주변', Icons.my_location_rounded, () => Navigator.pop(context, const RegionPick(me: true))),
                  const SizedBox(width: 8),
                  quick('전국 보기', Icons.public_rounded, () => Navigator.pop(context, const RegionPick(all: true))),
                ]),
              ),
              const Divider(height: 1, thickness: 1, color: kHair),
              Expanded(
                child: query.isNotEmpty
                    ? (hits.isEmpty
                        ? const Center(child: Text('그 이름의 지역에는 아직 유튜버 맛집이 없어요', style: TextStyle(fontSize: 13, color: kSub)))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                            itemCount: hits.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => spotBtn(hits[i], withSido: true),
                          ))
                    : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        // 왼쪽: 시·도 (붙은 네모 칸)
                        Container(
                          width: 104,
                          color: const Color(0xFFF7F7F9),
                          child: ListView(padding: EdgeInsets.zero, children: [
                            for (final s in idx.sidos)
                              Semantics(
                                button: true,
                                selected: s == sido,
                                label: '$s ${idx.whole[s]?.n ?? 0}곳',
                                onTap: () => setState(() => sido = s),
                                excludeSemantics: true,
                                child: GestureDetector(
                                  onTap: () => setState(() => sido = s),
                                  child: Container(
                                    height: 50,
                                    padding: const EdgeInsets.only(left: 16, right: 8),
                                    decoration: BoxDecoration(
                                      color: s == sido ? Colors.white : Colors.transparent,
                                      border: const Border(bottom: BorderSide(color: kHair)),
                                    ),
                                    child: Row(children: [
                                      if (s == sido) Container(width: 3, height: 18, margin: const EdgeInsets.only(right: 8), color: kAccent),
                                      Expanded(
                                        child: Text(s,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 14, fontWeight: s == sido ? FontWeight.w800 : FontWeight.w500, color: s == sido ? kInk : const Color(0xFF4A4F59))),
                                      ),
                                      if (idx.hasDetail(s)) Container(width: 6, height: 6, decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle)),
                                    ]),
                                  ),
                                ),
                              ),
                          ]),
                        ),
                        // 오른쪽: 시·군·구
                        Expanded(
                          child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 16, 24), children: [
                            if (idx.whole[sido] != null) ...[
                              spotBtn(RegionSpot(sido, '')..pts.addAll(idx.whole[sido]!.pts)),
                              const SizedBox(height: 10),
                            ],
                            if (idx.hasDetail(sido))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10, left: 2),
                                child: Row(children: [
                                  detailTag(),
                                  const SizedBox(width: 6),
                                  const Expanded(child: Text('별점·영업시간·화제 순위까지 있는 동네', style: TextStyle(fontSize: 11.5, color: kSub))),
                                ]),
                              ),
                            LayoutBuilder(builder: (_, c) {
                              final w = (c.maxWidth - 8) / 2;
                              return Wrap(spacing: 8, runSpacing: 8, children: [for (final r in list) SizedBox(width: w, child: spotBtn(r))]);
                            }),
                          ]),
                        ),
                      ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// 위치를 처음 물을 때: 왜 쓰는지 먼저 알린다 (휴대폰 허락 창은 그다음)
Future<bool?> locationReason(BuildContext context) => showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (ctx) => Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kHomeMax),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(22, 22, 22, 12 + MediaQuery.of(ctx).padding.bottom),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    mixTitle('내 주변 ', '유튜버 맛집부터', size: 19),
                    const SizedBox(height: 8),
                    const Text('지금 계신 곳 가까이에 있는 유튜버 맛집을\n먼저 보여 드리려고 위치를 써요.', style: TextStyle(fontSize: 14, color: kInk, height: 1.45)),
                  ]),
                ),
                const SizedBox(width: 10),
                Image.asset(kIntroMark, height: 62, filterQuality: FilterQuality.medium),
              ]),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                decoration: BoxDecoration(color: const Color(0xFFF6F6F8), borderRadius: BorderRadius.circular(12)),
                child: const Text('위치는 휴대폰 안에서만 쓰고, 콕플로 보내거나 저장하지 않아요.\n허용하지 않아도 지도는 전국으로 볼 수 있어요.',
                    style: TextStyle(fontSize: 12.5, color: kSub, height: 1.45)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(backgroundColor: kAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: const Text('위치 허용하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(foregroundColor: kSub, minimumSize: const Size(0, 44)),
                  child: const Text('나중에', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
