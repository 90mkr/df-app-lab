import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

const kBlue = Color(0xFF1F5BFF);
const kInk = Color(0xFF1B1D22);
const kGray = Color(0xFF7A808C);
const kLine = Color(0xFFE3E6EC);
const kDataUrl = 'https://90mkr.github.io/df-app-lab/data/songdo.json';
const kCenter = LatLng(37.3905, 126.6430);
const kTop = 10; // 종류별로 지도에 보이는 수

void main() => runApp(const DfApp());

class DfApp extends StatelessWidget {
  const DfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '송도 맛집',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Pretendard',
        colorScheme: ColorScheme.fromSeed(seedColor: kBlue, primary: kBlue, surface: Colors.white),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      home: const MapPage(),
    );
  }
}

// ---------------- 자료 ----------------

class Post {
  final String title, desc, url, date, by;
  Post(Map<String, dynamic> j)
      : title = j['t'] ?? '',
        desc = j['d'] ?? '',
        url = j['u'] ?? '',
        date = j['date'] ?? '',
        by = j['by'] ?? '';
  String get dateText => date.length == 8 ? '${date.substring(0, 4)}.${date.substring(4, 6)}.${date.substring(6)}' : date;
}

class Video {
  final String id, title, channel, date;
  Video(Map<String, dynamic> j)
      : id = j['id'] ?? '',
        title = j['t'] ?? '',
        channel = j['ch'] ?? '',
        date = j['date'] ?? '';
}

class Place {
  final String id, kind, name, cat, addr, tel, kakao, home, gurl;
  final double grate;
  final int greviews;
  final double lat, lng;
  final int blog, ads, score;
  final List<Post> posts;
  final List<Video> vids;
  Place(Map<String, dynamic> j)
      : id = '${j['id']}',
        kind = j['kind'] ?? 'food',
        name = j['name'] ?? '',
        cat = j['cat'] ?? '',
        addr = j['addr'] ?? '',
        tel = j['tel'] ?? '',
        kakao = j['kakao'] ?? '',
        home = j['home'] ?? '',
        gurl = j['gurl'] ?? '',
        grate = ((j['grate'] ?? 0) as num).toDouble(),
        greviews = j['greviews'] ?? 0,
        lat = (j['lat'] as num).toDouble(),
        lng = (j['lng'] as num).toDouble(),
        blog = j['blog'] ?? 0,
        ads = j['ads'] ?? 0,
        score = j['score'] ?? 0,
        posts = ((j['posts'] ?? []) as List).map((e) => Post(e)).toList(),
        vids = ((j['vids'] ?? []) as List).map((e) => Video(e)).toList();
  LatLng get point => LatLng(lat, lng);
}

class SongdoData {
  final String updated;
  final int recentDays;
  final List<Place> places;
  SongdoData(this.updated, this.recentDays, this.places);
}

Future<SongdoData> loadData() async {
  final base = kIsWeb ? Uri.base.resolve('data/songdo.json').toString() : kDataUrl;
  final res = await http.get(Uri.parse('$base?t=${DateTime.now().millisecondsSinceEpoch}'));
  if (res.statusCode != 200) throw Exception('자료를 아직 받지 못했습니다 (${res.statusCode})');
  final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  final list = ((j['places'] ?? []) as List).map((e) => Place(e)).toList();
  return SongdoData(j['updated'] ?? '', j['recent_days'] ?? 90, list);
}

Future<void> openUrl(String url) async {
  if (url.isEmpty) return;
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

// ---------------- 지도 화면 ----------------

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final map = MapController();
  SongdoData? data;
  String? error;
  String kind = 'food';
  String get kindLabel => kind == 'cafe' ? '카페' : '맛집';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final d = await loadData();
      setState(() => data = d);
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  List<Place> get visible {
    final d = data;
    if (d == null) return [];
    final list = d.places.where((p) => p.kind == kind && p.score > 0).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return list.take(kTop).toList();
  }

  void openPlace(Place p) {
    map.move(p.point, math.max(map.camera.zoom, 16));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (_) => PlaceSheet(place: p, recentDays: data?.recentDays ?? 90),
    );
  }

  void openRank() {
    final list = visible;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (ctx) => _Sheet(
        initial: 0.7,
        builder: (scroll) => ListView.separated(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          itemCount: list.length + 1,
          separatorBuilder: (_, i) => i == 0 ? const SizedBox(height: 6) : const Divider(height: 1, color: kLine),
          itemBuilder: (_, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '송도 $kindLabel ', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: kInk)),
                  TextSpan(text: '화제 순위', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kInk)),
                  TextSpan(text: '  상위 ${list.length}곳', style: const TextStyle(fontSize: 13, color: kGray)),
                ])),
              );
            }
            final p = list[i - 1];
            return InkWell(
              onTap: () {
                Navigator.pop(ctx);
                openPlace(p);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(children: [
                  SizedBox(
                    width: 30,
                    child: Text('$i', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: i <= 3 ? kBlue : kGray)),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: kInk)),
                      const SizedBox(height: 2),
                      Text('${p.cat}${p.greviews > 0 ? '  ·  ★${p.grate.toStringAsFixed(1)} (${p.greviews})' : ''}  ·  블로그 ${p.blog}',
                          style: const TextStyle(fontSize: 12, color: kGray)),
                    ]),
                  ),
                  ScoreTag(score: p.score),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = visible;
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: map,
          options: const MapOptions(initialCenter: kCenter, initialZoom: 14, minZoom: 11, maxZoom: 19),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'kr.designfeel.df_app_lab',
            ),
            MarkerLayer(
              markers: [
                for (var i = list.length - 1; i >= 0; i--)
                  Marker(
                    point: list[i].point,
                    width: i < 3 ? 178 : 154,
                    height: i < 3 ? 74 : 64,
                    alignment: Alignment.topCenter,
                    child: PlaceMarker(place: list[i], rank: i + 1, onTap: () => openPlace(list[i])),
                  ),
              ],
            ),
          ],
        ),
        // 위쪽 머리말
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Header(data: data, kindLabel: kindLabel, onRank: data == null ? null : openRank),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final k in const [['food', '맛집'], ['cafe', '카페']])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _Chip(label: k[1], on: kind == k[0], onTap: () => setState(() => kind = k[0])),
                    ),
                ]),
              ),
            ]),
          ),
        ),
        if (data == null)
          Center(
            child: Container(
              margin: const EdgeInsets.all(30),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              decoration: _card(),
              child: error == null
                  ? const Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('맛집 자료를 불러오는 중', style: TextStyle(fontSize: 14, color: kInk)),
                    ])
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('자료를 아직 받지 못했습니다', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kInk)),
                      const SizedBox(height: 4),
                      const Text('매일 새벽 자동으로 모읍니다.\n잠시 뒤 다시 시도해 주세요.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: kGray, height: 1.4)),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: const Text('다시 불러오기')),
                    ]),
            ),
          ),
        Positioned(
          right: 6,
          bottom: 4,
          child: GestureDetector(
            onTap: () => openUrl('https://www.openstreetmap.org/copyright'),
            child: const Text('© OpenStreetMap', style: TextStyle(fontSize: 10, color: kGray)),
          ),
        ),
      ]),
    );
  }
}

BoxDecoration _card({double r = 14}) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: kLine, width: 1),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, spreadRadius: 0)],
    );

class _Header extends StatelessWidget {
  final SongdoData? data;
  final String kindLabel;
  final VoidCallback? onRank;
  const _Header({required this.data, required this.kindLabel, required this.onRank});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      decoration: _card(),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text.rich(TextSpan(children: [
              TextSpan(text: '송도 ', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w400, color: kInk)),
              TextSpan(text: '맛집·카페 지도', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: kInk)),
            ])),
            const SizedBox(height: 2),
            Text(
              data == null ? '블로그·유튜브 화제 순' : '$kindLabel 화제 상위 $kTop곳  ·  ${data!.updated} 기준',
              style: const TextStyle(fontSize: 11.5, color: kGray),
            ),
          ]),
        ),
        TextButton(
          onPressed: onRank,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: kBlue,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('순위', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: on ? kInk : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? kInk : kLine, width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
        ),
        child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? Colors.white : kInk)),
      ),
    );
  }
}

String commas(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

class PlaceMarker extends StatelessWidget {
  final Place place;
  final int rank;
  final VoidCallback onTap;
  const PlaceMarker({super.key, required this.place, required this.rank, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final big = rank <= 3;
    final img = big ? 52.0 : 44.0;
    final thumb = place.vids.isNotEmpty ? 'https://i.ytimg.com/vi/${place.vids.first.id}/mqdefault.jpg' : '';
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: big ? kBlue : kLine, width: 1),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10)],
          ),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: SizedBox(
                width: img,
                height: img,
                child: thumb.isEmpty
                    ? Container(
                        color: const Color(0xFFF1F3F7),
                        alignment: Alignment.center,
                        child: Icon(place.kind == 'cafe' ? Icons.local_cafe_outlined : Icons.restaurant_outlined, size: img * 0.42, color: kGray),
                      )
                    : Image.network(
                        thumb,
                        fit: BoxFit.cover,
                        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                        errorBuilder: (_, __, ___) => Container(color: const Color(0xFFF1F3F7)),
                      ),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$rank ', style: TextStyle(fontSize: big ? 12 : 11, fontWeight: FontWeight.w700, color: big ? kBlue : kGray)),
                    TextSpan(text: place.name, style: TextStyle(fontSize: big ? 12 : 11, fontWeight: FontWeight.w700, color: kInk)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (place.greviews > 0)
                  Text.rich(TextSpan(children: [
                    const TextSpan(text: '★ ', style: TextStyle(fontSize: 10.5, color: Color(0xFFF5A623))),
                    TextSpan(text: place.grate.toStringAsFixed(1), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: kInk)),
                    TextSpan(text: ' · 리뷰 ${commas(place.greviews)}', style: const TextStyle(fontSize: 10, color: kGray)),
                  ]), maxLines: 1)
                else
                  Text(place.cat, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: kGray)),
              ]),
            ),
          ]),
        ),
        // 카드 아래 꼬리 (가게 위치를 가리킴)
        CustomPaint(size: const Size(12, 6), painter: _Tail(big ? kBlue : kLine)),
      ]),
    );
  }
}

class _Tail extends CustomPainter {
  final Color line;
  _Tail(this.line);
  @override
  void paint(Canvas c, Size s) {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(s.width / 2, s.height)
      ..lineTo(s.width, 0)
      ..close();
    c.drawPath(path, Paint()..color = Colors.white);
    c.drawLine(Offset(0, 0), Offset(s.width / 2, s.height), Paint()..color = line..strokeWidth = 1);
    c.drawLine(Offset(s.width, 0), Offset(s.width / 2, s.height), Paint()..color = line..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _Tail old) => old.line != line;
}

class ScoreTag extends StatelessWidget {
  final int score;
  const ScoreTag({super.key, required this.score});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: score >= 50 ? kBlue : kLine, width: 1),
      ),
      child: Text.rich(TextSpan(children: [
        const TextSpan(text: '화제 ', style: TextStyle(fontSize: 11, color: kGray)),
        TextSpan(text: '$score', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: score >= 50 ? kBlue : kInk)),
      ])),
    );
  }
}

// ---------------- 아래에서 올라오는 판 ----------------

class _Sheet extends StatelessWidget {
  final double initial;
  final Widget Function(ScrollController) builder;
  const _Sheet({required this.initial, required this.builder});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: initial,
      minChildSize: 0.25,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 20)],
        ),
        child: Column(children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(child: builder(scroll)),
        ]),
      ),
    );
  }
}

class PlaceSheet extends StatelessWidget {
  final Place place;
  final int recentDays;
  const PlaceSheet({super.key, required this.place, required this.recentDays});

  @override
  Widget build(BuildContext context) {
    final p = place;
    final naver = 'https://map.naver.com/p/search/${Uri.encodeComponent(p.name)}';
    return _Sheet(
      initial: 0.55,
      builder: (scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 30),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk, height: 1.25)),
                const SizedBox(height: 3),
                Text(p.cat, style: const TextStyle(fontSize: 12.5, color: kGray)),
              ]),
            ),
            ScoreTag(score: p.score),
          ]),
          const SizedBox(height: 10),
          if (p.greviews > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text.rich(TextSpan(children: [
                const TextSpan(text: '구글 별점 ', style: TextStyle(fontSize: 12.5, color: kGray)),
                TextSpan(text: p.grate.toStringAsFixed(1), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
                TextSpan(text: '   리뷰 ${p.greviews}개', style: const TextStyle(fontSize: 12.5, color: kGray)),
              ])),
            ),
          if (p.addr.isNotEmpty) Text(p.addr, style: const TextStyle(fontSize: 13, color: kInk, height: 1.4)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _Btn(label: '카카오맵', onTap: () => openUrl(p.kakao))),
            const SizedBox(width: 8),
            Expanded(child: _Btn(label: '네이버 지도', onTap: () => openUrl(naver))),
            if (p.home.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(child: _Btn(label: '가게 블로그', onTap: () => openUrl(p.home))),
            ],
            if (p.tel.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(child: _Btn(label: '전화', primary: true, onTap: () => openUrl('tel:${p.tel}'))),
            ],
          ]),
          const SizedBox(height: 22),
          if (p.vids.isNotEmpty) ...[
            const _Title(text: '유튜브 영상'),
            const SizedBox(height: 10),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: p.vids.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final v = p.vids[i];
                  return GestureDetector(
                    onTap: () => openUrl('https://www.youtube.com/watch?v=${v.id}'),
                    child: SizedBox(
                      width: 180,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network('https://i.ytimg.com/vi/${v.id}/mqdefault.jpg', width: 180, height: 101, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(width: 180, height: 101, color: kLine)),
                        ),
                        const SizedBox(height: 6),
                        Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kInk, height: 1.3)),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 22),
          ],
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _Title(text: '최근 $recentDays일 블로그 ${p.blog}건'),
            const SizedBox(width: 8),
            if (p.ads > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Text('광고 의심 ${p.ads}건 제외', style: const TextStyle(fontSize: 11.5, color: kGray)),
              ),
          ]),
          const SizedBox(height: 6),
          if (p.posts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('최근 올라온 블로그 글이 없습니다.', style: TextStyle(fontSize: 13, color: kGray)),
            ),
          for (final b in p.posts)
            InkWell(
              onTap: () => openUrl(b.url),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kLine, width: 1))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
                  const SizedBox(height: 3),
                  Text(b.desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Color(0xFF4A4F59), height: 1.4)),
                  const SizedBox(height: 4),
                  Text('${b.by}  ·  ${b.dateText}', style: const TextStyle(fontSize: 11, color: kGray)),
                ]),
              ),
            ),
          const SizedBox(height: 12),
          const Text('블로그 글은 제목과 앞부분만 보여 드리며, 누르면 원래 글로 이동합니다. 가게가 직접 쓴 글과 광고 의심 글은 점수에서 뺐습니다.', style: TextStyle(fontSize: 11, color: kGray)),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  final String text;
  const _Title({required this.text});
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kInk));
}

class _Btn extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;
  const _Btn({required this.label, required this.onTap, this.primary = false});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? kBlue : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: primary ? kBlue : kLine, width: 1),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary ? Colors.white : kInk)),
      ),
    );
  }
}
