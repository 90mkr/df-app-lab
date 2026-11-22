import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' show YoutubePlayer, YoutubePlayerController, YoutubePlayerParams;
import 'package:firebase_core/firebase_core.dart' as fc;
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

part 'home.dart';
part 'fb.dart';
part 'admin.dart';
part 'intro.dart';

const kPoint = kAccent; // 콕플 주색 (빨강주황): 단추·고른 탭·강조
const kPointText = Color(0xFFDC3519); // 작은 강조 글씨 (흰 바탕에서 또렷하게 한 톤 진하게)
const kGps = Color(0xFF1F5BFF); // 지도 위 내 위치 점만 파랑 (지도 앱 관례)
const kInk = Color(0xFF1B1D22);
const kGray = Color(0xFF7A808C);
const kLine = Color(0xFFE3E6EC);
const kDark = Color(0xFF262A31); // 검색 켜짐 등 진한 바탕
const kRegion = Color(0xFF34302E); // 지역 단추·고른 시·도·동네 바탕 (따뜻한 먹색)
const kDataBase = 'https://90mkr.github.io/df-app-lab/data/'; // 안드로이드 앱이 자료를 받아 오는 곳
const kTop = 20; // 종류별로 지도에 보이는 수

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  fbReady().then((ok) {
    if (ok) watchAuth();
  });
  await Future.wait([introWarmUp(), loadHeroSeen()]); // 시작 화면 그림·최근 본 추천 영상을 먼저 읽어 둔다
  runApp(const DfApp());
}

class DfApp extends StatelessWidget {
  const DfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '콕플',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const MaterialScrollBehavior().copyWith(dragDevices: ui.PointerDeviceKind.values.toSet()),
      theme: ThemeData(
        fontFamily: 'Pretendard',
        colorScheme: ColorScheme.fromSeed(seedColor: kPoint, primary: kPoint, surface: Colors.white),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      // 인트로가 앱 위에 잠깐 덮였다가 사라진다 (그 사이 아래에서 자료를 받는다). 상태 표시줄 글씨는 흰 화면에 맞게 진하게.
      // 휴대폰 글자 크기를 아주 크게 해도 화면이 깨지지 않게 1.3배까지만 키운다
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: KokIntro(
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
            child: child ?? const SizedBox(),
          ),
        ),
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
  final String id, title, channel, date, cid;
  final bool hd; // 고화질 표지(maxres)가 있다고 확인된 영상
  final bool short; // 세로 영상(쇼츠) — 표지를 자르지 않고 통째로
  Video(Map<String, dynamic> j)
      : id = j['id'] ?? '',
        title = j['t'] ?? '',
        channel = j['ch'] ?? '',
        date = j['date'] ?? '',
        cid = j['cid'] ?? '',
        hd = j['mx'] == 1,
        short = j['sh'] == 1,
        dur = ((j['dur'] ?? 0) as num).toInt();
  final int dur; // 영상 길이(초) — 따라가기 자료에만
}

class Place {
  final String id, kind, name, cat, addr, tel, kakao, home, gurl;
  final String dong; // 송도동 같은 동 이름
  final String insta; // 가게 인스타그램 계정 주소 (없으면 단추 숨김)
  final String cz; // 음식 종류 (카카오 분류 둘째 칸)
  final String model; // 「○○구 지정 모범음식점」 (공공데이터)
  final String mfood; // 모범음식점 자료의 주된 음식
  final String areaId; // 어느 동네 자료에서 왔는지
  final double grate;
  final int greviews;
  final double lat, lng;
  final int blog, ads, score;
  final List<Post> posts;
  final List<Video> vids;
  final List<List<int>> hours; // [여는 요일, 시각(hhmm), 닫는 요일, 시각] 요일 0=일, 닫는 시각 없으면 -1
  final List<String> week; // "월요일: 오전 11:00~오후 9:00" 같은 7줄
  final List<String> tv; // 출연한 방송 이름 (블로그 글로 확인)
  final bool big; // 대형 카페 (블로그 글로 확인)
  final bool view; // 뷰 맛집·오션뷰 카페 (블로그 글로 확인)
  final bool top; // 순위(종류별 20위) 안
  final bool rise; // 새로 뜨는 집 (최근 30일 글이 크게 늘어남)
  final int r30; // 최근 30일 블로그 글 수
  final double rr; // 그 전보다 몇 배
  final List<String> feat; // 편의 정보 (주차·애견 동반 등, 구글 기준)
  final String sido, gu; // 시·도, 시·군·구 (따라가기 자료)
  final Map<String, dynamic> raw; // 받은 그대로의 자료 (관리자가 고친 값을 덮어 다시 만들 때)
  Place(Map<String, dynamic> j, [this.areaId = ''])
      : raw = j,
        id = '${j['id']}',
        kind = j['kind'] ?? 'food',
        name = j['name'] ?? '',
        cat = j['cat'] ?? '',
        dong = j['dong'] ?? '',
        insta = j['insta'] ?? '',
        cz = j['cz'] ?? '',
        model = j['model'] ?? '',
        mfood = j['mfood'] ?? '',
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
        vids = ((j['vids'] ?? []) as List).map((e) => Video(e)).toList(),
        hours = ((j['hours'] ?? []) as List).map((e) => (e as List).map((x) => (x as num).toInt()).toList()).toList(),
        week = ((j['week'] ?? []) as List).map((e) => '$e').toList(),
        tv = ((j['tv'] ?? []) as List).map((e) => '$e').toList(),
        big = j['big'] == true,
        view = j['view'] == true,
        top = j['top'] != false,
        rise = j['rise'] == true,
        r30 = j['r30'] ?? 0,
        rr = ((j['rr'] ?? 0) as num).toDouble(),
        feat = ((j['feat'] ?? []) as List).map((e) => '$e').toList(),
        sido = j['s'] ?? '',
        gu = j['gu'] ?? '';
  LatLng get point => LatLng(lat, lng);
}

// ---------------- 영업시간 계산 (한국 시간 기준) ----------------

const kDays = ['일', '월', '화', '수', '목', '금', '토'];

class OpenInfo {
  final bool open;
  final String short, text;
  const OpenInfo(this.open, this.short, this.text);
}

DateTime nowKst() => DateTime.now().toUtc().add(const Duration(hours: 9));

String hm(int v) {
  if (v == 0) return '자정';
  return '${(v ~/ 100).toString().padLeft(2, '0')}:${(v % 100).toString().padLeft(2, '0')}';
}

OpenInfo? openInfo(Place p) {
  if (p.hours.isEmpty) return null;
  if (p.hours.any((h) => h[2] < 0)) return const OpenInfo(true, '24시간', '24시간 영업');
  final t = nowKst();
  final day = t.weekday % 7; // 0=일
  const week = 7 * 1440;
  final now = day * 1440 + t.hour * 60 + t.minute;
  int mins(int d, int v) => d * 1440 + (v ~/ 100) * 60 + v % 100;
  List<int>? next;
  int nextIn = week + 1;
  for (final h in p.hours) {
    final o = mins(h[0], h[1]);
    var c = mins(h[2], h[3]);
    if (c <= o) c += week;
    for (final n in [now, now + week]) {
      if (n >= o && n < c) {
        final left = c - n;
        return OpenInfo(true, left <= 60 ? '곧 마감' : '영업 중', '${left <= 60 ? '곧 마감' : '영업 중'} · ${hm(h[3])}까지');
      }
    }
    final until = (o - now) % week;
    if (until < nextIn) {
      nextIn = until;
      next = h;
    }
  }
  if (next == null) return null;
  if (next[0] == day && nextIn < 1440) return OpenInfo(false, '준비 중', '준비 중 · ${hm(next[1])} 시작');
  final when = (next[0] == (day + 1) % 7 && nextIn < 2 * 1440) ? '내일' : '${kDays[next[0]]}요일';
  return OpenInfo(false, '영업 종료', '영업 종료 · $when ${hm(next[1])} 시작');
}

double meters(LatLng a, LatLng b) {
  const r = 6371000.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(a.latitude * math.pi / 180) * math.cos(b.latitude * math.pi / 180) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

String distText(double m) => m < 1000 ? '${(m / 10).round() * 10}m' : '${(m / 1000).toStringAsFixed(1)}km';

// 내 위치 (거부·실패하면 null)
// 내 위치 (거리 표시용) — 한 번 알면 가게 화면·목록·내 콕에 거리가 붙는다
final myPos = ValueNotifier<LatLng?>(null);

// 이미 위치 사용을 허락받았을 때만 조용히 (묻는 창을 띄우지 않음)
Future<LatLng?> quietLocation() async {
  try {
    if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) return null;
    final perm = await Geolocator.checkPermission();
    if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) return null;
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 12)),
    );
    return LatLng(pos.latitude, pos.longitude);
  } catch (_) {
    return null;
  }
}

// 내 위치가 들어 있는 동네, 없으면 10km 안에서 가장 가까운 동네 (자료가 있는 동네만)
Area? nearArea(List<Area> all, LatLng? at) {
  if (at == null) return null;
  Area? best;
  var bd = 10000.0;
  for (final a in all) {
    final d = a.contains(at) ? 0.0 : meters(at, a.center);
    if (d < bd || (d == 0 && best != null && meters(at, a.center) < meters(at, best.center))) {
      bd = d;
      best = a;
    }
  }
  return best;
}

Future<LatLng?> myLocation() async {
  try {
    if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 12)),
    );
    return LatLng(pos.latitude, pos.longitude);
  } catch (_) {
    return null;
  }
}

// ---------------- 지역 (전국 확장용: 시·도 → 동네) ----------------

class Area {
  final String id, name, gu, sido, updated;
  final double lat, lng, zoom;
  final bool ready;
  final List<double>? bbox; // 서쪽 경도, 남쪽 위도, 동쪽 경도, 북쪽 위도
  final int count, food, cafe; // 수집할 때 미리 센 가게 수 (축소 화면 숫자 묶음용)
  final List<String> tour; // 동네 테마 이름 (굵은 앞말, 가는 뒷말) — 예: 송도 한 바퀴
  Area(Map<String, dynamic> j, this.sido)
      : id = j['id'] ?? '',
        name = j['name'] ?? '',
        gu = j['gu'] ?? '',
        updated = '${j['updated'] ?? ''}',
        lat = ((j['lat'] ?? 37.3905) as num).toDouble(),
        lng = ((j['lng'] ?? 126.6430) as num).toDouble(),
        zoom = ((j['zoom'] ?? 13) as num).toDouble(),
        ready = j['ready'] == true,
        bbox = j['bbox'] is List ? (j['bbox'] as List).map((e) => (e as num).toDouble()).toList() : null,
        count = (j['count'] ?? 0) as int,
        food = (j['food'] ?? 0) as int,
        cafe = (j['cafe'] ?? 0) as int,
        tour = ((j['tour'] ?? []) as List).map((e) => '$e').toList();
  LatLng get center => LatLng(lat, lng);
  List<double> get box => bbox ?? [lng - 0.05, lat - 0.04, lng + 0.05, lat + 0.04];
  bool contains(LatLng p) => p.longitude >= box[0] && p.longitude <= box[2] && p.latitude >= box[1] && p.latitude <= box[3];
  bool hits(LatLngBounds b) => !(box[2] < b.west || box[0] > b.east || box[3] < b.south || box[1] > b.north);
  int countFor(String kind) => kind == 'food' ? food : (kind == 'cafe' ? cafe : count);
}

class Sido {
  final String name;
  final List<Area> areas;
  Sido(Map<String, dynamic> j)
      : name = j['name'] ?? '',
        areas = [];
  bool get ready => areas.any((a) => a.ready);
}

// 새로 뜨는 집: 최근 한 달 안에 유튜버 영상이 올라온 집 (영상 날짜 yyyy-mm-dd 또는 yyyymmdd)
String ytLast(Place p) {
  var last = '';
  for (final v in p.vids) {
    final d = v.date.replaceAll('-', '');
    if (d.length == 8 && d.compareTo(last) > 0) last = d;
  }
  return last;
}

bool ytRecent(Place p, [int days = 30]) {
  final last = ytLast(p);
  if (last.isEmpty) return false;
  final cut = DateTime.now().subtract(Duration(days: days));
  final c = '${cut.year}${cut.month.toString().padLeft(2, '0')}${cut.day.toString().padLeft(2, '0')}';
  return last.compareTo(c) >= 0;
}

String mdText(String yyyymmdd) =>
    yyyymmdd.length == 8 ? '${int.parse(yyyymmdd.substring(4, 6))}월 ${int.parse(yyyymmdd.substring(6))}일' : '';

// 지도 가운데가 어느 시·군·구인지: 콕플 자료 가게 주소로 어림한다 (돈 드는 지도 서비스를 쓰지 않음)
String placeName(LatLng c, Iterable<Place> src, double zoom) {
  if (zoom < 8) return '전국';
  Place? best;
  var bd = double.infinity;
  for (final p in src) {
    final d = meters(c, p.point);
    if (d < bd) {
      bd = d;
      best = p;
    }
  }
  if (best == null || bd > 60000) return '전국';
  final parts = best.addr.split(' ').where((x) => x.isNotEmpty).toList();
  if (parts.isEmpty) return '전국';
  var sido = parts[0].replaceAll(RegExp(r'(통합특별시|특별자치도|특별자치시|특별시|광역시)$'), '');
  if (sido == '전남광주') sido = '광주·전남';
  if (bd > 25000 || parts.length < 2 || !RegExp(r'(시|군|구)$').hasMatch(parts[1])) return sido;
  return '$sido ${parts[1]}';
}

// 지역 목록을 못 받았을 때 쓰는 기본값 (송도만)
final kDefaultArea = Area({'id': 'songdo', 'name': '송도/연수', 'gu': '연수구', 'lat': 37.3905, 'lng': 126.6430, 'zoom': 13, 'ready': true}, '인천');

String dataUrl(String file) => kIsWeb ? Uri.base.resolve('data/$file').toString() : '$kDataBase$file';

// 지도 위 한 점을 화면에서 dy 픽셀 아래로 옮긴 자리 (메르카토르, 경도는 그대로)
LatLng shiftDown(LatLng p, double zoom, double dy) {
  final scale = 256 * math.pow(2, zoom).toDouble();
  final r = p.latitude * math.pi / 180;
  final y = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * scale + dy;
  final n = math.pi - 2 * math.pi * y / scale;
  return LatLng(180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n))), p.longitude);
}

Future<List<Sido>> loadRegions({bool fallback = true}) async {
  try {
    final res = await http.get(Uri.parse('${dataUrl('regions.json')}?t=${DateTime.now().millisecondsSinceEpoch}'));
    if (res.statusCode == 200) {
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final out = <Sido>[];
      for (final sj in (j['sido'] ?? []) as List) {
        final sd = Sido(sj);
        sd.areas.addAll(((sj['areas'] ?? []) as List).map((a) => Area(a, sd.name)));
        out.add(sd);
      }
      if (out.isNotEmpty) return out;
    }
  } catch (_) {}
  if (!fallback) return [];
  final sd = Sido({'name': '인천'});
  sd.areas.add(kDefaultArea);
  return [sd];
}

class SongdoData {
  final String updated;
  final int recentDays;
  final List<Place> places;
  final List<Chan> channels; // 이 동네에 다녀간 유튜버
  SongdoData(this.updated, this.recentDays, this.places, [this.channels = const []]);
}

// 동네 자료 받기: 한 번 받은 동네는 휴대폰에 저장해 두고, 새 판(지역 목록의 updated)이 나올 때까지 다시 받지 않는다
Future<SongdoData> loadData(String areaId, {String version = ''}) async {
  SharedPreferences? sp;
  try {
    sp = await SharedPreferences.getInstance();
  } catch (_) {}
  final key = 'area_$areaId';
  String? body;
  try {
    final savedVer = sp?.getString('${key}_v') ?? '';
    final savedAt = sp?.getInt('${key}_at') ?? 0;
    final fresh = version.isNotEmpty ? savedVer == version : DateTime.now().millisecondsSinceEpoch - savedAt < 3 * 3600 * 1000;
    if (fresh) body = sp?.getString(key);
  } catch (_) {}
  if (body == null) {
    final res = await http.get(Uri.parse('${dataUrl('$areaId.json')}?t=${DateTime.now().millisecondsSinceEpoch}'));
    if (res.statusCode != 200) throw Exception('자료를 아직 받지 못했습니다 (${res.statusCode})');
    body = utf8.decode(res.bodyBytes);
    try {
      if (body.length < 1500000) {
        await sp?.setString(key, body);
        await sp?.setString('${key}_v', version);
        await sp?.setInt('${key}_at', DateTime.now().millisecondsSinceEpoch);
      }
    } catch (_) {}
  }
  final j = jsonDecode(body) as Map<String, dynamic>;
  final list = ((j['places'] ?? []) as List).map((e) => Place(e, areaId)).toList();
  final chans = ((j['channels'] ?? []) as List).map((e) => Chan.fromJson(e as Map<String, dynamic>)).toList();
  return SongdoData(j['updated'] ?? '', j['recent_days'] ?? 90, list, chans);
}

// 유명 유튜버 따라가기 (전국): 큰 맛집 채널이 영상 설명란에 주소를 적은 가게
class FollowData {
  final String updated;
  final List<Chan> channels; // 가게 많은 순 (이름은 짧은 이름)
  final List<Place> places;
  final Map<String, String> names; // 채널 id → 짧은 이름
  FollowData(this.updated, this.channels, this.places, this.names);
  // 새로 올라온 영상 (한 영상에 여러 집이면 한 번만) — 한 번만 계산
  late final List<(Video, Place)> fresh = () {
    final all = [for (final p in places) for (final v in p.vids) (v, p)]..sort((a, b) => b.$1.date.compareTo(a.$1.date));
    final seen = <String>{};
    return [for (final it in all) if (seen.add(it.$1.id)) it].take(15).toList();
  }();
}

Future<FollowData?> loadFollow({bool fresh = false}) async {
  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    final res = await http.get(Uri.parse('${dataUrl('follow.json')}?t=${fresh ? now : now ~/ 3600000}'));
    if (res.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final places = ((j['places'] ?? []) as List).map((e) => Place(e as Map<String, dynamic>, 'follow')).toList();
    final byCh = <String, List<String>>{};
    for (final p in places) {
      for (final cid in p.vids.map((v) => v.cid).toSet()) {
        byCh.putIfAbsent(cid, () => []).add(p.id);
      }
    }
    final names = <String, String>{};
    final chans = <Chan>[];
    for (final c in (j['channels'] ?? []) as List) {
      final id = '${c['id']}';
      final nm = '${c['short'] ?? ''}'.isNotEmpty ? '${c['short']}' : '${c['name'] ?? ''}';
      names[id] = nm;
      if ((byCh[id] ?? []).isNotEmpty) chans.add(Chan(id, nm, '${c['thumb'] ?? ''}', ((c['subs'] ?? 0) as num).toInt(), byCh[id]!));
    }
    // 유튜버 순서는 자료 파일 순서 그대로 (모으는 쪽에서 대중 인지도 순으로 줄 세움)
    return FollowData(j['updated'] ?? '', chans, places, names);
  } catch (_) {
    return null;
  }
}

String sidoShort(String s) =>
    const {'제주특별자치도': '제주', '강원특별자치도': '강원', '전북특별자치도': '전북', '전남광주통합특별시': '광주·전남', '세종특별자치시': '세종'}[s] ?? s;

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

class _MapPageState extends State<MapPage> with WidgetsBindingObserver {
  final map = MapController();
  List<Sido> sidos = [];
  Area area = kDefaultArea; // 초점 동네 (머리말·홈·순위)
  final Map<String, SongdoData> loaded = {}; // 불러온 동네 자료 (관리자가 고친 값·숨김 반영)
  final Map<String, SongdoData> orig = {}; // 받은 그대로 (고친 값을 다시 덮을 때)
  HomeRemote? remote; // 메인 칸 순서 · 배너 · 팝업 (관리자 화면에서)
  final Set<String> loadingIds = {};
  SongdoData? get data => loaded[area.id];
  int tab = 0; // 0 홈, 1 영상, 2 지도, 3 내 콕
  List<Map<String, dynamic>> koks = []; // 내 콕 (저장한 집)
  List<Map<String, dynamic>> recents = []; // 최근 본 집 (휴대폰 안에만, 최대 30곳)
  LatLngBounds? bounds; // 지금 지도에 보이는 범위
  Course? course; // 지도에서 보는 중인 테마 코스
  String cuisine = ''; // 음식 종류 고르기 (한식·중식 …, 비면 전체)
  FollowData? follow; // 유명 유튜버 따라가기 (전국)
  bool followOn = false; // 지도에서 따라가기 가게를 보는 중
  String here = ''; // 따라가기 중 지도 가운데가 콕플 동네 밖일 때 머리말에 보일 지역 (예: 제주 제주시, 전국)
  String followCh = ''; // 그중 한 채널만 (비면 전체)
  List<Place> _fp = const [];
  String _fpKey = '#';
  Place? focus; // 지금 연 가게: 순위가 낮거나 지금 분류에 없어도 지도에 빨간 큰 카드로
  DateTime _checkedAt = DateTime.now(); // 마지막으로 새 정보를 확인한 때
  Future<int>? _checking;
  List<Place> get followPlaces {
    final f = follow;
    if (f == null) return const [];
    if (_fpKey != followCh) {
      _fpKey = followCh;
      final base = followCh.isEmpty ? f.places : f.places.where((p) => p.vids.any((v) => v.cid == followCh));
      // 관리자가 숨긴 집은 빼고, 고친 값은 덮어서
      _fp = [
        for (final p in base)
          if (guards[p.id]?.hidden != true) guarded(p)
      ];
    }
    return _fp;
  }
  Timer? _sync;
  static const kClusterZoom = 11.5; // 이보다 넓게 보면 동네별 숫자 묶음
  static const kSidoZoom = 9.0; // 이보다 넓게 보면 시·도별 숫자 묶음
  List<Area> get readyAreas => [for (final s in sidos) ...s.areas.where((a) => a.ready)];
  String? error;
  String kind = 'all'; // all 전체, near 내 주변, open 영업 중, food 맛집, cafe 카페, rise 새로 뜨는 집 (최근 한 달 안에 유튜버가 다녀간 집)
  final Set<String> feats = {}; // 편의 필터 (주차·아이 동반 등, 모두 갖춘 집만)
  LatLng? me; // 내 위치
  bool locating = false;
  static const kNearMeters = 3000.0; // 내 주변: 3km 안
  double zoom = 13;
  String get kindLabel {
    final b = switch (kind) {
      'cafe' => '카페',
      'food' => '맛집',
      'near' => '내 주변',
      'open' => '영업 중',
      'rise' => '새로 뜨는 집',
      _ => '맛집·카페',
    };
    return cuisine.isEmpty ? b : (kind == 'all' ? cuisine : '$cuisine $b');
  }

  // 홈에서 음식 종류: 지도로 가서 지금 동네의 그 음식 집이 모두 보이게 맞춘다
  void goCuisine(String c) {
    setState(() {
      followOn = false;
      focus = null;
      tab = 2;
      regionOpen = false;
      kind = 'all';
      cuisine = c;
      course = null;
    });
    final d = data;
    final pts = [
      for (final p in d?.places ?? const <Place>[])
        if (p.top && cuisineOf(p) == c) p.point
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (pts.length >= 2) {
        map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.fromLTRB(70, 240, 70, 120), maxZoom: 15.5));
      } else if (pts.length == 1) {
        map.move(pts.first, 15.5);
      } else {
        map.move(area.center, area.zoom);
      }
    });
  }

  // 음식 종류 고르기 (지도 분류 줄의 「음식 종류」 · 홈의 음식 알약)
  void pickCuisine(String c) => setState(() {
        cuisine = c;
        course = null;
        focus = null;
      });

  void openCuisine() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (ctx) => Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(20, 18, 20, 22 + MediaQuery.of(ctx).padding.bottom),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              mixTitle('음식 ', '종류', size: 17),
              const SizedBox(height: 14),
              CuisinePills(
                current: cuisine,
                withAll: true,
                onPick: (c) {
                  Navigator.pop(ctx);
                  pickCuisine(c);
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // 분류 단추를 눌렀을 때: 내 주변은 위치부터 확인
  Future<void> pickKind(String k) async {
    if (k != 'near') {
      setState(() {
        kind = k;
        focus = null;
      });
      return;
    }
    setState(() {
      kind = 'near';
      followOn = false;
      focus = null;
      locating = true;
      course = null;
    });
    final pos = await myLocation();
    if (!mounted) return;
    setState(() {
      locating = false;
      if (pos != null) {
        me = pos;
        myPos.value = pos;
      }
    });
    if (pos != null) await _ensureNear(pos);
    if (!mounted) return;
    if (pos == null) {
      setState(() => kind = 'all');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('내 위치를 확인하지 못했습니다. 위치 사용을 허용해 주세요.')));
      return;
    }
    map.move(pos, 15);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    allPlaces = () => [...loaded.values.expand((d) => d.places), ...?follow?.places];
    onAdminChanged = _adminChanged;
    authTick.addListener(_onAuth);
    _start();
    _remoteStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    myPos.removeListener(_onPos);
    authTick.removeListener(_onAuth);
    _sync?.cancel();
    _kokPush?.cancel();
    super.dispose();
  }

  // ---- 내 콕을 계정에 맞추기 ----
  // 이 휴대폰이 그 계정과 처음 만나면 휴대폰 목록 + 계정 목록을 합치고,
  // 이미 맞춘 적이 있으면 계정 쪽을 기준으로 (다른 휴대폰에서 뺀 집이 되살아나지 않게)
  String? _syncUid;
  bool _koksReady = false;
  Timer? _kokPush;
  Future<void> _onAuth() async {
    final u = fbOn ? fbUser : null;
    if (u == null) {
      // 로그아웃: 다음 로그인 때는 그동안 휴대폰에 콕한 집도 합치도록 표시를 지운다
      if (_syncUid != null) SharedPreferences.getInstance().then((sp) => sp.remove('kok_uid')).catchError((_) => false);
      _syncUid = null;
      return;
    }
    if (!_koksReady || u.uid == _syncUid) return;
    _syncUid = u.uid;
    _syncWatched(u.uid);
    final cloud = await cloudKoks();
    if (!mounted || cloud == null || (fbUser?.uid ?? '') != u.uid) return;
    String? last;
    try {
      last = (await SharedPreferences.getInstance()).getString('kok_uid');
    } catch (_) {}
    final List<Map<String, dynamic>> next;
    if (last == u.uid) {
      next = cloud;
    } else {
      final have = {for (final k in koks) '${k['id']}'};
      next = [...koks, ...cloud.where((k) => !have.contains('${k['id']}'))];
    }
    setState(() => koks = next);
    _saveList('koks', koks);
    SharedPreferences.getInstance().then((sp) => sp.setString('kok_uid', u.uid)).catchError((_) => false);
    if (last != u.uid) pushKoks(koks);
  }

  // 추천 영상 재생 기록: 휴대폰 기록 + 계정 기록을 합친다 (더 최근에 본 쪽을 남김)
  Future<void> _syncWatched(String uid) async {
    final cloud = await cloudWatched();
    if (cloud == null || (fbUser?.uid ?? '') != uid) return;
    var changed = false;
    for (final e in cloud.entries) {
      final mine = heroWatched[e.key];
      if (mine == null || ((e.value['t'] ?? 0) as num) > ((mine['t'] ?? 0) as num)) {
        heroWatched[e.key] = e.value;
        changed = true;
      }
    }
    final extra = heroWatched.keys.any((k) => !cloud.containsKey(k));
    if (changed || extra) saveWatched(push: extra);
  }

  // 콕을 넣거나 뺄 때: 휴대폰에 바로 저장, 로그인했으면 잠시 뒤 계정에도
  void _kokChanged() {
    _saveList('koks', koks);
    if (!fbOn || fbUser == null) return;
    _kokPush?.cancel();
    _kokPush = Timer(const Duration(milliseconds: 1200), () => pushKoks(koks));
  }

  // 다른 앱에 갔다 돌아오면: 마지막 확인에서 10분이 지났으면 조용히 새 정보 확인
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (DateTime.now().difference(_checkedAt) < const Duration(minutes: 10)) return;
    checkNew().then((r) {
      if (r == 1 && mounted) _toast('새 맛집 정보로 바꿨어요');
    }).catchError((_) {});
  }

  // 새 정보 확인: 작은 지역 목록만 다시 받아 판(updated)이 바뀐 동네만 새로 받고, 따라가기 자료도 다시 확인
  // 1 바뀜 · 0 그대로 · -1 못 받음
  Future<int> checkNew() => _checking ??= _checkNew().whenComplete(() => _checking = null);

  Future<int> _checkNew() async {
    _checkedAt = DateTime.now();
    final list = await loadRegions(fallback: false);
    if (list.isEmpty) return -1;
    final before = {for (final a in readyAreas) a.id: a.updated};
    final all = [for (final s in list) ...s.areas.where((a) => a.ready)];
    final stale = [for (final a in all) if (loaded.containsKey(a.id) && before[a.id] != a.updated) a];
    var changed = stale.isNotEmpty || all.any((a) => !before.containsKey(a.id));
    if (!mounted) return 0;
    setState(() {
      sidos = list;
      area = all.where((a) => a.id == area.id).firstOrNull ?? area;
    });
    for (final a in stale) {
      try {
        final d = await loadData(a.id, version: a.updated);
        orig[a.id] = d;
        if (mounted) setState(() => loaded[a.id] = _guard(d));
      } catch (_) {}
    }
    if (error != null) _load();
    final f = await loadFollow(fresh: true);
    if (f != null && mounted && f.updated != follow?.updated) {
      changed = true;
      setState(() {
        follow = f;
        _fpKey = '#';
      });
    }
    return changed ? 1 : 0;
  }

  // 관리자가 고친 값 덮기 · 숨긴 가게 빼기
  SongdoData _guard(SongdoData d) {
    if (guards.isEmpty) return d;
    return SongdoData(d.updated, d.recentDays, [
      for (final p in d.places)
        if (guards[p.id]?.hidden != true) guarded(p)
    ], d.channels);
  }

  void _reguard() {
    if (!mounted) return;
    setState(() {
      _fpKey = '#';
      for (final e in orig.entries) {
        loaded[e.key] = _guard(e.value);
      }
    });
  }

  // 파이어베이스: 메인 설정·가게 보호를 받고, 팝업은 앱 켤 때 한 번
  Future<void> _remoteStart() async {
    if (!await fbReady()) return;
    await loadGuards();
    _reguard();
    final r = await loadHomeRemote();
    if (!mounted || r == null) return;
    setState(() => remote = r);
    final pop = r.popup;
    if (pop != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showHomePopup(context, pop);
      });
    }
  }

  // 관리자 화면에서 저장하면: 설정·보호 다시 받기
  Future<void> _adminChanged() async {
    await loadGuards();
    _reguard();
    final r = await loadHomeRemote();
    if (mounted && r != null) setState(() => remote = r);
  }

  // 배너 누르기: 주소면 열고, place:가게 id 면 그 집
  void openBanner(HomeBanner b) {
    final l = b.link;
    if (l.startsWith('http')) {
      openUrl(l);
    } else if (l.startsWith('place:')) {
      final id = l.substring(6);
      final p = loaded.values.expand((d) => d.places).where((x) => x.id == id).firstOrNull;
      if (p != null) goWhere(p);
    }
  }

  // 아래로 당겨 새로 고침
  Future<void> pullRefresh() async {
    var r = -1;
    try {
      r = await checkNew();
    } catch (_) {}
    if (!mounted) return;
    _toast(switch (r) {
      1 => '새 맛집 정보로 바꿨어요',
      0 => '지금이 가장 새 정보예요',
      _ => '새 정보를 확인하지 못했어요. 인터넷 연결을 확인해 주세요',
    });
  }

  void _toast(String t) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 2)));
  }

  // 지역 목록을 받고, 지난번에 본 동네를 다시 연다
  void _onPos() {
    final v = myPos.value;
    if (v != null && v != me && mounted) setState(() => me = v);
  }

  // 처음 켤 때 위치: 허락해 둔 휴대폰은 조용히 받고, 허락을 묻는 건 처음 한 번만
  Future<LatLng?> _firstLocation() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!(sp.getBool('loc_asked') ?? false)) {
        await sp.setBool('loc_asked', true);
        return await myLocation();
      }
    } catch (_) {}
    return quietLocation();
  }

  Future<void> _start() async {
    myPos.addListener(_onPos);
    final locF = _firstLocation();
    locF.then((at) {
      if (at != null) myPos.value = at;
    });
    final list = await loadRegions();
    String? saved;
    var savedKoks = <String>[], savedRecents = <String>[];
    try {
      final sp = await SharedPreferences.getInstance();
      saved = sp.getString('area');
      savedKoks = sp.getStringList('koks') ?? [];
      savedRecents = sp.getStringList('recents') ?? [];
    } catch (_) {}
    koks = [
      for (final k in savedKoks)
        if (k.startsWith('{')) jsonDecode(k) as Map<String, dynamic>
    ];
    recents = [
      for (final k in savedRecents)
        if (k.startsWith('{')) jsonDecode(k) as Map<String, dynamic>
    ];
    _koksReady = true;
    _onAuth(); // 이미 로그인돼 있으면 계정의 내 콕과 맞춘다
    final all = [for (final s in list) ...s.areas.where((a) => a.ready)];
    // 홈 첫 동네: 내 위치가 서비스 동네 안이나 근처면 그 동네, 아니면 마지막에 고른 동네 (위치는 잠깐만 기다림)
    final at = await locF.timeout(const Duration(milliseconds: 1500), onTimeout: () => null);
    final pick = nearArea(all, at) ??
        all.where((a) => a.id == saved).firstOrNull ??
        all.where((a) => a.id == 'songdo').firstOrNull ??
        (all.isNotEmpty ? all.first : kDefaultArea);
    setState(() {
      sidos = list;
      area = pick;
    });
    if (at == null) {
      // 위치가 늦게 오면: 아직 홈에서 처음 동네를 보고 있을 때만 내 동네로 바꾼다
      locF.then((late) {
        final near = nearArea(readyAreas, late);
        if (!mounted || near == null || near.id == pick.id) return;
        if (area.id != pick.id || tab != 0 || regionOpen) return;
        setState(() => area = near);
        try {
          map.move(near.center, near.zoom);
        } catch (_) {}
        _ensure(near.id);
      });
    }
    if (pick.id != kDefaultArea.id) {
      try {
        map.move(pick.center, pick.zoom);
      } catch (_) {}
    }
    _load();
    loadFollow().then((f) {
      if (mounted && f != null) {
        setState(() {
          follow = f;
          _fpKey = '#';
        });
      }
    });
  }

  Future<void> _load() => _ensure(area.id);

  // 동네 자료가 없으면 받는다 (받아 둔 동네는 다시 받지 않음)
  Future<void> _ensure(String id) async {
    if (loaded.containsKey(id) || loadingIds.contains(id)) return;
    final a = readyAreas.where((x) => x.id == id).firstOrNull;
    loadingIds.add(id);
    if (id == area.id) setState(() => error = null);
    try {
      final d = await loadData(id, version: a?.updated ?? '');
      orig[id] = d;
      if (mounted) setState(() => loaded[id] = _guard(d));
    } catch (e) {
      if (mounted && id == area.id) setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      loadingIds.remove(id);
    }
  }

  // 지역 고르기 = 지도를 그 동네로 옮기기만 (가게는 보이는 범위를 따라 불러온다)
  void setArea(Area a) {
    setState(() {
      followOn = false;
      here = '';
      focus = null;
      regionOpen = false;
      area = a;
      course = null;
    });
    map.move(a.center, a.zoom);
    SharedPreferences.getInstance().then((sp) => sp.setString('area', a.id)).catchError((_) => false);
    _ensure(a.id);
  }

  // 지도가 멈추면: 보이는 범위에 걸친 동네 자료를 불러오고, 머리말 동네를 지도 가운데 동네로
  void _syncView(MapCamera cam) {
    if (!mounted) return;
    setState(() {
      bounds = cam.visibleBounds;
      zoom = cam.zoom;
    });
    if (cam.zoom >= kClusterZoom) {
      for (final a in readyAreas) {
        if (a.hits(cam.visibleBounds)) _ensure(a.id);
      }
    }
    final inside = readyAreas.where((a) => a.contains(cam.center)).toList()
      ..sort((x, y) => meters(cam.center, x.center).compareTo(meters(cam.center, y.center)));
    final h = (followOn && inside.isEmpty && follow != null) ? placeName(cam.center, follow!.places, cam.zoom) : '';
    if (h != here) setState(() => here = h);
    if (inside.isNotEmpty && inside.first.id != area.id) {
      final a = inside.first;
      setState(() => area = a);
      _ensure(a.id);
      SharedPreferences.getInstance().then((sp) => sp.setString('area', a.id)).catchError((_) => false);
    }
  }

  // 숫자 묶음 풍선 (동네·시·도·따라가기 묶음)
  Marker bubble(String key, LatLng c, String name, int n, VoidCallback onTap) => Marker(
        key: ValueKey('bubble$key'),
        point: c,
        width: 200,
        height: 44,
        child: Center(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              decoration: BoxDecoration(
                color: kRegion,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white, width: 1),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10)],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
                if (n > 0) ...[
                  const SizedBox(width: 6),
                  Text('$n', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                ],
              ]),
            ),
          ),
        ),
      );

  // 축소 화면: 동네별(더 넓으면 시·도별) 숫자 묶음 — 수집할 때 세어 둔 숫자만 쓴다
  List<Marker> clusterMarkers() {
    int n(Area a) {
      final c = a.countFor(kind);
      if (c > 0) return c;
      final d = loaded[a.id];
      return d == null ? 0 : d.places.where((p) => p.top && (kind != 'food' && kind != 'cafe' || p.kind == kind)).length;
    }

    if (zoom < kSidoZoom) {
      return [
        for (final s in sidos)
          if (s.ready)
            () {
              final ra = s.areas.where((a) => a.ready).toList();
              final c = LatLng(ra.map((a) => a.lat).reduce((x, y) => x + y) / ra.length, ra.map((a) => a.lng).reduce((x, y) => x + y) / ra.length);
              return bubble(s.name, c, s.name, ra.fold<int>(0, (t, a) => t + n(a)), () => map.move(c, kSidoZoom + 1.5));
            }(),
      ];
    }
    return [for (final a in readyAreas) bubble(a.id, a.center, a.name, n(a), () => map.move(a.center, a.zoom))];
  }

  // 따라가기 축소 화면: 화면 칸(가로 130·세로 60px)마다 묶고, 겹치는 풍선은 큰 쪽에 합친다
  // 이름: 넓게 보면 시·도, 가까이 보면 시·군·구 — 한 지역이 60% 넘으면 그 이름, 아니면 「○○ 일대」
  List<Marker> followClusters() {
    final scale = 256 * math.pow(2, zoom).toDouble();
    Offset px(LatLng p) {
      final x = (p.longitude + 180) / 360 * scale;
      final r = p.latitude * math.pi / 180;
      final y = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * scale;
      return Offset(x, y);
    }

    final cells = <String, List<Place>>{};
    for (final p in followPlaces) {
      final o = px(p.point);
      cells.putIfAbsent('${(o.dx / 130).floor()}_${(o.dy / 60).floor()}', () => []).add(p);
    }
    final groups = cells.values.toList()..sort((a, b) => b.length.compareTo(a.length));
    final rects = <Rect>[];
    final members = <List<Place>>[];
    final centers = <LatLng>[];
    for (final g in groups) {
      final c = LatLng(g.map((p) => p.lat).reduce((x, y) => x + y) / g.length, g.map((p) => p.lng).reduce((x, y) => x + y) / g.length);
      final r = Rect.fromCenter(center: px(c), width: 128, height: 44);
      final hit = rects.indexWhere((k) => k.overlaps(r));
      if (hit >= 0) {
        members[hit].addAll(g);
        continue;
      }
      rects.add(r);
      members.add([...g]);
      centers.add(c);
    }
    String label(List<Place> ps) {
      final m = <String, int>{};
      for (final p in ps) {
        final k = zoom < kSidoZoom ? sidoShort(p.sido) : p.gu.split(' ').first;
        if (k.isNotEmpty) m[k] = (m[k] ?? 0) + 1;
      }
      if (m.isEmpty) return '';
      final top = (m.entries.toList()..sort((x, y) => y.value.compareTo(x.value))).first;
      return top.value >= ps.length * 0.6 ? top.key : '${top.key} 일대';
    }

    return [
      for (var i = 0; i < members.length; i++)
        bubble('f${members[i].first.id}', centers[i], label(members[i]), members[i].length, () => zoomInto(members[i], centers[i])),
    ];
  }

  // 묶음 풍선을 누르면 그 묶음 가게들이 다 보이게 (넓게 퍼져 있으면 한 단계 반만 확대)
  void zoomInto(List<Place> ps, LatLng c) {
    final cam = CameraFit.coordinates(
      coordinates: [for (final p in ps) p.point],
      padding: const EdgeInsets.fromLTRB(50, 230, 50, 100),
      maxZoom: 14,
    ).fit(map.camera);
    if (cam.zoom <= zoom + 0.5) {
      map.move(c, zoom + 1.5);
    } else {
      map.move(cam.center, cam.zoom);
    }
  }

  // 유튜버 따라 먹기: 지도에서 전국 가게 (한 채널만 고를 수도)
  void openFollow([String ch = '']) {
    if (follow == null) return;
    setState(() {
      followOn = true;
      focus = null;
      followCh = ch;
      _fpKey = '#';
      course = null;
      tab = 2;
      regionOpen = false;
      searching = false;
      query = '';
      searchCtl.clear();
    });
    final ps = followPlaces;
    if (ps.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final at = me ?? myPos.value;
      if (at != null && ps.where((p) => meters(at, p.point) < 8000).length >= 3) {
        map.move(at, 12.4); // 내 근처에 몇 곳 있으면 거기부터
      } else {
        map.fitCamera(CameraFit.coordinates(
          coordinates: [for (final p in ps) p.point],
          padding: const EdgeInsets.fromLTRB(40, 210, 40, 90),
          maxZoom: 12.5,
        ));
      }
    });
  }

  // 새로 올라온 영상·내 콕에서 따라가기 가게 하나 열기
  void openFollowPlace(Place p) {
    setState(() {
      followOn = true;
      focus = null;
      followCh = '';
      _fpKey = '#';
      course = null;
      tab = 2;
      regionOpen = false;
      searching = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => openPlace(p));
  }

  void closeFollow() {
    final away = here.isNotEmpty; // 지도가 아직 준비 중인 지역에 있음 → 고르신 동네로 돌아감
    setState(() {
      followOn = false;
      focus = null;
      followCh = '';
      _fpKey = '#';
      here = '';
    });
    if (away) map.move(area.center, area.zoom);
  }

  // 따라가기: 지금 보이는 범위의 가게 (여러 채널이 다녀간 집 → 최근 영상 순)
  List<Place> followVisible() {
    final b = bounds;
    Iterable<Place> src = followPlaces;
    if (b != null) {
      final dLat = (b.north - b.south) * 0.1, dLng = (b.east - b.west) * 0.1;
      src = src.where((p) => p.lat >= b.south - dLat && p.lat <= b.north + dLat && p.lng >= b.west - dLng && p.lng <= b.east + dLng);
    }
    final out = src.toList()
      ..sort((a, b) {
        final c = ytCount(b).compareTo(ytCount(a));
        return c != 0 ? c : b.vids.first.date.compareTo(a.vids.first.date);
      });
    return out.take(300).toList();
  }

  // 오늘 뭐 먹지: 뽑을 집 (유튜버·방송 맛집, 모자라면 인기 맛집까지)
  List<Place> roulettePool(String k, bool near) {
    final at = me;
    Iterable<Place> src = near && at != null
        ? loaded.values.expand((d) => d.places).where((p) => meters(at, p.point) <= kNearMeters)
        : (data?.places ?? const <Place>[]);
    src = src.where((p) => p.top && (k == 'all' || p.kind == k));
    final yt = src.where((p) => p.vids.isNotEmpty || p.tv.isNotEmpty).toList();
    return yt.length >= 4 ? yt : src.toList();
  }

  // 내 위치 근처(약 4km 안) 동네 자료 불러오기
  Future<void> _ensureNear(LatLng at) async {
    for (final a in readyAreas) {
      final b = a.box;
      if (at.longitude >= b[0] - 0.045 && at.longitude <= b[2] + 0.045 && at.latitude >= b[1] - 0.035 && at.latitude <= b[3] + 0.035) {
        await _ensure(a.id);
      }
    }
  }

  // 내 위치 확인 (룰렛 「내 주변」)
  Future<bool> locateMe() async {
    final at = await myLocation();
    if (at == null || !mounted) return false;
    setState(() => me = at);
    myPos.value = at;
    await _ensureNear(at);
    return true;
  }

  void openRoulette() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (_) => RouletteSheet(poolOf: roulettePool, locate: locateMe, located: me != null, areaName: area.name, onWhere: goWhere),
    );
  }

  // 테마 코스를 지도에서: 코스 집들만 순서대로 잇고 화면을 맞춘다
  void openCourse(Course c) {
    setState(() {
      followOn = false;
      focus = null;
      course = c;
      tab = 2;
      regionOpen = false;
      searching = false;
      query = '';
      searchCtl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => map.fitCamera(CameraFit.coordinates(
          coordinates: [for (final p in c.stops) p.point],
          padding: const EdgeInsets.fromLTRB(70, 240, 70, 120),
          maxZoom: 16.5,
        )));
  }

  void openCourseSheet(Course c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (ctx) => SheetList(
        head: Align(
          alignment: Alignment.centerLeft,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            mixTitle(c.bold, c.light, size: 18),
            const SizedBox(height: 3),
            Text(c.route ? '${c.stops.length}곳 · ${c.trip} (직선 거리로 어림)' : c.sub, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w300, color: kSub)),
          ]),
        ),
        rows: [
          for (var i = 0; i < c.stops.length; i++) ...[
            if (i > 0 && c.route)
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 2, bottom: 2),
                child: Text('↓ ${distText(meters(c.stops[i - 1].point, c.stops[i].point))}', style: const TextStyle(fontSize: 10.5, color: kSub)),
              ),
            YtRow(
              place: c.stops[i],
              rank: i + 1,
              onTap: () {
                Navigator.pop(ctx);
                openPlace(c.stops[i]);
              },
            ),
          ],
        ],
      ),
    );
  }

  // 「이 집 어디야」: 지도 탭으로 가서 그 집을 연다
  void goWhere(Place p) {
    setState(() {
      followOn = false;
      focus = null;
      tab = 2;
      regionOpen = false;
      course = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => openPlace(p));
  }

  // 내 콕
  bool isKok(Place p) => koks.any((k) => k['id'] == p.id);
  // 내 콕·최근 본 집에 남기는 한 줄 (지역 자료를 다시 받지 않아도 목록을 그릴 수 있게)
  Map<String, dynamic> placeRec(Place p) => {
        'id': p.id,
        'n': p.name,
        'k': p.kind,
        'c': p.cat,
        'la': p.lat,
        'ln': p.lng,
        'a': p.areaId,
        'an': p.areaId == 'follow'
            ? [sidoShort(p.sido), p.gu].where((x) => x.isNotEmpty).join(' ')
            : (readyAreas.where((a) => a.id == p.areaId).firstOrNull?.name ?? area.name),
        'th': p.vids.isEmpty ? '' : 'https://i.ytimg.com/vi/${p.vids.first.id}/mqdefault.jpg',
      };
  void _saveList(String key, List<Map<String, dynamic>> list) =>
      SharedPreferences.getInstance().then((sp) => sp.setStringList(key, [for (final k in list) jsonEncode(k)])).catchError((_) => false);
  void toggleKok(Place p, bool on) {
    setState(() {
      koks.removeWhere((k) => k['id'] == p.id);
      if (on) koks.insert(0, placeRec(p));
    });
    _kokChanged();
  }

  // 최근 본 집: 가게 화면을 열 때마다 맨 위로 (같은 집은 한 번만, 30곳까지)
  void noteRecent(Place p) {
    final r = placeRec(p)..['t'] = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      recents.removeWhere((k) => k['id'] == p.id);
      recents.insert(0, r);
      if (recents.length > 30) recents.removeRange(30, recents.length);
    });
    _saveList('recents', recents);
  }

  void openKok(Map<String, dynamic> k) {
    if (k['a'] == 'follow') {
      final fp = follow?.places.where((x) => x.id == k['id']).firstOrNull;
      if (fp != null) {
        openFollowPlace(fp);
        return;
      }
    }
    final a = readyAreas.where((x) => x.id == k['a']).firstOrNull;
    final at = LatLng(((k['la'] ?? 0) as num).toDouble(), ((k['ln'] ?? 0) as num).toDouble());
    setState(() {
      tab = 2;
      if (a != null) area = a;
    });
    if (a != null) _ensure(a.id);
    final p = loaded.values.expand((d) => d.places).where((x) => x.id == k['id']).firstOrNull;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (p != null) {
        openPlace(p);
      } else {
        map.move(at, 16);
      }
    });
  }

  void openChannel(Chan c) {
    final d = data;
    if (d == null) return;
    final ps = [for (final id in c.places) ...d.places.where((p) => p.id == id)];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (ctx) => SheetList(
        head: Row(children: [
          ChanAvatar(c, ring: kAccent, label: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.4)),
              const SizedBox(height: 3),
              Text([if (c.subs > 0) subsText(c.subs), '${area.name}에서 다녀간 집 ${ps.length}곳'].join(' · '),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300, color: kSub)),
            ]),
          ),
        ]),
        rows: [
          for (var i = 0; i < ps.length; i++)
            YtRow(
              place: ps[i],
              rank: i + 1,
              onTap: () {
                Navigator.pop(ctx);
                goWhere(ps[i]);
              },
            ),
        ],
      ),
    );
  }

  void openAllChannels() {
    final d = data;
    if (d == null) return;
    final list = channelsOf(d);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (ctx) => SheetList(
        head: Align(alignment: Alignment.centerLeft, child: mixTitle('${area.name} ', '유튜버 ${list.length}명', size: 18)),
        rows: [
          for (final c in list)
            InkWell(
              onTap: () {
                Navigator.pop(ctx);
                openChannel(c);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  ChanAvatar(c, label: false),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
                      const SizedBox(height: 2),
                      Text([if (c.subs > 0) subsText(c.subs), '다녀간 집 ${c.places.length}곳'].join(' · '),
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w300, color: kSub)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: kSub),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  void openYtRank() {
    final d = data;
    if (d == null) return;
    final yt = ytRank(d);
    final list = yt.isNotEmpty ? yt : popRank(d);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (ctx) => SheetList(
        head: Align(
            alignment: Alignment.centerLeft,
            child: yt.isNotEmpty ? mixTitle('유튜버가 ', '많이 찾은 집', size: 18) : mixTitle('${area.name} ', '인기 많은 집', size: 18)),
        rows: [
          for (var i = 0; i < list.length; i++)
            YtRow(
              place: list[i],
              rank: i + 1,
              onTap: () {
                Navigator.pop(ctx);
                goWhere(list[i]);
              },
            ),
        ],
      ),
    );
  }

  void zoomBy(double d) {
    final cam = map.camera;
    map.move(cam.center, (cam.zoom + d).clamp(6.0, 19.0));
  }

  void openFeats() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            const Text.rich(TextSpan(children: [
              TextSpan(text: '편의 ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: kInk)),
              TextSpan(text: '필터', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kInk)),
            ])),
            const SizedBox(height: 4),
            const Text('고른 것을 모두 갖춘 집만 보여 줍니다 (구글 정보 기준)', style: TextStyle(fontSize: 12, color: kGray)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in const ['park', 'kid', 'group', 'resv', 'take', 'deliv', 'out', 'wheel', 'dog'])
                GestureDetector(
                  onTap: () {
                    setState(() {
                      feats.contains(f) ? feats.remove(f) : feats.add(f);
                      focus = null;
                    });
                    setS(() {});
                  },
                  child: FeatTile(icon: kFeat[f]!.$1, label: kFeat[f]!.$2, color: kFeat[f]!.$3, on: feats.contains(f)),
                ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: _Btn(
                  label: '모두 해제',
                  onTap: () {
                    setState(() {
                      feats.clear();
                      focus = null;
                    });
                    setS(() {});
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _Btn(label: '적용', primary: true, onTap: () => Navigator.pop(ctx))),
            ]),
          ]),
        ),
      ),
    );
  }

  bool regionOpen = false; // 지역 메뉴(머리말 아래로 펼침)
  bool searching = false; // 가게 이름 검색
  String query = '';
  final searchCtl = TextEditingController();

  void openSearch() => setState(() {
        searching = !searching;
        followOn = false;
        focus = null;
        regionOpen = false;
        course = null;
        if (!searching) {
          query = '';
          searchCtl.clear();
        }
      });

  // 검색 결과로 지도 맞추기 (한 곳이면 바로 그 가게 화면)
  void fitResults() {
    final l = visible;
    if (l.isEmpty) return;
    if (l.length == 1) {
      openPlace(l.first);
      return;
    }
    map.fitCamera(CameraFit.coordinates(
      coordinates: [for (final p in l) p.point],
      padding: const EdgeInsets.fromLTRB(60, 220, 60, 60),
      maxZoom: 16,
    ));
  }

  Widget chipsRow() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final k in const [
            ['all', '전체', '🏆'],
            ['near', '내 주변', '📍'],
            ['open', '영업 중', '⏰'],
            ['food', '맛집', '🍽️'],
            ['cafe', '카페', '☕'],
            ['rise', '새로 뜨는 집', '🚀'],
          ])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _Chip(label: k[1], emoji: k[2], on: kind == k[0], onTap: () => pickKind(k[0])),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _Chip(
              label: cuisine.isEmpty ? '음식 종류' : '$cuisine ✕',
              emoji: cuisine.isEmpty ? '🍱' : (kCuisineEmoji[cuisine] ?? '🍱'),
              on: cuisine.isNotEmpty,
              onTap: () {
                if (cuisine.isEmpty) {
                  openCuisine();
                } else {
                  pickCuisine('');
                }
              },
            ),
          ),
          _Chip(label: feats.isEmpty ? '편의 필터' : '편의 필터 ${feats.length}', emoji: '🛎️', on: feats.isNotEmpty, onTap: openFeats),
        ]),
      );

  void openRegion() {
    if (sidos.isEmpty) return;
    setState(() => regionOpen = !regionOpen);
  }

  Iterable<Place> get pool {
    final b = bounds;
    if (b == null) return data?.places ?? const <Place>[];
    final pLat = (b.north - b.south) * 0.25, pLng = (b.east - b.west) * 0.25;
    return loaded.values.expand((d) => d.places).where(
        (p) => p.lat >= b.south - pLat && p.lat <= b.north + pLat && p.lng >= b.west - pLng && p.lng <= b.east + pLng);
  }

  List<Place> get visible {
    if (followOn) return followVisible();
    final cs = course;
    if (cs != null) return cs.stops;
    if (loaded.isEmpty) return [];
    final all = loaded.values.expand((d) => d.places);
    if (query.isNotEmpty) {
      final q = query.replaceAll(' ', '').toLowerCase();
      return all.where((p) => (p.top || p.rise) && p.name.replaceAll(' ', '').toLowerCase().contains(q)).toList()
        ..sort((a, b) => b.score.compareTo(a.score));
    }
    var src = (kind == 'near' ? all : pool).where((p) => kind == 'rise' ? ytRecent(p) : (p.top && p.score > 0));
    if (feats.isNotEmpty) src = src.where((p) => feats.every(p.feat.contains));
    if (cuisine.isNotEmpty) src = src.where((p) => cuisineOf(p) == cuisine);
    if (kind == 'open') src = src.where((p) => openInfo(p)?.open == true);
    if (kind == 'rise') {
      return src.toList()..sort((a, b) => ytLast(b).compareTo(ytLast(a)));
    }
    if (kind == 'food' || kind == 'cafe') src = src.where((p) => p.kind == kind);
    if (kind == 'near') {
      final at = me;
      if (at == null) return [];
      final near = src.where((p) => meters(at, p.point) <= kNearMeters).toList()
        ..sort((a, b) => meters(at, a.point).compareTo(meters(at, b.point)));
      return near.take(kTop).toList();
    }
    // 보이는 범위의 가게는 모두 (동네마다 이미 종류별 상위만 모아 둔 자료)
    return src.toList()..sort((a, b) => b.score.compareTo(a.score));
  }

  // 지도 표시 3단계: 0 = 펼친 카드, 1 = 접힌 카드(사진만), 2 = 작은 아이콘
  // 넓게 보면 카드 5곳부터, 조금만 확대해도 빠르게 늘어난다 (단계는 겹침을 막기 위한 것)
  int get cardCount => zoom < 13.4 ? 5 : (zoom < 14.0 ? 10 : (zoom < 14.6 ? 20 : 999));
  static const kPhotoCount = 7;

  // 순위 높은 집부터 자리를 잡는다. 겹치면 위 → 아래 → 오른쪽 → 왼쪽 자리를 찾아보고,
  // 그래도 없으면 한 단계 작게. 끝까지 확대하면(17.5 이상) 모두 카드로 보인다.
  List<(int, int)> layout(List<Place> list, {int first = -1}) {
    final scale = 256 * math.pow(2, zoom).toDouble();
    Offset px(LatLng p) {
      final x = (p.longitude + 180) / 360 * scale;
      final r = p.latitude * math.pi / 180;
      final y = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * scale;
      return Offset(x, y);
    }
    final kept = <Rect>[];
    final out = List<(int, int)>.filled(list.length, (2, 0));
    // 지금 연 가게(first)가 먼저 자리를 잡는다
    for (final i in [if (first >= 0) first, for (var k = 0; k < list.length; k++) if (k != first) k]) {
      final c = px(list[i].point);
      final want = i == first ? 0 : (i < cardCount ? 0 : (i < cardCount + kPhotoCount ? 1 : 2));
      (int, int)? got;
      for (var t = want; t < 2 && got == null; t++) {
        for (var d = 0; d < 4 && got == null; d++) {
          final r = cardRect(i + 1, t, d, c);
          if (!kept.any((k) => k.overlaps(r))) {
            kept.add(r);
            got = (t, d);
          }
        }
      }
      if (got == null && (zoom >= 17.5 || i == first)) {
        kept.add(cardRect(i + 1, 0, 0, c));
        got = (0, 0);
      }
      out[i] = got ?? (2, 0);
    }
    return out;
  }

  String subText(int total, int cards) {
    final d = data;
    final cs = course;
    if (followOn) {
      final nm = followCh.isEmpty ? '유튜버 따라 먹기' : (follow?.names[followCh] ?? '');
      return zoom < kClusterZoom ? '$nm · 전국 ${commas(followPlaces.length)}곳  ·  확대하면 가게가 보여요' : '$nm · 이 화면 $total곳';
    }
    if (cs != null) return cs.route ? '${cs.name} · ${cs.stops.length}곳을 순서대로 이었어요' : '${cs.name} · ${cs.stops.length}곳';
    if (zoom < kClusterZoom) return '동네별 가게 수  ·  확대하면 가게가 보여요';
    if (d == null) return '맛집 자료를 불러오는 중';
    if (query.isNotEmpty) return total == 0 ? '「$query」 찾는 집이 없습니다' : '「$query」 $total곳';
    if (kind == 'near') {
      if (locating || me == null) return '내 위치를 확인하는 중';
      if (total == 0) return '3km 안에 아직 자료가 있는 집이 없습니다';
      return '내 위치에서 가까운 $total곳  ·  가까운 순';
    }
    if (total == 0) {
      if (feats.isNotEmpty) return '편의 필터에 맞는 집이 없습니다';
      if (cuisine.isNotEmpty) return '이 범위에는 $cuisine 집이 없어요 · 지도를 넓혀 보세요';
      return switch (kind) {
        'rise' => '최근 한 달 안에 유튜버가 다녀간 집이 아직 없습니다',
        'open' => '지금 문 연 집이 없습니다',
        _ => '아직 자료가 없습니다',
      };
    }
    if (kind == 'rise') return '최근 한 달 안에 유튜버가 다녀간 $total곳  ·  최근 영상 순';
    return cards < total ? '$kindLabel 상위 $total곳 · 확대하면 더 보여요' : '$kindLabel 화제 상위 $total곳  ·  ${d.updated} 기준';
  }

  Marker markerFor(Place p, int i, int t, int d, {bool focus = false, bool? numbered}) {
    if (t <= 1) {
      // 1·2단계는 같은 카드: 확대하면 접힌 카드가 펼쳐진다
      final w = cardFullW(i + 1), ch = cardImg(i + 1) + 12;
      final side = d >= 2;
      return Marker(
        key: ValueKey('card${p.id}'),
        point: p.point,
        width: side ? w + 6 : w,
        height: side ? ch : ch + 6,
        alignment: const [Alignment.topCenter, Alignment.bottomCenter, Alignment.centerRight, Alignment.centerLeft][d],
        child: PlaceMarker(place: p, rank: i + 1, open: t == 0 || focus, dir: d, numbered: numbered ?? !followOn, focus: focus, onTap: () => openPlace(p)),
      );
    }
    return Marker(
      key: ValueKey('icon${p.id}'),
      point: p.point,
      width: 30,
      height: 32,
      alignment: Alignment.topCenter,
      child: IconMarker(place: p, onTap: () => openPlace(p)),
    );
  }

  void openPlace(Place p) {
    noteRecent(p);
    // 처음엔 낮게: 이름 · 별점·거리·영업·주소 + 오른쪽 바로가기 (+ 편의 한 줄) 까지만, 끌어올리면 끝까지
    final mq = MediaQuery.of(context);
    final px = 238.0 + (oneLine(p).isNotEmpty ? 24 : 0) + (p.feat.any(kFeat.containsKey) ? 38 : 0) + mq.padding.bottom;
    final peek = (px / mq.size.height).clamp(0.26, 0.6).toDouble();
    // 그 집이 아래 창에 가리지 않게: 위 머리말과 아래 창 사이 가운데쯤 오도록 지도를 옮긴다
    final z = math.max(map.camera.zoom, 16.0);
    final mid = (mq.size.height - 68 - mq.padding.bottom) / 2; // 지도 가운데 (아래 탭 위)
    final want = (mq.padding.top + 130 + mq.size.height * (1 - peek)) / 2 + 30; // 카드는 점 위에 그려지니 조금 아래
    map.move(shiftDown(p.point, z, mid - want), z);
    setState(() => focus = p);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (_) => PlaceSheet(place: p, recentDays: data?.recentDays ?? 90, kok: isKok(p), onKok: (v) => toggleKok(p, v), peek: peek),
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
                  TextSpan(text: kind == 'near' ? '내 주변 ' : '${area.name} $kindLabel ', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: kInk)),
                  TextSpan(text: kind == 'near' ? '가까운 순' : '화제 순위', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kInk)),
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
                    child: Text('$i', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: i <= 3 ? kPointText : kGray)),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: kInk))),
                        if (p.tv.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.live_tv_outlined, size: 13, color: kInk),
                          const SizedBox(width: 2),
                          const Text('방송', style: TextStyle(fontSize: 11, color: kInk)),
                        ],
                      ]),
                      const SizedBox(height: 2),
                      Builder(builder: (_) {
                        final o = openInfo(p);
                        return Text.rich(
                          TextSpan(children: [
                            if (kind == 'near' && me != null)
                              TextSpan(text: '${distText(meters(me!, p.point))}  ·  ', style: const TextStyle(fontWeight: FontWeight.w600, color: kInk)),
                            if (kind == 'rise' && ytLast(p).isNotEmpty)
                              TextSpan(text: '${mdText(ytLast(p))} 영상  ·  ', style: const TextStyle(fontWeight: FontWeight.w600, color: kPointText)),
                            if (kind != 'food' && kind != 'cafe')
                              TextSpan(
                                text: p.kind == 'cafe' ? '카페  ·  ' : '맛집  ·  ',
                                style: TextStyle(fontWeight: FontWeight.w600, color: kindTint(p.kind)),
                              ),
                            if (o != null)
                              TextSpan(text: '${o.short}  ·  ', style: TextStyle(fontWeight: FontWeight.w600, color: o.open ? kPointText : kGray)),
                            TextSpan(text: '${p.cat}${p.greviews > 0 ? '  ·  ★${p.grate.toStringAsFixed(1)} (${commas(p.greviews)})' : ''}  ·  블로그 ${p.blog}'),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: kGray),
                        );
                      }),
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
    final panel = RegionPanel(
      sidos: sidos,
      current: area,
      onPick: setArea,
      onNear: () {
        setState(() {
          regionOpen = false;
          tab = 2;
        });
        pickKind('near');
      },
    );
    void toMapSearch() => setState(() {
          followOn = false;
          focus = null;
          tab = 2;
          regionOpen = false;
          searching = true;
        });
    return Scaffold(
      body: IndexedStack(index: tab, children: [
        HomeView(
          onRefresh: pullRefresh,
          active: tab == 0,
          banners: remote?.banners ?? const [],
          order: remote?.order ?? kHomeOrder,
          onBanner: openBanner,
          data: data,
          error: error,
          area: area,
          regionOpen: regionOpen && tab == 0,
          regionPanel: panel,
          onRegion: openRegion,
          onSearch: toMapSearch,
          onRetry: _load,
          onRoulette: openRoulette,
          onCuisine: goCuisine,
          onWhere: goWhere,
          onChannel: openChannel,
          onCourse: openCourse,
          onAllChannels: openAllChannels,
          onRankAll: openYtRank,
          follow: follow,
          onFollow: openFollow,
          onFollowPlace: openFollowPlace,
        ),
        VideoView(
          onRefresh: pullRefresh,
          data: data,
          area: area,
          regionOpen: regionOpen && tab == 1,
          regionPanel: panel,
          onRegion: openRegion,
          onSearch: toMapSearch,
          onWhere: goWhere,
        ),
        _mapTab(context),
        SavedView(
          onRefresh: pullRefresh,
          koks: koks,
          recents: recents,
          onOpen: openKok,
          onRemove: (k) {
            setState(() => koks.removeWhere((x) => x['id'] == k['id']));
            _kokChanged();
          },
          onRemoveRecent: (k) {
            setState(() => recents.removeWhere((x) => x['id'] == k['id']));
            _saveList('recents', recents);
          },
          onClearRecents: () {
            setState(() => recents.clear());
            _saveList('recents', recents);
          },
        ),
      ]),
      bottomNavigationBar: KokNav(
        tab: tab,
        onTap: (i) => setState(() {
          tab = i;
          regionOpen = false;
        }),
        onCenter: openRoulette,
      ),
    );
  }

  Widget _mapTab(BuildContext context) {
    final base = visible;
    // 지금 연 가게: 순위가 낮거나 지금 분류에 없어도 큰 카드로, 맨 위에 (번호는 원래 순위, 목록에 없으면 번호 없이)
    final f = focus;
    var fi = f == null ? -1 : base.indexWhere((x) => x.id == f.id);
    final extra = f != null && fi < 0 && course == null;
    final list = extra ? [...base, f!] : base;
    if (extra) fi = list.length - 1;
    final wide = MediaQuery.of(context).size.width >= 760; // 넓은 화면: 분류 단추를 머리말 오른쪽에
    final place = layout(list, first: fi);
    final cards = place.where((x) => x.$1 == 0).length;
    // 작은 것부터 깔고 큰 카드를 위에 (같은 단계는 높은 순위가 위), 지금 연 가게는 맨 위
    final order = [
      for (final t in const [2, 1, 0])
        for (var i = list.length - 1; i >= 0; i--)
          if (place[i].$1 == t) i
    ];
    if (fi >= 0) {
      order.remove(fi);
      order.add(fi);
    }
    return Stack(children: [
        FlutterMap(
          mapController: map,
          options: MapOptions(
            initialCenter: kDefaultArea.center,
            initialZoom: 13,
            minZoom: 6,
            maxZoom: 19,
            // 두 손가락에 지도가 돌아가지 않게 (맛집 지도는 늘 북쪽이 위)
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onPositionChanged: (camera, hasGesture) {
              if ((camera.zoom - zoom).abs() >= 0.05) setState(() => zoom = camera.zoom);
              _sync?.cancel();
              _sync = Timer(const Duration(milliseconds: 250), () => _syncView(camera));
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'kr.designfeel.df_app_lab',
            ),
            if (course != null && course!.route)
              PolylineLayer(polylines: [
                Polyline(
                  points: [for (final p in course!.stops) p.point],
                  color: kAccent,
                  strokeWidth: 3,
                  pattern: StrokePattern.dashed(segments: const [10, 7]),
                ),
              ]),
            MarkerLayer(
              markers: [
                // 넓게 보면 동네별 숫자 묶음, 확대하면 가게 하나하나 (코스는 늘 가게로)
                if (zoom < kClusterZoom && course == null)
                  ...(followOn ? followClusters() : clusterMarkers())
                else
                  for (final i in order) markerFor(list[i], i, place[i].$1, place[i].$2, focus: i == fi, numbered: extra && i == fi ? false : null),
                if (me != null)
                  Marker(
                    key: const ValueKey('me'),
                    point: me!,
                    width: 22,
                    height: 22,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6)],
                      ),
                      child: Container(decoration: const BoxDecoration(color: kGps, shape: BoxShape.circle)),
                    ),
                  ),
              ],
            ),
          ],
        ),
        if (regionOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => regionOpen = false),
              child: const SizedBox.expand(),
            ),
          ),
        // 위쪽 머리말
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Header(
                data: data,
                area: area,
                here: followOn ? here : '',
                open: regionOpen,
                onRegion: openRegion,
                sub: subText(base.length, cards),
                onRank: data == null ? null : openRank,
                onSearch: openSearch,
                searching: searching,
                middle: (wide && !regionOpen && !searching && course == null && !followOn) ? chipsRow() : null,
              ),
              const SizedBox(height: 8),
              if (searching)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.only(left: 14, right: 4),
                  decoration: _card(),
                  child: Row(children: [
                    const Icon(Icons.search_rounded, size: 20, color: kGray),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: searchCtl,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(fontSize: 14.5, color: kInk),
                        decoration: const InputDecoration(
                          hintText: '가게 이름으로 찾기',
                          hintStyle: TextStyle(fontSize: 14.5, color: kGray),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                        onChanged: (v) => setState(() => query = v.trim()),
                        onSubmitted: (_) => fitResults(),
                      ),
                    ),
                    IconButton(onPressed: openSearch, icon: const Icon(Icons.close_rounded, color: kInk, size: 20)),
                  ]),
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !regionOpen
                    ? const SizedBox(width: double.infinity)
                    : RegionPanel(
                        sidos: sidos,
                        current: area,
                        onPick: setArea,
                        onNear: () {
                          setState(() => regionOpen = false);
                          pickKind('near');
                        },
                      ),
              ),
              if (!regionOpen && !searching && followOn && follow != null)
                FollowBar(follow: follow!, current: followCh, onPick: openFollow, onClose: closeFollow)
              else if (!regionOpen && !searching && course != null)
                CourseBar(course: course!, onList: () => openCourseSheet(course!), onClose: () => setState(() => course = null))
              else if (!regionOpen && !searching && !wide)
                chipsRow(),
            ]),
          ),
        ),
        if (data == null && zoom >= kClusterZoom && course == null && !followOn)
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
        if (data != null && !followOn && feats.isEmpty && kind == 'rise' && base.isEmpty)
          Center(
            child: Container(
              margin: const EdgeInsets.all(30),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              decoration: _card(),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                    '최근 한 달 안에 유튜버가 다녀간 집이 아직 없습니다',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kInk)),
                const SizedBox(height: 4),
                const Text('새 영상이 올라오면 매일 저녁 여기에 보입니다.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: kGray, height: 1.4)),
              ]),
            ),
          ),
        Positioned(
          right: 12,
          bottom: 30,
          child: Container(
            decoration: _card(r: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _ZoomBtn(plus: true, onTap: () => zoomBy(1)),
              Container(width: 42, height: 1, color: kLine),
              _ZoomBtn(plus: false, onTap: () => zoomBy(-1)),
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
      ]);
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
  final Area area;
  final String here; // 비어 있지 않으면 동네 이름 대신 (따라가기 중 지금 보는 곳)
  final bool open;
  final VoidCallback onRegion;
  final String sub;
  final VoidCallback? onRank;
  final VoidCallback onSearch;
  final bool searching;
  final Widget? middle;
  const _Header({
    required this.data,
    required this.area,
    this.here = '',
    required this.open,
    required this.onRegion,
    required this.sub,
    required this.onRank,
    required this.onSearch,
    required this.searching,
    this.middle,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final inline = w >= 600; // 넓으면 설명 글을 지역 이름 오른쪽에
    final region = GestureDetector(
      onTap: onRegion,
      behavior: HitTestBehavior.opaque,
      child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
        // 네모 지역 단추 (열리면 ✕)
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: kRegion, borderRadius: BorderRadius.circular(10)),
          child: open ? const _XGlyph(size: 16) : const PinGlyph(size: 24, color: Colors.white, bg: kRegion),
        ),
        const SizedBox(width: 10),
        Text(here.isNotEmpty ? (here.contains(' ') ? '${here.split(' ').first} ' : '') : '${area.sido} ',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: kInk)),
        Flexible(
          child: Text(here.isNotEmpty ? (here.contains(' ') ? here.substring(here.indexOf(' ') + 1) : here) : area.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk)),
        ),
        Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 28, color: kInk),
      ]),
    );
    final subText = Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: kGray));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (!inline) Expanded(child: Align(alignment: Alignment.centerLeft, child: region)) else Flexible(child: region),
          if (inline && middle == null) ...[const SizedBox(width: 16), Expanded(child: subText)],
          if (inline && middle != null) ...[const SizedBox(width: 16), Flexible(flex: 0, child: subText)],
        if (middle != null) ...[const SizedBox(width: 18), Expanded(child: middle!)],
        const SizedBox(width: 8),
        // 가게 이름 검색
        InkWell(
          onTap: onSearch,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: searching ? kDark : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: searching ? kDark : kLine, width: 1),
            ),
            child: Icon(Icons.search_rounded, size: 21, color: searching ? Colors.white : kInk),
          ),
        ),
        const SizedBox(width: 6),
        TextButton(
          onPressed: onRank,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: kPoint,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('순위', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
        ]),
        if (!inline) Padding(padding: const EdgeInsets.only(top: 6, left: 2), child: subText),
      ]),
    );
  }
}

// 직접 그린 ✕ (지역 메뉴 닫기)
class _XGlyph extends StatelessWidget {
  final double size;
  const _XGlyph({required this.size});
  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: math.pi / 4,
        child: Stack(alignment: Alignment.center, children: [
          Container(width: size * 1.25, height: 2, color: Colors.white),
          Container(width: 2, height: size * 1.25, color: Colors.white),
        ]),
      );
}

// 지역 고르기: 왼쪽 시·도 목록, 오른쪽에 그 시·도의 동네 목록 (머리말 아래로 펼침)
class RegionPanel extends StatefulWidget {
  final List<Sido> sidos;
  final Area current;
  final ValueChanged<Area> onPick;
  final VoidCallback onNear;
  const RegionPanel({super.key, required this.sidos, required this.current, required this.onPick, required this.onNear});
  @override
  State<RegionPanel> createState() => _RegionPanelState();
}

class _RegionPanelState extends State<RegionPanel> {
  late String sel = widget.current.sido;
  static const kSide = Color(0xFFF3F5F8);
  static const kOff = Color(0xFFA9AEB8);
  static const kSoft = Color(0xFFC9C0BA); // 진한 먹색 위의 흐린 글

  @override
  Widget build(BuildContext context) {
    final cur = widget.sidos.where((x) => x.name == sel).firstOrNull ?? widget.sidos.first;
    final h = math.min(MediaQuery.of(context).size.height * 0.6, 460.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: _card(),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
          child: Row(children: [
            const Text.rich(TextSpan(children: [
              TextSpan(text: '전국 ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: kInk)),
              TextSpan(text: '지역 선택', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
            ])),
            const Spacer(),
            InkWell(
              onTap: widget.onNear,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(9, 6, 12, 6),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: kLine, width: 1)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.near_me_rounded, size: 15, color: kPoint),
                  SizedBox(width: 4),
                  Text('내 주변으로', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kInk)),
                ]),
              ),
            ),
          ]),
        ),
        const Divider(height: 1, thickness: 1, color: kLine),
        SizedBox(
          height: h,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // 시·도
            Container(
              width: 96,
              color: kSide,
              child: ListView(padding: const EdgeInsets.symmetric(vertical: 6), children: [
                for (final x in widget.sidos)
                  InkWell(
                    onTap: () => setState(() => sel = x.name),
                    child: Container(
                      height: 46,
                      color: x.name == cur.name ? kRegion : Colors.transparent,
                      padding: const EdgeInsets.only(left: 18),
                      alignment: Alignment.centerLeft,
                      child: Row(children: [
                        Text(x.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: x.name == cur.name ? FontWeight.w700 : FontWeight.w600,
                              color: x.name == cur.name ? Colors.white : (x.ready ? kInk : kOff),
                            )),
                        if (x.ready) ...[
                          const SizedBox(width: 5),
                          Container(width: 5, height: 5, decoration: const BoxDecoration(color: kFoodTint, shape: BoxShape.circle)),
                        ],
                      ]),
                    ),
                  ),
              ]),
            ),
            // 동네
            Expanded(
              child: Container(
                color: kRegion,
                child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 10, 12), children: [
                  SizedBox(
                    height: 44,
                    child: Row(children: [
                      Text(cur.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                      const SizedBox(width: 8),
                      Text(cur.ready ? '${cur.areas.where((a) => a.ready).length}곳 이용 가능' : '준비 중',
                          style: const TextStyle(fontSize: 12, color: kSoft)),
                    ]),
                  ),
                  Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
                  if (cur.areas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('준비 중입니다. 인천부터 차례로 넓혀 갑니다.', style: TextStyle(fontSize: 13.5, color: kSoft, height: 1.5)),
                    )
                  else
                    for (final a in cur.areas) _areaRow(a),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _areaRow(Area a) {
    final ok = a.ready;
    final on = a.id == widget.current.id;
    return InkWell(
      onTap: ok ? () => widget.onPick(a) : null,
      child: SizedBox(
        height: 46,
        child: Row(children: [
          Flexible(
            child: Text(a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: on ? FontWeight.w700 : FontWeight.w400, color: ok ? Colors.white : kSoft.withValues(alpha: 0.7))),
          ),
          if (on) ...[const SizedBox(width: 6), const Icon(Icons.check_rounded, size: 17, color: Colors.white)],
          if (!ok) ...[const SizedBox(width: 8), Text('준비 중', style: TextStyle(fontSize: 11.5, color: kSoft.withValues(alpha: 0.7)))],
          const Spacer(),
          if (ok) const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.white),
        ]),
      ),
    );
  }
}

// 지도 확대(+)·축소(−) 단추
class _ZoomBtn extends StatelessWidget {
  final bool plus;
  final VoidCallback onTap;
  const _ZoomBtn({required this.plus, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 42,
        height: 42,
        child: Stack(alignment: Alignment.center, children: [
          Container(width: 15, height: 2, decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(1))),
          if (plus) Container(width: 2, height: 15, decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(1))),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  final String emoji; // 앞에 붙는 색 그림 (작은 단추도 재미있게)
  const _Chip({required this.label, required this.on, required this.onTap, this.emoji = ''});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.fromLTRB(emoji.isEmpty ? 14 : 11, 6, 14, 6),
        decoration: BoxDecoration(
          color: on ? kInk : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? kInk : kLine, width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (emoji.isNotEmpty) ...[Text(emoji, style: const TextStyle(fontSize: 15, height: 1.1)), const SizedBox(width: 5)],
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? Colors.white : kInk)),
        ]),
      ),
    );
  }
}

String commas(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

// 카드 크기 (지도 겹침 계산에도 씀)
// 카드 사진은 유튜브 표지 비율(16:9) 그대로 — 자르지 않는다
double cardImg(int rank) => rank <= 3 ? 43.0 : 36.0; // 사진 높이
double cardImgW(int rank) => rank <= 3 ? 76.0 : 64.0; // 사진 너비
double cardFullW(int rank) => rank <= 3 ? 196.0 : 170.0;
double cardShutW(int rank) => cardImgW(rank) + 12; // 사진 + 안쪽 여백 5×2 + 테두리 1×2
double cardH(int rank) => cardImg(rank) + 12 + 6; // 카드 + 꼬리

// 자리(d): 0 가게 위, 1 가게 아래, 2 가게 오른쪽, 3 가게 왼쪽
Rect cardRect(int rank, int t, int d, Offset c) {
  final w = t == 0 ? cardFullW(rank) : cardShutW(rank);
  final ch = cardImg(rank) + 12;
  const tail = 6.0;
  final r = switch (d) {
    0 => Rect.fromLTWH(c.dx - w / 2, c.dy - ch - tail, w, ch + tail),
    1 => Rect.fromLTWH(c.dx - w / 2, c.dy, w, ch + tail),
    2 => Rect.fromLTWH(c.dx, c.dy - ch / 2, w + tail, ch),
    _ => Rect.fromLTWH(c.dx - w - tail, c.dy - ch / 2, w + tail, ch),
  };
  return r.inflate(t == 0 ? 3 : 1);
}

// 1·2단계 카드: 접히면 왼쪽 사진만, 펼치면 오른쪽 이름·별점까지 (확대하면 양옆으로 벌어짐)
class PlaceMarker extends StatelessWidget {
  final Place place;
  final int rank;
  final bool open;
  final int dir; // 0 가게 위, 1 아래, 2 오른쪽, 3 왼쪽
  final VoidCallback onTap;
  final bool numbered; // 순위 번호 (따라가기 지도는 순위가 아니라 번호 없이)
  final bool focus; // 지금 연 가게: 빨간 바탕 + 흰 글
  const PlaceMarker({super.key, required this.place, required this.rank, required this.open, this.dir = 0, this.numbered = true, this.focus = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final big = rank <= 3;
    final img = cardImg(rank);
    final inner = cardFullW(rank) - 12;
    final line = kindLine(place.kind); // 맛집 빨강, 카페 짙은 갈색
    final thumb = thumbOf(place);
    final card = Stack(clipBehavior: Clip.none, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            width: open ? cardFullW(rank) : cardShutW(rank),
            height: img + 12,
            padding: const EdgeInsets.all(5),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: focus ? kAccent : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: focus ? kAccent : line, width: 1),
              boxShadow: [focus ? BoxShadow(color: kAccent.withValues(alpha: 0.45), blurRadius: 16, spreadRadius: 1) : BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10)],
            ),
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: inner,
              maxWidth: inner,
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: cardImgW(rank),
                    height: img,
                    child: thumb.isEmpty
                        ? kindFill(place.kind, img * 0.66)
                        : Image.network(
                            thumb,
                            fit: BoxFit.cover,
                            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                            errorBuilder: (_, __, ___) => kindFill(place.kind, img * 0.66),
                          ),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text.rich(
                      TextSpan(children: [
                        if (numbered)
                          TextSpan(
                              text: '$rank ',
                              style: TextStyle(fontSize: big ? 12 : 11, fontWeight: FontWeight.w700, color: focus ? Colors.white : (big ? kindLine(place.kind) : kGray))),
                        if (place.tv.isNotEmpty)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(padding: const EdgeInsets.only(right: 3), child: Icon(Icons.live_tv_outlined, size: 12, color: focus ? Colors.white : kInk)),
                          ),
                        TextSpan(text: place.name, style: TextStyle(fontSize: big ? 12 : 11, fontWeight: FontWeight.w700, color: focus ? Colors.white : kInk)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    if (place.greviews > 0)
                      Text.rich(TextSpan(children: [
                        TextSpan(text: '★ ', style: TextStyle(fontSize: 10.5, color: focus ? Colors.white : const Color(0xFFF5A623))),
                        TextSpan(text: place.grate.toStringAsFixed(1), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: focus ? Colors.white : kInk)),
                        TextSpan(text: ' · 리뷰 ${commas(place.greviews)}', style: TextStyle(fontSize: 10, color: focus ? Colors.white.withValues(alpha: 0.85) : kGray)),
                      ]), maxLines: 1)
                    else
                      Text(place.cat, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: focus ? Colors.white.withValues(alpha: 0.85) : kGray)),
                  ]),
                ),
              ]),
            ),
          ),
          // 접혀 있을 때는 이름이 안 보이니 방송 표시를 모서리에
          if (place.tv.isNotEmpty)
            Positioned(
              right: -5,
              top: -5,
              child: AnimatedOpacity(opacity: open ? 0 : 1, duration: const Duration(milliseconds: 200), child: const TvBadge()),
            ),
        ]);
    // 꼬리: 가게 위치를 가리킨다 (기본 그림은 아래쪽 뾰족)
    Widget tail(int turns, Offset nudge) =>
        Transform.translate(offset: nudge, child: RotatedBox(quarterTurns: turns, child: CustomPaint(size: const Size(12, 6), painter: _Tail(focus ? kAccent : line, fill: focus ? kAccent : Colors.white))));
    final Widget body = switch (dir) {
      1 => Column(mainAxisAlignment: MainAxisAlignment.start, children: [tail(2, const Offset(0, 1)), card]),
      2 => Row(mainAxisAlignment: MainAxisAlignment.start, children: [tail(1, const Offset(1, 0)), card]),
      3 => Row(mainAxisAlignment: MainAxisAlignment.end, children: [card, tail(3, const Offset(-1, 0))]),
      _ => Column(mainAxisAlignment: MainAxisAlignment.end, children: [card, tail(0, const Offset(0, -1))]),
    };
    return GestureDetector(onTap: onTap, child: body);
  }
}

// 편의 정보: 코드 → (아이콘, 이름, 색) — 둥근 사각형 칸에 색 아이콘
const kFeat = <String, (IconData, String, Color)>{
  'park': (Icons.local_parking_rounded, '주차', Color(0xFF2F6BFF)),
  'dog': (Icons.pets_rounded, '애견 동반', Color(0xFFF08A24)),
  'kid': (Icons.child_care_rounded, '아이 동반', Color(0xFFE8558A)),
  'resv': (Icons.event_available_rounded, '예약', Color(0xFF7A5AF8)),
  'take': (Icons.takeout_dining_rounded, '포장', Color(0xFFD9930D)),
  'deliv': (Icons.delivery_dining_rounded, '배달', Color(0xFFE5484D)),
  'out': (Icons.deck_rounded, '야외석', Color(0xFF1BA3C6)),
  'group': (Icons.groups_rounded, '단체석', Color(0xFF5B6B86)),
  'wheel': (Icons.accessible_rounded, '휠체어', Color(0xFF2F6BFF)),
};

// 가게 화면의 편의 정보: 작은 무채색 아이콘 한 줄 (자리가 모자라면 글 없이 아이콘만, 길게 누르면 이름)
class FeatRow extends StatelessWidget {
  final Iterable<String> feats;
  const FeatRow(this.feats, {super.key});
  static const _line = Color(0xFFE8EAEE), _icon = Color(0xFF8B919B), _text = Color(0xFF5F6670);
  @override
  Widget build(BuildContext context) {
    final items = [for (final f in feats) if (kFeat[f] != null) kFeat[f]!];
    return LayoutBuilder(builder: (_, c) {
      // 글까지 넣었을 때 너비 (넉넉히 셈): 아이콘 14 + 사이 3 + 글자 11 + 안쪽 여백 16 + 테두리 2, 칸 사이 6
      final need = items.fold<double>(0, (s, it) => s + 35 + it.$2.length * 11.0) + 6.0 * (items.length - 1);
      final withText = need <= c.maxWidth;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Row(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Tooltip(
              message: items[i].$2,
              child: Semantics(
                label: items[i].$2,
                excludeSemantics: true,
                child: Container(
                  height: 26,
                  padding: EdgeInsets.symmetric(horizontal: withText ? 9 : 6),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(13), border: Border.all(color: _line, width: 1)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(items[i].$1, size: 14, color: _icon),
                    if (withText) ...[
                      const SizedBox(width: 3),
                      Text(items[i].$2, maxLines: 1, style: const TextStyle(fontSize: 11.5, color: _text, height: 1.1)),
                    ],
                  ]),
                ),
              ),
            ),
          ],
        ]),
      );
    });
  }
}

class FeatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool on;
  const FeatTile({super.key, required this.icon, required this.label, required this.color, this.on = true});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: on ? color.withValues(alpha: 0.10) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: on ? color.withValues(alpha: 0.55) : kLine, width: 1),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 25, color: on ? color : const Color(0xFFB0B5BF)),
        const SizedBox(height: 4),
        Text(label, maxLines: 1, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: kInk, height: 1.1)),
      ]),
    );
  }
}

const kFoodTint = Color(0xFFE53935); // 맛집: 빨강
const kCafeTint = Color(0xFF8A5A33); // 카페: 밝은 갈색 (커피색)
const kLineBrown = Color(0xFF5C3A21); // 카페 카드 테두리·꼬리: 짙은 갈색

IconData kindIcon(String kind) => kind == 'cafe' ? Icons.local_cafe_outlined : Icons.restaurant_outlined;
Color kindTint(String kind) => kind == 'cafe' ? kCafeTint : kFoodTint;
// 카드 테두리: 맛집 빨강, 카페 짙은 갈색 (전체 보기에서 한눈에 구분)
Color kindLine(String kind) => kind == 'cafe' ? kLineBrown : kFoodTint;

IconData kindIconFilled(String kind) => kind == 'cafe' ? Icons.local_cafe : Icons.restaurant;

// 색을 채운 동그라미 + 흰 그림 (사진이 없을 때)
Widget kindFill(String kind, double size) => Container(
      color: kindTint(kind),
      alignment: Alignment.center,
      child: KindGlyph(kind: kind, size: size, bg: kindTint(kind)),
    );

// 직접 그린 위치 표시 (지역 단추)
class PinGlyph extends StatelessWidget {
  final double size;
  final Color color, bg;
  const PinGlyph({super.key, required this.size, required this.color, required this.bg});
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _PinPainter(color, bg));
}

class _PinPainter extends CustomPainter {
  final Color color, bg;
  _PinPainter(this.color, this.bg);
  @override
  void paint(Canvas c, Size s) {
    final k = s.width / 24;
    final p = Paint()
      ..color = color
      ..isAntiAlias = true;
    final pin = ui.Path()
      ..moveTo(12 * k, 22.5 * k)
      ..cubicTo(7 * k, 16.5 * k, 4.5 * k, 13 * k, 4.5 * k, 9.5 * k)
      ..arcToPoint(Offset(19.5 * k, 9.5 * k), radius: Radius.circular(7.5 * k))
      ..cubicTo(19.5 * k, 13 * k, 17 * k, 16.5 * k, 12 * k, 22.5 * k)
      ..close();
    c.drawPath(pin, p);
    c.drawCircle(Offset(12 * k, 9.5 * k), 2.8 * k, Paint()..color = bg);
  }

  @override
  bool shouldRepaint(covariant _PinPainter o) => o.color != color || o.bg != bg;
}

// 직접 그린 그림: 맛집은 요리사 모자, 카페는 원두
class KindGlyph extends StatelessWidget {
  final String kind;
  final double size;
  final Color color, bg;
  const KindGlyph({super.key, required this.kind, required this.size, this.color = Colors.white, required this.bg});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: kind == 'cafe' ? _BeanPainter(color, bg) : _ChefHatPainter(color, bg));
}

class _ChefHatPainter extends CustomPainter {
  final Color color, bg;
  _ChefHatPainter(this.color, this.bg);
  @override
  void paint(Canvas c, Size s) {
    final k = s.width / 24;
    final p = Paint()
      ..color = color
      ..isAntiAlias = true;
    // 위쪽 몽실한 부분 (둥근 세 덩이)
    c.drawCircle(Offset(7.2 * k, 10.2 * k), 4.5 * k, p);
    c.drawCircle(Offset(12 * k, 7.4 * k), 5.3 * k, p);
    c.drawCircle(Offset(16.8 * k, 10.2 * k), 4.5 * k, p);
    // 몸통
    c.drawRect(Rect.fromLTRB(7.4 * k, 10.2 * k, 16.6 * k, 16.8 * k), p);
    // 주름 두 줄
    final pleat = Paint()
      ..color = bg
      ..strokeWidth = 1.0 * k
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    c.drawLine(Offset(10.4 * k, 12.6 * k), Offset(10.4 * k, 16.2 * k), pleat);
    c.drawLine(Offset(13.6 * k, 12.6 * k), Offset(13.6 * k, 16.2 * k), pleat);
    // 아래 띠 (몸통과 살짝 띄움)
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(7.4 * k, 17.8 * k, 16.6 * k, 20.8 * k), Radius.circular(1 * k)), p);
  }

  @override
  bool shouldRepaint(covariant _ChefHatPainter o) => o.color != color || o.bg != bg;
}

class _BeanPainter extends CustomPainter {
  final Color color, bg;
  _BeanPainter(this.color, this.bg);
  @override
  void paint(Canvas c, Size s) {
    final k = s.width / 24;
    c.save();
    c.translate(12 * k, 12 * k);
    c.rotate(-0.6); // 비스듬히 누운 원두
    c.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 12.6 * k, height: 18.4 * k),
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
    // 가운데 갈라진 홈 (S자)
    final groove = ui.Path()
      ..moveTo(0, -8.4 * k)
      ..cubicTo(-3.4 * k, -3 * k, 3.4 * k, 3 * k, 0, 8.4 * k);
    c.drawPath(
      groove,
      Paint()
        ..color = bg
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8 * k
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _BeanPainter o) => o.color != color || o.bg != bg;
}
String thumbOf(Place p) => p.vids.isNotEmpty ? 'https://i.ytimg.com/vi/${p.vids.first.id}/mqdefault.jpg' : '';

// 방송 출연 표시 (진한 회색, 작게)
class TvBadge extends StatelessWidget {
  const TvBadge({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: kLine, width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 4)],
      ),
      child: const Icon(Icons.live_tv_outlined, size: 11, color: kInk),
    );
  }
}

// 3단계: 작은 맛집·카페 아이콘 (숫자 없이 자리만)
class IconMarker extends StatelessWidget {
  final Place place;
  final VoidCallback onTap;
  const IconMarker({super.key, required this.place, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.max, mainAxisAlignment: MainAxisAlignment.end, children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: kindTint(place.kind),
            borderRadius: BorderRadius.circular(7),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 6)],
          ),
          child: KindGlyph(kind: place.kind, size: 18, bg: kindTint(place.kind)),
        ),
        Transform.translate(
          offset: const Offset(0, -1.5),
          child: CustomPaint(size: const Size(8, 5), painter: _Tail(kindTint(place.kind), fill: kindTint(place.kind))),
        ),
      ]),
    );
  }
}

class _Tail extends CustomPainter {
  final Color line, fill;
  _Tail(this.line, {this.fill = Colors.white});
  @override
  void paint(Canvas c, Size s) {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(s.width / 2, s.height)
      ..lineTo(s.width, 0)
      ..close();
    c.drawPath(path, Paint()..color = fill);
    c.drawLine(Offset(0, 0), Offset(s.width / 2, s.height), Paint()..color = line..strokeWidth = 1);
    c.drawLine(Offset(s.width, 0), Offset(s.width / 2, s.height), Paint()..color = line..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _Tail old) => old.line != line || old.fill != fill;
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
        border: Border.all(color: score >= 50 ? kPoint : kLine, width: 1),
      ),
      child: Text.rich(TextSpan(children: [
        const TextSpan(text: '화제 ', style: TextStyle(fontSize: 11, color: kGray)),
        TextSpan(text: '$score', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: score >= 50 ? kPointText : kInk)),
      ])),
    );
  }
}

// ---------------- 아래에서 올라오는 판 ----------------

class _Sheet extends StatefulWidget {
  final double initial;
  final List<double>? snaps; // 걸리는 높이 (있으면 낮게 → 끝까지 두 단계, 아래로 내리면 닫힘)
  final Widget Function(ScrollController) builder;
  const _Sheet({required this.initial, required this.builder, this.snaps});
  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  bool closing = false;
  @override
  Widget build(BuildContext context) {
    final snaps = widget.snaps;
    final min = snaps == null ? 0.25 : 0.08;
    final sheet = DraggableScrollableSheet(
      initialChildSize: widget.initial,
      minChildSize: min,
      maxChildSize: 0.92,
      snap: snaps != null,
      snapSizes: snaps,
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
          Expanded(child: widget.builder(scroll)),
        ]),
      ),
    );
    if (snaps == null) return sheet;
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        if (!closing && n.extent <= n.minExtent + 0.015) {
          closing = true;
          Navigator.of(context).maybePop();
        }
        return false;
      },
      child: sheet,
    );
  }
}

class PlaceSheet extends StatelessWidget {
  final Place place;
  final int recentDays;
  final bool kok;
  final ValueChanged<bool>? onKok;
  final double peek; // 처음 열리는 높이 (화면 비율)
  const PlaceSheet({super.key, required this.place, required this.recentDays, this.kok = false, this.onKok, this.peek = 0.36});

  @override
  Widget build(BuildContext context) {
    final p = place;
    final naver = 'https://map.naver.com/p/search/${Uri.encodeComponent(p.name)}';
    // 길찾기: 카카오맵 길안내 (도착지 = 이 가게)
    final route = 'https://map.kakao.com/link/to/${Uri.encodeComponent(p.name)},${p.lat},${p.lng}';
    final open = openInfo(p);
    final today = '${kDays[nowKst().weekday % 7]}요일';
    // 오른쪽 바로가기 (요약 옆 빈자리): 전화 · 길찾기 · 메뉴 · 블로그
    final quick = <Widget>[
      if (p.tel.isNotEmpty) _Quick(icon: Icons.call_outlined, label: '전화', strong: true, onTap: () => openUrl('tel:${p.tel}')),
      _Quick(icon: Icons.directions_outlined, label: '길찾기', onTap: () => openUrl(route)),
      _Quick(icon: Icons.photo_library_outlined, label: '메뉴', onTap: () => openUrl(p.kakao.isNotEmpty ? p.kakao : naver)),
      if (p.home.isNotEmpty) _Quick(icon: Icons.public, label: p.home.contains('blog') ? '블로그' : '홈페이지', onTap: () => openUrl(p.home)),
    ];
    return _Sheet(
      initial: peek,
      snaps: [peek],
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
                if (oneLine(p).isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(oneLine(p), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kInk, height: 1.35)),
                ],
              ]),
            ),
            if (p.score > 0) ScoreTag(score: p.score),
            if (onKok != null) ...[const SizedBox(width: 8), KokButton(on: kok, onChanged: onKok!)],
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (p.greviews > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text.rich(TextSpan(children: [
                const TextSpan(text: '구글 별점 ', style: TextStyle(fontSize: 12.5, color: kGray)),
                TextSpan(text: p.grate.toStringAsFixed(1), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
                TextSpan(text: '   리뷰 ${p.greviews}개', style: const TextStyle(fontSize: 12.5, color: kGray)),
              ])),
            ),
          Padding(padding: const EdgeInsets.only(bottom: 4), child: DistanceText(place: p)),
          if (p.model.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                const Icon(Icons.verified_outlined, size: 14, color: kInk),
                const SizedBox(width: 5),
                Expanded(child: Text(p.model, style: const TextStyle(fontSize: 13, color: kInk))),
              ]),
            ),
          if (p.tv.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                const Icon(Icons.live_tv_outlined, size: 14, color: kInk),
                const SizedBox(width: 5),
                Expanded(child: Text('${p.tv.join(' · ')} 출연', style: const TextStyle(fontSize: 13, color: kInk))),
              ]),
            ),
          if (open != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(open.text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: open.open ? kPointText : kGray)),
            ),
          if (p.addr.isNotEmpty) Text(p.addr, style: const TextStyle(fontSize: 13, color: kInk, height: 1.4)),
              ]),
            ),
            const SizedBox(width: 10),
            SizedBox(width: 114, child: Wrap(spacing: 6, runSpacing: 6, children: quick)),
          ]),
          if (p.feat.any(kFeat.containsKey)) ...[
            const SizedBox(height: 12),
            FeatRow(p.feat),
          ],
          const SizedBox(height: 22),
          const _Title(text: '영업시간'),
          const SizedBox(height: 8),
          if (p.week.isEmpty)
            const Text('구글에 등록된 영업시간이 없습니다. 카카오맵이나 네이버 지도에서 확인해 주세요.',
                style: TextStyle(fontSize: 12.5, color: kGray, height: 1.4))
          else
            for (final line in p.week)
              Builder(builder: (_) {
                final cut = line.indexOf(':');
                final d = cut > 0 ? line.substring(0, cut).replaceAll('요일', '') : '';
                final v = cut > 0 ? line.substring(cut + 1).trim() : line;
                final isToday = line.startsWith(today);
                final st = TextStyle(fontSize: 12.5, height: 1.4, color: isToday ? kInk : kGray, fontWeight: isToday ? FontWeight.w700 : FontWeight.w400);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 26, child: Text(d, style: st)),
                    Expanded(child: Text(v, style: st)),
                  ]),
                );
              }),
          if (p.week.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('구글 지도 기준이라 명절·임시 휴무는 반영되지 않을 수 있습니다.', style: TextStyle(fontSize: 11, color: kGray)),
            ),
          // 정보 수정 신고 (작게)
          Align(
            alignment: Alignment.centerRight,
            child: Builder(builder: (context) {
              void report() => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    barrierColor: Colors.black.withValues(alpha: 0.08),
                    builder: (_) => ReportSheet(place: p),
                  );
              return Semantics(
              button: true,
              label: '정보 수정 신고',
              onTap: report,
              excludeSemantics: true,
              child: TextButton(
                onPressed: report,
                style: TextButton.styleFrom(foregroundColor: kGray, padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 32)),
                child: const Text('정보가 다른가요?  정보 수정 신고', style: TextStyle(fontSize: 11.5, color: kGray, decoration: TextDecoration.underline, decorationColor: kGray)),
              ),
            );
            }),
          ),
          const SizedBox(height: 14),
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
          // 인스타: 가게 계정 주소만 (게시물·사진은 가져오지 않음), 주소 없는 가게는 숨김
          if (p.insta.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _Title(text: '인스타그램'),
            _Btn(label: '인스타 보기', onTap: () => openUrl(p.insta)),
          ],
        ],
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool strong; // 전화: 파랑 하나만 강조
  final VoidCallback onTap;
  const _Quick({required this.icon, required this.label, required this.onTap, this.strong = false});
  @override
  Widget build(BuildContext context) {
    final c = strong ? kPoint : kInk;
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: strong ? kPoint.withValues(alpha: 0.5) : kLine, width: 1),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 21, color: c),
              const SizedBox(height: 3),
              Text(label, maxLines: 1, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: c, height: 1.1)),
            ]),
          ),
        ),
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
          color: primary ? kPoint : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: primary ? kPoint : kLine, width: 1),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary ? Colors.white : kInk)),
      ),
    );
  }
}
