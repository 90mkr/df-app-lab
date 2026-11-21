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

// ---- 음식 종류 (카카오 분류 둘째 칸이 있으면 그것, 없으면 분류·이름으로) ----
const kCuisines = ['한식', '중식', '일식', '양식', '아시안', '분식', '빵', '카페'];

String cuisineOf(Place p) {
  if (isBread(p)) return '빵';
  if (p.kind == 'cafe') return '카페';
  const direct = {'한식': '한식', '중식': '중식', '일식': '일식', '양식': '양식', '분식': '분식', '아시아음식': '아시안', '패스트푸드': '양식'};
  final d = direct[p.cz];
  if (d != null) return d;
  final c = '${p.cat} ${p.name}';
  bool has(List<String> ks) => ks.any(c.contains);
  if (has(const ['중국', '중식', '짬뽕', '짜장', '마라', '양꼬치', '딤섬', '훠궈'])) return '중식';
  if (has(const ['일식', '초밥', '스시', '라멘', '우동', '돈까스', '돈카츠', '이자카야', '오마카세', '텐동', '규동', '소바'])) return '일식';
  if (has(const ['양식', '이탈리안', '파스타', '피자', '스테이크', '버거', '브런치', '패밀리레스토랑', '멕시칸', '프랑스', '스페인', '쉐이크쉑'])) return '양식';
  if (has(const ['인도', '베트남', '태국', '쌀국수', '아시아', '네팔', '터키'])) return '아시안';
  if (has(const ['분식', '떡볶이', '김밥', '만두'])) return '분식';
  if (has(const ['한식', '육류', '고기', '국수', '순대', '한정식', '해물', '생선', '찌개', '전골', '국밥', '해장', '곰탕', '냉면', '칼국수', '감자탕', '닭',
    '족발', '보쌈', '갈비', '백반', '두부', '쌈밥', '조개'])) {
    return '한식';
  }
  return '';
}

// 대표 메뉴: 영상·블로그 제목에 두 번 넘게 나온 메뉴 (모범음식점 자료의 주된 음식이 있으면 그것을 먼저)
const kMenus = [
  '묵은지김치찜', '김치찜', '김치찌개', '된장찌개', '부대찌개', '순두부', '청국장', '갈비찜', '갈비탕', '돼지갈비', '소갈비', '갈비', '삼겹살', '목살', '항정살',
  '갈매기살', '차돌박이', '꽃등심', '등심', '한우', '육회', '불고기', '제육볶음', '닭갈비', '닭볶음탕', '백숙', '삼계탕', '찜닭', '치킨', '족발', '보쌈',
  '곱창', '막창', '대창', '순대국', '순댓국', '돼지국밥', '국밥', '해장국', '뼈해장국', '감자탕', '곰탕', '설렁탕', '수육', '물냉면', '비빔냉면', '냉면', '막국수',
  '바지락칼국수', '해물칼국수', '칼국수', '수제비', '잔치국수', '콩국수', '비빔밥', '쌈밥', '한정식', '보리밥', '생선구이', '갈치조림', '아구찜', '해물찜', '해물탕',
  '매운탕', '조개구이', '조개찜', '낙지볶음', '연포탕', '쭈꾸미', '주꾸미', '장어구이', '장어', '물회', '회덮밥', '모둠회', '대게', '킹크랩', '간장게장', '양념게장',
  '게장', '전복', '추어탕', '오리구이', '훈제오리', '만두', '떡볶이', '김밥', '라볶이', '어묵', '파전', '짜장면', '짬뽕', '탕수육', '마라탕', '마라샹궈', '양꼬치',
  '딤섬', '샤오롱바오', '꿔바로우', '깐풍기', '유린기', '훠궈', '초밥', '스시', '오마카세', '사시미', '라멘', '우동', '소바', '돈까스', '돈카츠', '텐동', '규동',
  '카츠동', '오코노미야키', '타코야키', '야키토리', '파스타', '피자', '스테이크', '수제버거', '햄버거', '함박스테이크', '리조또', '브런치', '샐러드', '샌드위치',
  '타코', '부리또', '쌀국수', '분짜', '반미', '팟타이', '커리', '카레', '탄두리', '소금빵', '크루아상', '베이글', '식빵', '단팥빵', '크림빵', '치즈케이크',
  '롤케이크', '케이크', '마카롱', '휘낭시에', '스콘', '도넛', '에그타르트', '크로플', '와플', '망고빙수', '팥빙수', '빙수', '젤라또', '아이스크림', '티라미수',
  '푸딩', '아인슈페너', '핸드드립', '말차', '밀크티',
];

// 메뉴 이름이 다른 낱말 속에 숨어 헛걸리는 것 (베이커리 → 커리, 안심식당 → 안심 …)은 먼저 지운다
const kMenuMask = ['베이커리', '안심식당', '스토리', '타코야끼집'];

List<String> menusOf(Place p) {
  final texts = [for (final v in p.vids) v.title, for (final b in p.posts) '${b.title} ${b.desc}'];
  final cnt = <String, int>{};
  for (final t in texts) {
    var s = t.replaceAll(' ', '');
    for (final w in kMenuMask) {
      s = s.replaceAll(w, '/');
    }
    for (final m in kMenus) {
      if (s.contains(m)) cnt[m] = (cnt[m] ?? 0) + 1;
    }
  }
  final keys = cnt.keys.where((k) => cnt[k]! >= 2).toList()
    ..sort((a, b) {
      final c = cnt[b]!.compareTo(cnt[a]!);
      return c != 0 ? c : b.length.compareTo(a.length);
    });
  final out = <String>[];
  for (final k in keys) {
    if (out.any((o) => o.contains(k) || k.contains(o))) continue;
    out.add(k);
    if (out.length == 2) break;
  }
  return out;
}

// 가게 한 줄 소개 (대표 메뉴)
String oneLine(Place p) {
  final m = p.mfood.isNotEmpty ? [p.mfood] : menusOf(p);
  return m.isEmpty ? '' : '대표 메뉴 · ${m.join(', ')}';
}

// 음식 종류 알약 (홈 · 지도)
class CuisinePills extends StatelessWidget {
  final String current;
  final bool withAll;
  final ValueChanged<String> onPick;
  const CuisinePills({super.key, required this.current, required this.onPick, this.withAll = false});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 8, children: [
        if (withAll) _SegChip(label: '전체', on: current.isEmpty, onTap: () => onPick('')),
        for (final c in kCuisines) _SegChip(label: c, on: current == c, onTap: () => onPick(c)),
      ]);
}

// ---- 테마 (자동으로 묶이는 것부터) ----
// 이름에 유명인·방송 프로그램 이름은 쓰지 않는다 (가게 화면의 「○○ 출연」 사실 표시는 괜찮음)
class Course {
  final String id, bold, light, desc; // 이름: 굵은 앞말 + 가는 뒷말, 짧은 설명
  final List<Place> stops;
  final bool route; // true: 순서대로 잇는 코스(지도에 점선) / false: 모아 보기(번호만)
  Course(this.id, this.bold, this.light, this.stops, {this.desc = '', this.route = true});
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
    return m <= 2500 ? '도보 약 ${r5(m / 70)}분' : '차로 약 ${r5(m / 500)}분';
  }

  String get sub => route ? '${stops.length}곳 · $trip' : [('${stops.length}곳'), if (desc.isNotEmpty) desc].join(' · ');
}

// 가게 분류 (카카오 분류 + 가게 이름으로 자동)
bool _has(Place p, List<String> keys) {
  final t = '${p.cat} ${p.name}';
  return keys.any(t.contains);
}

bool isSoup(Place p) => p.kind == 'food' && _has(p, const ['국밥', '해장', '순대', '순댓국', '곰탕', '설렁탕', '감자탕', '내장탕', '선지', '뼈다귀', '육개장']);
bool isNoodle(Place p) =>
    p.kind == 'food' && _has(p, const ['국수', '칼국수', '냉면', '면옥', '제면', '막국수', '우동', '라멘', '라면', '소바', '쌀국수', '짬뽕', '수제비', '밀면']);
bool isBread(Place p) => _has(p, const ['베이커리', '제과', '빵', '브레드', '베이글', '도넛', '크루아상', '소금빵']);
bool isMeat(Place p) => p.kind == 'food' && _has(p, const ['육류', '고기', '갈비', '삼겹', '한우', '숯불', '등심', '정육', '곱창', '막창', '스테이크', '목살', '양꼬치']);

// 오늘 밤 10시 넘어서도 여는 집 (24시간 포함)
bool isLate(Place p) {
  if (p.hours.isEmpty) return false;
  if (p.hours.any((h) => h[2] < 0)) return true;
  final day = nowKst().weekday % 7;
  const week = 7 * 1440;
  int mins(int d, int v) => d * 1440 + (v ~/ 100) * 60 + v % 100;
  final t = day * 1440 + 22 * 60 + 1;
  for (final h in p.hours) {
    final o = mins(h[0], h[1]);
    var c = mins(h[2], h[3]);
    if (c <= o) c += week;
    for (final n in [t, t + week]) {
      if (n >= o && n < c) return true;
    }
  }
  return false;
}

// 모아 보기: 최대 10곳 (번호만, 점선 없음)
Course? collect(String id, String bold, String light, Iterable<Place> ps, {String desc = ''}) {
  final l = ps.take(10).toList();
  return l.length < 3 ? null : Course(id, bold, light, l, desc: desc, route: false);
}

// 맛집에서 시작해 카페·맛집을 번갈아 가까운 집으로 잇는 3~4곳 코스
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

// 가까운 집부터 차례로 잇는 코스 (빵지순례)
Course? chain(String id, String bold, String light, Iterable<Place> theme, {int size = 5, double within = 5000}) {
  final ps = theme.toList();
  if (ps.length < 3) return null;
  final out = [ps.first];
  final cand = ps.skip(1).where((p) => meters(ps.first.point, p.point) <= within).toList();
  while (out.length < size && cand.isNotEmpty) {
    final last = out.last.point;
    cand.sort((a, b) => meters(last, a.point).compareTo(meters(last, b.point)));
    out.add(cand.removeAt(0));
  }
  return out.length >= 3 ? Course(id, bold, light, out) : null;
}

// 동네 한 바퀴: 인기 맛집 3 + 카페 2를 한 바퀴 도는 순서로 (첫 맛집에서 출발)
Course? tour(String id, String bold, String light, List<Place> top) {
  final food = top.where((p) => p.kind == 'food').take(3).toList();
  final ps = [...food, ...top.where((p) => p.kind == 'cafe').take(2)];
  if (ps.length < 3) return null;
  final cLat = ps.map((p) => p.lat).reduce((a, b) => a + b) / ps.length;
  final cLng = ps.map((p) => p.lng).reduce((a, b) => a + b) / ps.length;
  double ang(Place p) => math.atan2(p.lat - cLat, p.lng - cLng);
  ps.sort((a, b) => ang(b).compareTo(ang(a)));
  final s = ps.indexOf(food.isNotEmpty ? food.first : ps.first);
  return Course(id, bold, light, [...ps.sublist(s), ...ps.sublist(0, s)]);
}

// 동네 테마 — 자동으로 묶이는 것부터 (정보가 모자라면 그 테마는 안 보임)
List<Course> coursesOf(SongdoData d, Area a) {
  final top = popRank(d);
  final yt = ytRank(d);
  final tv = top.where((p) => p.tv.isNotEmpty).toList();
  final cook = tv.where((p) => p.tv.any(kCookShows.contains)).toList();
  final out = <Course?>[
    collect('proven', '검증 ', '맛집', yt.where((p) => ytCount(p) >= 3), desc: '유튜버 3명 이상 다녀간 집'),
    makeCourse('yt', '먹방 유튜버 ', '코스', yt.where((p) => ytCount(p) >= 2)),
    if (a.tour.length == 2) tour('tour', a.tour[0], a.tour[1], top),
    collect('soup', '국밥', '·해장', top.where(isSoup)),
    collect('noodle', '칼국수', '·면', top.where(isNoodle)),
    chain('bread', '빵지', '순례', top.where(isBread)),
    collect('meat', '고기 ', '맛집', top.where(isMeat)),
    collect('late', '늦게까지 ', '여는 집', top.where(isLate), desc: '오늘 밤 10시 넘어서까지'),
    // 방송 정보가 모이면 저절로 나타난다
    makeCourse('cook', '요리 경연 방송 ', '코스', cook),
    if (tv.length > cook.length) makeCourse('tv', '방송 맛집 ', '코스', tv),
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
      case 'set': // 설정: 조절 막대 셋
        for (final (y, x) in const [(7.0, 9.0), (12.0, 15.5), (17.0, 7.5)]) {
          c.drawLine(o(4, y), o(20, y), p);
          c.drawCircle(o(x, y), 2.1 * k, Paint()..color = Colors.white);
          c.drawCircle(o(x, y), 2.1 * k, p);
        }
      case 'user': // 사람
        c.drawCircle(o(12, 8.5), 3.6 * k, p);
        c.drawPath(
            ui.Path()
              ..moveTo(5 * k, 20 * k)
              ..cubicTo(5 * k, 15.5 * k, 8.2 * k, 13.6 * k, 12 * k, 13.6 * k)
              ..cubicTo(15.8 * k, 13.6 * k, 19 * k, 15.5 * k, 19 * k, 20 * k),
            p);
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

// 쇼츠(세로 영상): 표지를 자르지 않고 어두운 바탕 가운데에 통째로
Widget _shortFit(String id, Widget fb) => Container(
      color: const Color(0xFF16171B),
      alignment: Alignment.center,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Image.network(
          'https://i.ytimg.com/vi/$id/hqdefault.jpg',
          fit: BoxFit.fill,
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
          errorBuilder: (_, __, ___) => fb,
        ),
      ),
    );

// 유튜브 큰 사진 (16:9 칸): 고화질 표지(maxres, 16:9 그대로 — 쇼츠도 통째로)를 먼저,
// 없는 영상은 hqdefault에서 검은 띠만 빼거나(가로 영상) 통째로(쇼츠) — 어느 쪽도 그림을 자르지 않는다
Widget ytWide(Video v, {Widget? fallback}) {
  final fb = fallback ?? Container(color: const Color(0xFFE9E9EC));
  return Image.network(
    'https://i.ytimg.com/vi/${v.id}/maxresdefault.jpg',
    fit: BoxFit.cover,
    width: double.infinity,
    height: double.infinity,
    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
    loadingBuilder: (_, child, progress) => progress == null ? child : Container(color: const Color(0xFFEDEDF0)),
    errorBuilder: (_, __, ___) => v.short ? _shortFit(v.id, fb) : _hqCrop(v.id, fb),
  );
}

// 작은 표지: 유튜브 표지 비율(16:9) 그대로 — mqdefault는 16:9에 띠가 없고, 쇼츠도 통째로 담긴다
Widget ytSmall(Place p, double w, {double r = 6}) => ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: SizedBox(
        width: w,
        height: w * 9 / 16,
        child: p.vids.isEmpty
            ? kindFill(p.kind, w * 0.3)
            : Image.network(
                'https://i.ytimg.com/vi/${p.vids.first.id}/mqdefault.jpg',
                fit: BoxFit.cover,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                errorBuilder: (_, __, ___) => kindFill(p.kind, w * 0.3),
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
        onTap: onTap,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: on ? kInk : Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: on ? kInk : kPillLine, width: 1),
            ),
            // 글자 폭만큼만 (줄바꿈 칸에서도 가로로 늘어나지 않게)
            child: Center(
              widthFactor: 1,
              child: Text(label, style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? Colors.white : kInk)),
            ),
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
          onTap: onRegion,
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
  final ValueChanged<String> onCuisine; // 음식 종류 → 지도
  final ValueChanged<Place> onWhere; // 이 집 어디야 → 지도
  final ValueChanged<Chan> onChannel;
  final ValueChanged<Course> onCourse;
  final VoidCallback onAllChannels, onRankAll;
  final FollowData? follow; // 유명 유튜버 따라가기 (전국)
  final ValueChanged<String> onFollow; // 채널 id (비면 전체) → 지도
  final ValueChanged<Place> onFollowPlace; // 새로 올라온 영상 → 그 가게
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
    required this.onCuisine,
    required this.onWhere,
    required this.onChannel,
    required this.onCourse,
    required this.onAllChannels,
    required this.onRankAll,
    this.follow,
    required this.onFollow,
    required this.onFollowPlace,
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
                  const SizedBox(height: 22),
                  sectionHead('무엇이 ', '당기세요?'),
                  const SizedBox(height: 10),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: CuisinePills(current: '', onPick: onCuisine)),
                  _follow(),
                  _fresh(),
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
    final v = p.vids.isEmpty
        ? null
        : p.vids.firstWhere((x) => x.hd && !x.short, orElse: () => p.vids.firstWhere((x) => !x.short, orElse: () => p.vids.first));
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
              aspectRatio: 16 / 9,
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
            onTap: () => onWhere(p),
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

  // 유튜버 따라 먹기 (전국): 큰 맛집 채널 → 누르면 지도에서 그 채널이 다녀간 집
  Widget _follow() {
    final f = follow;
    if (f == null || f.channels.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sectionHead('유튜버 ', '따라 먹기', link: '전국 지도', onLink: () => onFollow('')),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text('맛집 채널이 영상에 주소를 적어 둔 집 · 전국 ${commas(f.places.length)}곳',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w300, color: kSub)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: f.channels.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final c = f.channels[i];
              return Semantics(
                button: true,
                label: '${c.name} 따라 먹기',
                onTap: () => onFollow(c.id),
                excludeSemantics: true,
                child: GestureDetector(onTap: () => onFollow(c.id), child: ChanAvatar(c)),
              );
            },
          ),
        ),
      ]),
    );
  }

  // 새로 올라온 영상 (따라가는 채널들의 최근 영상 — 누르면 그 가게)
  Widget _fresh() {
    final f = follow;
    if (f == null || f.fresh.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sectionHead('새로 ', '올라온 영상'),
        const SizedBox(height: 10),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: f.fresh.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final (v, p) = f.fresh[i];
              return FreshCard(video: v, place: p, channel: f.names[v.cid] ?? v.channel, onTap: () => onFollowPlace(p));
            },
          ),
        ),
      ]),
    );
  }

  Widget _creators(SongdoData d) {
    final list = channelsOf(d).take(12).toList();
    if (list.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sectionHead('이 동네 ', '다녀간 유튜버', link: '전체 보기', onLink: onAllChannels),
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
    final list = coursesOf(d, area);
    if (list.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sectionHead('테마 ', '골라 보기'),
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
        onTap: onTap,
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
      onTap: onTap,
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
            Text(c.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w300, color: kSub)),
            const SizedBox(height: 10),
            Row(children: [
              for (var i = 0; i < math.min(s.length, 4); i++) ...[
                if (i > 0) const SizedBox(width: 4),
                ytSmall(s[i], 48, r: 4),
              ],
            ]),
            const SizedBox(height: 9),
            Text([for (var i = 0; i < math.min(s.length, 4); i++) '${i + 1} ${s[i].name}'].join('  '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kInk, height: 1.3)),
          ]),
        ),
      ),
    );
  }
}

// 지도 위 코스 띠 (코스 보는 중)
// 영상 길이 12:34 · 1:02:03
String durText(int s) {
  if (s <= 0) return '';
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

// 올린 날: 오늘 · 어제 · 3일 전 · 2주 전 · 5개월 전 · 2년 전
String agoText(String date) {
  final d = DateTime.tryParse(date);
  if (d == null) return '';
  final days = DateTime.now().difference(d).inDays;
  if (days <= 0) return '오늘';
  if (days == 1) return '어제';
  if (days < 7) return '$days일 전';
  if (days < 30) return '${days ~/ 7}주 전';
  if (days < 365) return '${days ~/ 30}개월 전';
  return '${days ~/ 365}년 전';
}

class FreshCard extends StatelessWidget {
  final Video video;
  final Place place;
  final String channel;
  final VoidCallback onTap;
  const FreshCard({super.key, required this.video, required this.place, required this.channel, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final v = video;
    final fb = kindFill(place.kind, 28);
    final badge = v.short ? '쇼츠' : durText(v.dur);
    return Semantics(
      button: true,
      label: v.title,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 216,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(fit: StackFit.expand, children: [
                  v.short
                      ? _shortFit(v.id, fb)
                      : Image.network('https://i.ytimg.com/vi/${v.id}/mqdefault.jpg',
                          fit: BoxFit.cover, webHtmlElementStrategy: WebHtmlElementStrategy.fallback, errorBuilder: (_, __, ___) => fb),
                  if (badge.isNotEmpty)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(4)),
                        child: Text(badge, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 7),
            Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kInk, height: 1.3)),
            const SizedBox(height: 3),
            Text([channel, agoText(v.date)].where((x) => x.isNotEmpty).join(' · '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w400, color: kSub)),
            Text([place.name, [sidoShort(place.sido), place.gu].where((x) => x.isNotEmpty).join(' ')].where((x) => x.isNotEmpty).join(' · '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w300, color: kSub)),
          ]),
        ),
      ),
    );
  }
}

// 따라가기 지도 머리 띠: 지금 보는 채널 · 전국 몇 곳 · 닫기, 아래에 채널 고르기
class FollowBar extends StatelessWidget {
  final FollowData follow;
  final String current;
  final ValueChanged<String> onPick;
  final VoidCallback onClose;
  const FollowBar({super.key, required this.follow, required this.current, required this.onPick, required this.onClose});
  @override
  Widget build(BuildContext context) {
    final f = follow;
    final ch = f.channels.where((c) => c.id == current).firstOrNull;
    final n = ch?.places.length ?? f.places.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 40,
        padding: const EdgeInsets.only(left: 14, right: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kAccent, width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10)],
        ),
        child: Row(children: [
          const LineIcon('play', size: 15, color: kAccent),
          const SizedBox(width: 7),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: ch == null ? '유튜버 따라 먹기' : '${ch.name} 따라 먹기', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
                TextSpan(text: '   전국 ${commas(n)}곳', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w300, color: kSub)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Semantics(
            button: true,
            label: '따라가기 닫기',
            onTap: onClose,
            excludeSemantics: true,
            child: IconButton(onPressed: onClose, tooltip: '따라가기 닫기', visualDensity: VisualDensity.compact, icon: const Icon(Icons.close_rounded, size: 18, color: kInk)),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 30,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          _SegChip(label: '전체', on: current.isEmpty, onTap: () => onPick('')),
          for (final c in f.channels) ...[
            const SizedBox(width: 6),
            _SegChip(label: c.name, on: current == c.id, onTap: () => onPick(c.id)),
          ],
        ]),
      ),
    ]);
  }
}

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
                  TextSpan(
                      text: course.route ? '   ${course.stops.length}곳 · ${course.trip} · 순서 보기' : '   ${course.stops.length}곳 · 목록 보기',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w300, color: kSub)),
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
                      onTap: spin,
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
                      height: 72,
                      padding: const EdgeInsets.all(12),
                      decoration: kokCard(),
                      child: Row(children: [
                        ytSmall(p, 80),
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
                          onTap: () {
                            Navigator.pop(context);
                            widget.onWhere(p);
                          },
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
      final mid = start + seg / 2;
      if (math.cos(mid + angle) < 0) {
        // 왼쪽 반: 글자가 거꾸로 보이지 않게 반 바퀴 돌려 바깥→안쪽으로
        c.rotate(mid + math.pi);
        tp.paint(c, Offset(-r * 0.94 + (r * 0.64 - tp.width) / 2, -tp.height / 2));
      } else {
        c.rotate(mid);
        tp.paint(c, Offset(r * 0.3 + (r * 0.64 - tp.width) / 2, -tp.height / 2));
      }
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
          ytSmall(place, 80),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(place.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Text([if (myPos.value != null) distText(meters(myPos.value!, place.point)), metaOf(place)].join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w300, color: kSub)),
              if (oneLine(place).isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(oneLine(place), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: kInk)),
              ],
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
    Widget item((Video, Place) it) {
      final (v, p) = it;
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
        Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk, height: 1.35)),
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
    }

    return SafeArea(
      bottom: false,
      child: LayoutBuilder(builder: (_, c) {
        // 휴대폰은 한 줄에 1개, 태블릿(가로 600 이상)은 2개
        final cols = c.maxWidth >= 600 ? 2 : 1;
        final width = math.min(c.maxWidth, cols == 1 ? kHomeMax : 1040.0);
        final itemW = (width - 40 - 16 * (cols - 1)) / cols;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: c.maxHeight,
            child: Column(children: [
              KokHeader(area: area, open: regionOpen, onRegion: onRegion, onSearch: onSearch, title: '영상'),
              if (regionOpen) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: regionPanel),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(d == null ? '' : '${area.name} 유튜브 영상은 모으는 중입니다.', style: const TextStyle(fontSize: 13, color: kSub)),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 22,
                          mainAxisExtent: itemW * 9 / 16 + 80,
                        ),
                        itemCount: items.length,
                        itemBuilder: (_, i) => item(items[i]),
                      ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

// ---- 내 콕 (저장한 집) ----
class SavedView extends StatefulWidget {
  final List<Map<String, dynamic>> koks, recents;
  final ValueChanged<Map<String, dynamic>> onOpen, onRemove, onRemoveRecent;
  final VoidCallback onClearRecents;
  const SavedView(
      {super.key,
      required this.koks,
      required this.recents,
      required this.onOpen,
      required this.onRemove,
      required this.onRemoveRecent,
      required this.onClearRecents});
  @override
  State<SavedView> createState() => _SavedViewState();
}

class _SavedViewState extends State<SavedView> {
  int? which; // 0 콕한 집 · 1 최근 본 집 (안 골랐으면 콕한 집이 없을 때 최근 본 집부터)
  void openSettings(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));

  // 언제 봤는지: 오늘 · 어제 · 3일 전 · 11월 2일
  static String seen(Object? t) {
    if (t is! num) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(t.toInt());
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (days <= 0) return '오늘';
    if (days == 1) return '어제';
    if (days < 7) return '$days일 전';
    return '${d.month}월 ${d.day}일';
  }

  Widget row(Map<String, dynamic> k, {required VoidCallback onRemove, required String removeTip, bool when = false}) {
    final th = '${k['th'] ?? ''}';
    final kd = '${k['k'] ?? 'food'}';
    return InkWell(
      onTap: () => widget.onOpen(k),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 80,
              height: 45,
              child: th.isEmpty
                  ? kindFill(kd, 24)
                  : Image.network(th, fit: BoxFit.cover, webHtmlElementStrategy: WebHtmlElementStrategy.fallback, errorBuilder: (_, __, ___) => kindFill(kd, 24)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${k['n'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
              const SizedBox(height: 2),
              Text(
                  [
                    if (when) seen(k['t']),
                    if (myPos.value != null && k['la'] != null)
                      distText(meters(myPos.value!, LatLng(((k['la'] ?? 0) as num).toDouble(), ((k['ln'] ?? 0) as num).toDouble()))),
                    '${k['an'] ?? ''}',
                    '${k['c'] ?? ''}',
                  ].where((x) => x.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w300, color: kSub)),
            ]),
          ),
          IconButton(onPressed: onRemove, tooltip: removeTip, icon: const Icon(Icons.close_rounded, size: 18, color: kSub)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final koks = widget.koks, recents = widget.recents;
    final w = which ?? (koks.isEmpty && recents.isNotEmpty ? 1 : 0);
    final list = w == 0 ? koks : recents;
    return SafeArea(
      bottom: false,
      child: narrow(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
          child: Row(children: [
            const Expanded(child: Text('내 콕', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.4))),
            Semantics(
              button: true,
              label: '설정',
              onTap: () => openSettings(context),
              excludeSemantics: true,
              child: TextButton(
                onPressed: () => openSettings(context),
                style: TextButton.styleFrom(foregroundColor: kInk, padding: const EdgeInsets.symmetric(horizontal: 10)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  LineIcon('set', size: 20),
                  SizedBox(width: 4),
                  Text('설정', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: kInk)),
                ]),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 6),
          child: Row(children: [
            _SegChip(label: koks.isEmpty ? '콕한 집' : '콕한 집 ${koks.length}', on: w == 0, onTap: () => setState(() => which = 0)),
            const SizedBox(width: 6),
            _SegChip(label: recents.isEmpty ? '최근 본 집' : '최근 본 집 ${recents.length}', on: w == 1, onTap: () => setState(() => which = 1)),
            const Spacer(),
            if (w == 1 && recents.isNotEmpty)
              Semantics(
                button: true,
                label: '모두 지우기',
                onTap: widget.onClearRecents,
                excludeSemantics: true,
                child: TextButton(
                  onPressed: widget.onClearRecents,
                  style: TextButton.styleFrom(foregroundColor: kSub, padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 30)),
                  child: const Text('모두 지우기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: kSub)),
                ),
              ),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                      w == 0 ? '마음에 드는 집을 「콕」 눌러 저장해 두세요.\n가게 화면 오른쪽 위에 있습니다.' : '가게 화면을 열어 본 집이 여기에 차례로 쌓여요.\n휴대폰 안에만 남습니다.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: kSub, height: 1.5)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, thickness: 1, color: kHair),
                  itemBuilder: (_, i) => w == 0
                      ? row(list[i], onRemove: () => widget.onRemove(list[i]), removeTip: '콕 빼기')
                      : row(list[i], onRemove: () => widget.onRemoveRecent(list[i]), removeTip: '목록에서 지우기', when: true),
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
                      selected: tab == i,
                      onTap: () => onTap(i),
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
  void toggle() {
    setState(() => on = !on);
    widget.onChanged(on);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: on ? '콕 했어요' : '콕 하기',
      onTap: toggle,
      excludeSemantics: true,
      child: InkWell(
        onTap: toggle,
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

// ---- 설정 (내 콕 안) ----
const kContactMail = 'dfmail@naver.com';
const kPrivacyUrl = 'https://90mkr.github.io/df-app-lab/policy/privacy.html';
const kDeleteUrl = 'https://90mkr.github.io/df-app-lab/policy/delete.html';
const kTermsUrl = 'https://90mkr.github.io/df-app-lab/policy/terms.html';
const kAppVersion = '0.1 시험판';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  // 로그인은 후기·별점 기능(파이어베이스)과 함께 연다 — 그때 계정 칸에 로그아웃·회원 탈퇴가 생긴다
  void soon(BuildContext context) => showModalBottomSheet(
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
              padding: EdgeInsets.fromLTRB(22, 22, 22, 22 + MediaQuery.of(ctx).padding.bottom),
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                mixTitle('로그인은 ', '준비 중이에요', size: 17),
                const SizedBox(height: 8),
                const Text('후기·별점 쓰기가 열릴 때 함께 열립니다.\n지금은 로그인 없이 모든 기능을 쓸 수 있어요.', style: TextStyle(fontSize: 13, color: kSub, height: 1.45)),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                        backgroundColor: kInk, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text('확인', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    Widget row(String label, {String? sub, VoidCallback? onTap, Widget? trail}) => Semantics(
          button: onTap != null,
          label: label,
          onTap: onTap,
          excludeSemantics: true,
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kInk)),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Text(sub, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w300, color: kSub)),
                    ],
                  ]),
                ),
                trail ?? (onTap == null ? const SizedBox() : const Icon(Icons.chevron_right_rounded, size: 20, color: kSub)),
              ]),
            ),
          ),
        );
    Widget group(String title, List<Widget> rows) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kSub)),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: kokCard(),
            child: Column(children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, thickness: 1, color: kHair),
                rows[i],
              ],
            ]),
          ),
        ]);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: narrow(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 20, 4),
            child: Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), tooltip: '뒤로', icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: kInk)),
              const Text('설정', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.4)),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 30), children: [
              group('계정', [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(children: [
                    CircleAvatar(radius: 22, backgroundColor: Color(0xFFF1F1F4), child: LineIcon('user', size: 22, color: kSub)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('로그인하지 않았어요', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
                        SizedBox(height: 2),
                        Text('로그인 없이도 모든 기능을 쓸 수 있어요', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w300, color: kSub)),
                      ]),
                    ),
                  ]),
                ),
                row('로그인', sub: '후기·별점 기능과 함께 열립니다', onTap: () => soon(context)),
              ]),
              const SizedBox(height: 24),
              group('문의', [
                row('문의하기', sub: kContactMail, onTap: () => openUrl('mailto:$kContactMail?subject=${Uri.encodeComponent('[콕플] 문의')}')),
                row('제휴 문의',
                    sub: '광고·협업 제안',
                    onTap: () => openUrl('mailto:$kContactMail?subject=${Uri.encodeComponent('[콕플 제휴 문의]')}'
                        '&body=${Uri.encodeComponent('회사·가게 이름:\n담당자 연락처:\n제안 내용:\n')}')),
              ]),
              const SizedBox(height: 24),
              group('약관·정책', [
                row('서비스 이용약관', onTap: () => openUrl(kTermsUrl)),
                row('개인정보처리방침', onTap: () => openUrl(kPrivacyUrl)),
                row('회원 탈퇴 안내', sub: '계정과 쓴 후기를 지우는 방법', onTap: () => openUrl(kDeleteUrl)),
                row('YouTube 서비스 약관', onTap: () => openUrl('https://www.youtube.com/t/terms')),
              ]),
              const SizedBox(height: 24),
              group('앱 정보', [
                row('버전', trail: const Text(kAppVersion, style: TextStyle(fontSize: 12.5, color: kSub))),
              ]),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('영상과 표지 사진의 저작권은 각 유튜버에게 있습니다.\n지도 © OpenStreetMap · 모범음식점 정보 행정안전부(공공데이터포털)',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w300, color: kSub, height: 1.4)),
              ),
            ]),
          ),
        ])),
      ),
    );
  }
}

// ---- 정보 수정 신고 ----
// 로그인 기능이 열리기 전까지는 메일로 보낸다 (보낸 사람이 남아 장난 신고가 줄고, 같은 휴대폰에서 같은 가게는 하루 한 번)
class ReportSheet extends StatefulWidget {
  final Place place;
  const ReportSheet({super.key, required this.place});
  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  static const items = ['영업시간', '전화번호', '주소·위치', '폐업·이전', '메뉴·가격', '기타'];
  final picks = <String>{};
  final memo = TextEditingController();
  String note = '';
  bool sent = false;

  @override
  void dispose() {
    memo.dispose();
    super.dispose();
  }

  String get todayKey {
    final t = nowKst();
    return 'report_${widget.place.id}_${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}';
  }

  Future<void> send() async {
    SharedPreferences? sp;
    try {
      sp = await SharedPreferences.getInstance();
    } catch (_) {}
    if (sp?.getBool(todayKey) == true) {
      setState(() => note = '이 가게는 오늘 이미 신고하셨어요. 내일 다시 보낼 수 있어요.');
      return;
    }
    final p = widget.place;
    final body = '가게: ${p.name}\n주소: ${p.addr}\n항목: ${picks.join(', ')}\n내용: ${memo.text.trim()}\n\n(콕플 앱에서 보냄 · 가게 번호 ${p.id})';
    await openUrl('mailto:$kContactMail?subject=${Uri.encodeComponent('[콕플 정보 수정] ${p.name}')}&body=${Uri.encodeComponent(body)}');
    try {
      await sp?.setBool(todayKey, true);
    } catch (_) {}
    if (mounted) setState(() => sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.place;
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              mixTitle(sent ? '신고를 ' : '정보 수정 ', sent ? '보냈어요' : '신고', size: 18),
              const SizedBox(height: 3),
              Text(p.name, style: const TextStyle(fontSize: 12, color: kSub)),
              const SizedBox(height: 14),
              if (sent) ...[
                const Text('메일 앱에서 「보내기」를 누르면 접수됩니다.\n확인한 뒤 바로 고칠게요. 알려 주셔서 고맙습니다.', style: TextStyle(fontSize: 13, color: kInk, height: 1.45)),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                        backgroundColor: kInk, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text('확인', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              ] else ...[
                const Text('무엇이 다른가요? (여러 개 고를 수 있어요)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: kInk)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in items)
                    _SegChip(
                      label: t,
                      on: picks.contains(t),
                      onTap: () => setState(() {
                        if (!picks.remove(t)) picks.add(t);
                        note = '';
                      }),
                    ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: memo,
                  minLines: 2,
                  maxLines: 3,
                  maxLength: 200,
                  style: const TextStyle(fontSize: 13.5, color: kInk),
                  decoration: InputDecoration(
                    hintText: '어떻게 다른지 짧게 적어 주세요 (선택)',
                    hintStyle: const TextStyle(fontSize: 13, color: kSub),
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.all(12),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPillLine, width: 1)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kInk, width: 1)),
                  ),
                ),
                if (note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note, style: const TextStyle(fontSize: 12, color: kAccent))),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: TextButton(
                    onPressed: picks.isEmpty ? null : send,
                    style: TextButton.styleFrom(
                      backgroundColor: picks.isEmpty ? const Color(0xFFE9E9EC) : kAccent,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: kSub,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('보내기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('지금은 메일로 보내져요. 로그인 기능이 열리면 앱 안에서 바로 접수됩니다.', style: TextStyle(fontSize: 10.5, color: kSub)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// ---- 거리 (내 위치를 알면 「내 위치에서 1.2km」, 모르면 「거리 보기」를 눌러 위치 확인) ----
class DistanceText extends StatefulWidget {
  final Place place;
  const DistanceText({super.key, required this.place});
  @override
  State<DistanceText> createState() => _DistanceTextState();
}

class _DistanceTextState extends State<DistanceText> {
  bool busy = false;
  String note = '';

  Future<void> locate() async {
    setState(() {
      busy = true;
      note = '';
    });
    final at = await myLocation();
    if (!mounted) return;
    setState(() {
      busy = false;
      if (at == null) note = '위치를 확인하지 못했습니다';
    });
    if (at != null) myPos.value = at;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<LatLng?>(
        valueListenable: myPos,
        builder: (_, at, __) => Row(children: [
          const Icon(Icons.near_me_outlined, size: 14, color: kInk),
          const SizedBox(width: 5),
          if (at != null)
            Text.rich(TextSpan(children: [
              const TextSpan(text: '내 위치에서 ', style: TextStyle(fontSize: 13, color: kGray)),
              TextSpan(text: distText(meters(at, widget.place.point)), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
            ]))
          else
            Semantics(
              button: true,
              label: '거리 보기',
              onTap: busy ? null : locate,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: busy ? null : locate,
                child: Text(busy ? '내 위치 확인 중…' : (note.isNotEmpty ? note : '거리 보기 (내 위치 확인)'),
                    style: const TextStyle(fontSize: 13, color: kGray, decoration: TextDecoration.underline, decorationColor: kGray)),
              ),
            ),
        ]),
      );
}
