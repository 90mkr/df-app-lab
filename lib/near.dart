part of 'main.dart';

// ---------------- 내 주변 (아래 가운데 단추) ----------------
// 위 반은 지도, 아래 반은 가까운 순 목록 (끌어올리면 전체) — 유튜버 맛집 + 수집·순위 맛집을 거리순으로
// 위치를 허락하지 않으면 고른 동네 가운데를 기준으로.

class NearPage extends StatefulWidget {
  final List<Place> Function() places; // 한 지도 가게 (전국)
  final LatLng? me;
  final Area area; // 위치가 없을 때 기준
  final Map<String, String> names; // 채널 id → 이름
  final bool Function(Place) isKok;
  final void Function(Place, bool) onKok;
  final ValueChanged<Place> onSeen; // 최근 본 집에 남기기
  final ValueChanged<LatLng> onMe; // 위치를 받으면 지도에도 알림
  final Place Function(Place) richer;
  final int recentDays;
  const NearPage({
    super.key,
    required this.places,
    required this.me,
    required this.area,
    required this.names,
    required this.isKok,
    required this.onKok,
    required this.onSeen,
    required this.onMe,
    required this.richer,
    required this.recentDays,
  });
  @override
  State<NearPage> createState() => _NearPageState();
}

class _NearPageState extends State<NearPage> {
  final map = MapController();
  final sheet = DraggableScrollableController();
  LatLng? at; // 거리를 재는 기준
  bool mine = false; // 기준이 내 위치인지
  bool busy = true;
  String sel = ''; // 고른 가게
  List<(Place, double)> list = const [];

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    sheet.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    var pos = widget.me;
    if (pos == null) {
      try {
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
          pos = await quietLocation();
        } else if (perm != LocationPermission.deniedForever && mounted) {
          if (await locationReason(context) == true) pos = await myLocation();
        }
      } catch (_) {}
    }
    if (!mounted) return;
    if (pos != null) widget.onMe(pos);
    setState(() {
      at = pos ?? widget.area.center;
      mine = pos != null;
      busy = false;
      _build();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
  }

  void _build() {
    final c = at;
    if (c == null) return;
    // 유튜버가 다녀간 집만 (거리순)
    final all = [
      for (final p in widget.places())
        if (p.vids.isNotEmpty) (p, meters(c, p.point)),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    final close = all.where((x) => x.$2 <= 5000).take(60).toList();
    list = close.length >= 10 ? close : all.take(30).toList();
  }

  // 위 반 지도에 기준점과 가까운 집들이 다 들어오게
  void _fit() {
    final c = at;
    if (c == null || list.isEmpty) return;
    try {
      final pts = [c, for (final x in list.take(12)) x.$1.point];
      final h = MediaQuery.of(context).size.height;
      final cam = CameraFit.coordinates(coordinates: pts, padding: EdgeInsets.fromLTRB(40, 110, 40, h * 0.5 + 30), maxZoom: 16).fit(map.camera);
      map.move(cam.center, cam.zoom);
    } catch (_) {}
  }

  void open(Place p0) {
    final p = widget.richer(p0);
    setState(() => sel = p.id);
    widget.onSeen(p);
    try {
      final h = MediaQuery.of(context).size.height;
      final z = math.max(map.camera.zoom, 15.0);
      map.move(shiftDown(p.point, z, h * 0.18), z);
    } catch (_) {}
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (_) => PlaceSheet(place: p, recentDays: widget.recentDays, kok: widget.isKok(p), onKok: (v) => widget.onKok(p, v), peek: 0.5),
    );
  }

  // 고민되면 룰렛: 내 주변 3km 안 유튜버 맛집에서
  void roulette() {
    final c = at;
    List<Place> pool(String kind, bool near) {
      final src = [
        for (final (p, d) in list)
          if (d <= 3000 && p.vids.isNotEmpty && (kind == 'all' || p.kind == kind)) p
      ];
      if (src.length >= 2 || c == null) return src;
      // 3km 안이 모자라면 가까운 유튜버 맛집으로 채움
      return [for (final (p, _) in list) if (p.vids.isNotEmpty && (kind == 'all' || p.kind == kind)) p].take(10).toList();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (ctx) => RouletteSheet(
        poolOf: pool,
        locate: () async => mine,
        located: true,
        areaName: mine ? '내 주변 3km' : widget.area.name,
        onWhere: (p) {
          Navigator.pop(ctx);
          open(p);
        },
      ),
    );
  }

  Widget row(Place p, double d) {
    final yt = ytCount(p);
    final o = openInfo(p);
    final thumb = thumbOf(p);
    final on = sel == p.id;
    final chans = p.vids.map((v) => widget.names[v.cid] ?? v.channel).where((x) => x.isNotEmpty).toSet().take(2).join(', ');
    return InkWell(
      onTap: () => open(p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        color: on ? const Color(0xFFFFF7F4) : null,
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 92,
              height: 60,
              child: thumb.isEmpty
                  ? kindFill(p.kind, 30)
                  : Image.network(thumb, fit: BoxFit.cover, webHtmlElementStrategy: WebHtmlElementStrategy.fallback, errorBuilder: (_, __, ___) => kindFill(p.kind, 30)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.2)),
              const SizedBox(height: 3),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: distText(d), style: const TextStyle(fontWeight: FontWeight.w800, color: kInk)),
                  if (yt > 0) ...[
                    const TextSpan(text: '  ·  '),
                    TextSpan(text: '유튜버 $yt명', style: const TextStyle(fontWeight: FontWeight.w700, color: kPointText)),
                  ],
                  if (o != null) ...[
                    const TextSpan(text: '  ·  '),
                    TextSpan(text: o.short, style: TextStyle(fontWeight: FontWeight.w600, color: o.open ? kPointText : kGray)),
                  ],
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: kGray),
              ),
              const SizedBox(height: 2),
              Text([if (chans.isNotEmpty) chans, p.cat.split(' > ').last].where((x) => x.isNotEmpty).join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: kSub)),
            ]),
          ),
          const SizedBox(width: 8),
          NavPill(onTap: () => startNav(context, name: p.name, lat: p.lat, lng: p.lng)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final c = at;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(children: [
        // 위 반: 지도
        Positioned.fill(
          child: FlutterMap(
            mapController: map,
            options: MapOptions(
              initialCenter: c ?? widget.area.center,
              initialZoom: 14,
              minZoom: 6,
              maxZoom: 19,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'kr.designfeel.df_app_lab'),
              MarkerLayer(markers: [
                for (final (p, _) in list.reversed)
                  if (p.id != sel)
                    Marker(
                        key: ValueKey('n${p.id}'),
                        point: p.point,
                        width: IconMarker.boxOf(p).width,
                        height: IconMarker.boxOf(p).height,
                        alignment: Alignment.topCenter,
                        child: IconMarker(place: p, onTap: () => open(p))),
                for (final (p, _) in list)
                  if (p.id == sel)
                    Marker(
                      key: ValueKey('s${p.id}'),
                      point: p.point,
                      width: cardFullW(1),
                      height: cardImg(1) + 18,
                      alignment: Alignment.topCenter,
                      child: PlaceMarker(place: p, rank: 1, open: true, numbered: false, focus: true, onTap: () => open(p)),
                    ),
                if (c != null)
                  Marker(
                    key: const ValueKey('me'),
                    point: c,
                    width: 22,
                    height: 22,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6)]),
                      child: Container(decoration: BoxDecoration(color: mine ? kGps : kRegion, shape: BoxShape.circle)),
                    ),
                  ),
              ]),
            ],
          ),
        ),
        // 위쪽 머리줄: 뒤로 · 제목 · 고민되면 룰렛
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Container(
              padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
              decoration: _card(),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), tooltip: '뒤로', icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: kInk)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    mixTitle('내 ', '주변', size: 19),
                    Text(
                      busy ? '내 위치를 확인하는 중' : (mine ? '내 위치에서 가까운 순' : '위치를 쓰지 않아 「${widget.area.name}」 가운데 기준'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: kSub),
                    ),
                  ]),
                ),
                Semantics(
                  button: true,
                  label: '고민되면 룰렛',
                  onTap: list.isEmpty ? null : roulette,
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: list.isEmpty ? null : roulette,
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.only(left: 10, right: 12),
                      decoration: BoxDecoration(color: kAccentTint, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFFFC9B8), width: 1)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        LineIcon('wheel', size: 18, color: kPointText),
                        SizedBox(width: 5),
                        Text('고민되면 룰렛', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kPointText)),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        // 아래 반: 가까운 순 목록 (끌어올리면 전체)
        DraggableScrollableSheet(
          controller: sheet,
          initialChildSize: 0.5,
          minChildSize: 0.2,
          maxChildSize: 1.0,
          snap: true,
          snapSizes: const [0.5],
          builder: (_, scroll) => Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 20)],
            ),
            child: busy
                ? ListView(controller: scroll, children: const [
                    SizedBox(height: 60),
                    Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent))),
                  ])
                : ListView.builder(
                    controller: scroll,
                    padding: EdgeInsets.only(bottom: mq.padding.bottom + 20),
                    itemCount: list.length + 1,
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        final in3 = list.where((x) => x.$2 <= 3000).length;
                        return Column(children: [
                          Container(margin: const EdgeInsets.only(top: 8, bottom: 10), width: 36, height: 4, decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(2))),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                            child: Row(children: [
                              Expanded(
                                child: Text.rich(TextSpan(children: [
                                  const TextSpan(text: '가까운 ', style: TextStyle(fontWeight: FontWeight.w400)),
                                  const TextSpan(text: '유튜버 맛집', style: TextStyle(fontWeight: FontWeight.w800)),
                                  TextSpan(text: '  ${list.length}곳', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kSub)),
                                ]), style: const TextStyle(fontSize: 17, color: kInk, letterSpacing: -0.3)),
                              ),
                              if (in3 > 0) Text('3km 안 $in3곳', style: const TextStyle(fontSize: 12, color: kSub)),
                            ]),
                          ),
                          if (list.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 30),
                              child: Text('아직 근처에 모은 맛집이 없어요', style: TextStyle(fontSize: 13, color: kSub)),
                            ),
                        ]);
                      }
                      final (p, d) = list[i - 1];
                      return Column(children: [
                        if (i > 1) const Divider(height: 1, thickness: 1, color: kHair, indent: 20, endIndent: 20),
                        row(p, d),
                      ]);
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}
