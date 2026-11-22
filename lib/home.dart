part of 'main.dart';

// ---------------- 콕플 시안: 홈 · 영상 · 내 콕 · 아래 탭 · 룰렛 · 테마 코스 ----------------

const kAccent = Color(0xFFFF4B2B); // 콕플 대표색 (시안)
const kSub = Color(0xFF6B6B75); // 보조 글색 (시안)
const kHair = Color(0xFFECECF0); // 가는 구분선
const kNavOff = Color(0xFF858D98); // 아래 탭: 안 고른 아이콘·글
const kPageBg = Color(0xFFF2F3F5); // 홈 바탕 (흰 카드 뒤 옅은 회색)

// 홈 흰 카드 (회색 바탕 위에)
Widget homeCard(Widget child, {EdgeInsets padding = const EdgeInsets.symmetric(vertical: 24), EdgeInsets margin = const EdgeInsets.fromLTRB(14, 0, 14, 14)}) => Container(
      margin: margin,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.025), blurRadius: 10)],
      ),
      child: child,
    );
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
// 머리말처럼 높이가 정해지지 않은 줄을 넓은 화면에서 가운데 좁게
Widget narrowTop(Widget child) => LayoutBuilder(
      builder: (_, c) => Align(alignment: Alignment.topCenter, child: SizedBox(width: math.min(c.maxWidth, kHomeMax), child: child)),
    );

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

// 추천 영상: 앱을 열 때마다 다른 집 — 그 동네에서 영상이 있는 집 15곳 + 최근 한 달 새 영상이 올라온 집 가운데,
// 유튜버가 많이 다녀간 집·새 영상이 있는 집이 더 자주 나오게 뽑고, 최근에 본 5곳은 다시 안 나오게.
// 한 번 뽑으면 앱을 닫을 때까지 그대로 (화면을 다시 그려도 안 바뀜).
final Map<String, String> heroChoice = {}; // 동네 → 이번에 뽑힌 가게
List<String> heroSeen = []; // 최근에 맨 위에 보인 가게 (앱 시작 때 읽어 둠)

// 추천 영상에서 재생한 가게: 그 집에 새 영상이 올라오기 전까지 다시 안 나옴 (로그인하면 계정에도 저장)
Map<String, Map<String, dynamic>> heroWatched = {}; // 가게 id → {'d': 그때 가장 최근 영상 날짜, 't': 본 때}

Future<void> loadHeroSeen() async {
  try {
    final sp = await SharedPreferences.getInstance();
    heroSeen = sp.getStringList('hero_seen') ?? [];
    final w = sp.getString('hero_watched');
    if (w != null) {
      heroWatched = {
        for (final e in (jsonDecode(w) as Map).entries)
          if (e.value is Map) '${e.key}': Map<String, dynamic>.from(e.value as Map)
      };
    }
  } catch (_) {}
}

bool watchedNoNew(Place p) {
  final w = heroWatched[p.id];
  return w != null && ytLast(p).compareTo('${w['d'] ?? ''}') <= 0;
}

num _watchedAt(String id) => (heroWatched[id]?['t'] ?? 0) as num;

void saveWatched({bool push = true}) {
  if (heroWatched.length > 300) {
    final ks = heroWatched.keys.toList()..sort((a, b) => _watchedAt(a).compareTo(_watchedAt(b)));
    for (final k in ks.take(heroWatched.length - 300)) {
      heroWatched.remove(k);
    }
  }
  SharedPreferences.getInstance().then((sp) => sp.setString('hero_watched', jsonEncode(heroWatched))).catchError((_) => false);
  if (push) pushWatched(heroWatched);
}

void markWatched(Place p) {
  heroWatched[p.id] = {'d': ytLast(p), 't': DateTime.now().millisecondsSinceEpoch};
  saveWatched();
}

Place? sessionPick(String key, List<Place> pool) {
  final had = heroChoice[key];
  if (had != null) {
    final p = pool.where((x) => x.id == had).firstOrNull;
    if (p != null) return p;
  }
  if (pool.isEmpty) return null;
  final notWatched = pool.where((p) => !watchedNoNew(p)).toList();
  final fresh = notWatched.where((p) => !heroSeen.contains(p.id)).toList();
  var src = fresh.isNotEmpty ? fresh : notWatched;
  if (src.isEmpty) {
    // 동네 후보를 다 봤으면 오래전에 본 것부터 다시
    src = ([...pool]..sort((a, b) => _watchedAt(a.id).compareTo(_watchedAt(b.id)))).take(3).toList();
  }
  double w(Place p) => 1.0 + ytCount(p) + (ytRecent(p) ? 2.0 : 0.0);
  final total = src.fold<double>(0, (a, p) => a + w(p));
  var x = math.Random().nextDouble() * total;
  var pick = src.last;
  for (final p in src) {
    x -= w(p);
    if (x <= 0) {
      pick = p;
      break;
    }
  }
  heroChoice[key] = pick.id;
  heroSeen = [pick.id, ...heroSeen.where((x) => x != pick.id)].take(5).toList();
  SharedPreferences.getInstance().then((sp) => sp.setStringList('hero_seen', heroSeen)).catchError((_) => false);
  return pick;
}

List<Place> heroPool(SongdoData d) {
  final l = ytRank(d).where((p) => p.vids.any((v) => !v.short)).toList();
  return [...l.take(15), ...l.skip(15).where((p) => ytRecent(p))];
}

// 영상이 없는 동네: 인기 맛집 가운데 날마다 돌아가며
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
const kCuisineEmoji = {'한식': '🍲', '중식': '🥟', '일식': '🍣', '양식': '🍝', '아시안': '🍜', '분식': '🍢', '빵': '🥐', '카페': '☕'};

class CuisinePills extends StatelessWidget {
  final String current;
  final bool withAll;
  final ValueChanged<String> onPick;
  const CuisinePills({super.key, required this.current, required this.onPick, this.withAll = false});
  // 한 줄을 꽉 채워 같은 너비로 (8개면 4칸씩 두 줄, 9개면 3칸씩 세 줄)
  @override
  Widget build(BuildContext context) {
    final items = [if (withAll) ('', '전체', '🍽️'), for (final c in kCuisines) (c, c, kCuisineEmoji[c] ?? '')];
    final cols = items.length % 4 == 0 ? 4 : 3;
    return LayoutBuilder(builder: (_, box) {
      const gap = 6.0;
      final w = ((box.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
      return Wrap(spacing: gap, runSpacing: 9, children: [
        for (final (key, label, emoji) in items)
          SizedBox(width: w, child: _FillChip(label: label, emoji: emoji, on: current == key, onTap: () => onPick(key))),
      ]);
    });
  }
}

// 칸을 꽉 채우는 단추 (그림 글자 + 이름, 가운데)
class _FillChip extends StatelessWidget {
  final String label, emoji;
  final bool on;
  final VoidCallback onTap;
  const _FillChip({required this.label, required this.emoji, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: on ? kInk : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: on ? kInk : kPillLine, width: 1),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (emoji.isNotEmpty) ...[Text(emoji, style: const TextStyle(fontSize: 18, height: 1.1)), const SizedBox(width: 4)],
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: TextStyle(fontSize: 14, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? Colors.white : kInk)),
              ),
            ]),
          ),
        ),
      );
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
  final double? stroke; // 선 굵기 (24칸 기준, 비우면 1.7)
  const LineIcon(this.name, {super.key, this.size = 22, this.color = kInk, this.stroke});
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _LinePainter(name, color, stroke));
}

class _LinePainter extends CustomPainter {
  final String name;
  final Color color;
  final double? stroke;
  _LinePainter(this.name, this.color, this.stroke);
  @override
  void paint(Canvas c, Size s) {
    final k = s.width / 24;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (stroke ?? (name == 'pin' ? 1.9 : 1.7)) * k
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
              ..moveTo(10.3 * k, 9.2 * k)
              ..lineTo(10.3 * k, 14.8 * k)
              ..lineTo(14.8 * k, 12 * k)
              ..close(),
            Paint()..color = color);
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
  bool shouldRepaint(covariant _LinePainter o) => o.name != name || o.color != color || o.stroke != stroke;
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
    // 고화질 표지가 없는 영상은 유튜브가 404와 함께 작은 회색 그림을 준다 — 웹에서 그 그림을 띄우지 않고 바로 hq로 넘어가게
    webHtmlElementStrategy: WebHtmlElementStrategy.never,
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
  final String emoji; // 앞에 붙는 색 그림 글자
  final Widget? lead; // 또는 앞에 붙는 작은 그림 (채널 사진 등)
  const _SegChip({required this.label, required this.on, required this.onTap, this.emoji = '', this.lead});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 32,
            padding: EdgeInsets.fromLTRB(lead != null ? 4 : (emoji.isEmpty ? 14 : 10), 0, 14, 0),
            decoration: BoxDecoration(
              color: on ? kInk : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: on ? kInk : kPillLine, width: 1),
            ),
            // 글자 폭만큼만 (줄바꿈 칸에서도 가로로 늘어나지 않게)
            child: Center(
              widthFactor: 1,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (lead != null) ...[lead!, const SizedBox(width: 6)] else if (emoji.isNotEmpty) ...[Text(emoji, style: const TextStyle(fontSize: 14.5, height: 1.1)), const SizedBox(width: 5)],
                Text(label, style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? Colors.white : kInk)),
              ]),
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
      padding: const EdgeInsets.fromLTRB(18, 14, 6, 12),
      child: Row(children: [
        if (title == null) ...[
          const Text('콕', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900, color: kAccent, letterSpacing: -1, height: 1.1)),
          const Text('플', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w300, color: kInk, letterSpacing: -1, height: 1.1)),
          const SizedBox(width: 8),
          // 작은 휴대폰에선 글자가 잘려 보이느니 통째로 숨긴다
          Expanded(
            child: LayoutBuilder(
              builder: (_, c) => c.maxWidth < 104
                  ? const SizedBox()
                  : const Padding(
                      padding: EdgeInsets.only(top: 7),
                      child: Text('유튜브 맛집 지도', maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontSize: 12.5, color: kSub)),
                    ),
            ),
          ),
        ] else
          Expanded(child: Text(title!, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.4))),
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
              height: 36,
              constraints: const BoxConstraints(maxWidth: 210),
              padding: const EdgeInsets.only(left: 13, right: 10),
              decoration: BoxDecoration(
                color: open ? kInk : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: open ? kInk : kPillLine, width: 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                LineIcon('pin', size: 16, color: open ? Colors.white : kInk),
                const SizedBox(width: 5),
                Flexible(
                  child: Text('${area.sido} · ${area.name}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: open ? Colors.white : kInk)),
                ),
                Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 18, color: open ? Colors.white : kInk),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 2),
        IconButton(onPressed: onSearch, tooltip: '검색', visualDensity: VisualDensity.compact, icon: const LineIcon('search', size: 24)),
        const AccountButton(), // 로그인·내 계정 (설정 안에 숨기지 않고 늘 보이게)
      ]),
    );
  }
}

// 섹션 제목 줄 (굵은 앞말 + 가는 뒷말 + 오른쪽 작은 링크)
Widget sectionHead(String bold, String light, {String? link, VoidCallback? onLink, double pad = 20, double size = 18}) => Padding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        mixTitle(bold, light, size: size),
        const Spacer(),
        if (link != null)
          Semantics(
            button: true,
            label: link,
            onTap: onLink,
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onLink,
              behavior: HitTestBehavior.opaque,
              child: Padding(padding: const EdgeInsets.fromLTRB(10, 6, 0, 2), child: Text('$link  ›', style: const TextStyle(fontSize: 13, color: kSub))),
            ),
          ),
      ]),
    );

// ---- 홈 ----
// 메인 칸 순서 (나중에 관리자 화면에서 바꿀 수 있게 이름 목록)
const kHomeOrder = ['hero', 'roulette', 'follow', 'courses', 'tops', 'fresh', 'creators', 'cuisine'];

// 맨 위 큰 비주얼에 섞어 넘기는 배너 (관리자 화면에서 등록)
class HomeBanner {
  final String id, title, sub, image, link;
  HomeBanner(Map<String, dynamic> j)
      : id = '${j['id'] ?? ''}',
        title = '${j['title'] ?? ''}',
        sub = '${j['sub'] ?? ''}',
        image = '${j['image'] ?? ''}',
        link = '${j['link'] ?? ''}';
}

// 배너 그림: 주소이거나, 관리자 화면에서 올린 그림 글자(base64)
Widget bannerImage(HomeBanner b) {
  final fb = Container(color: const Color(0xFFE9E9EC));
  if (b.image.startsWith('http')) {
    return Image.network(b.image, fit: BoxFit.cover, webHtmlElementStrategy: WebHtmlElementStrategy.fallback, errorBuilder: (_, __, ___) => fb);
  }
  try {
    return Image.memory(base64Decode(b.image.split(',').last), fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => fb);
  } catch (_) {
    return fb;
  }
}

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
  final Future<void> Function() onRefresh; // 아래로 당겨 새로 고침
  final bool active; // 홈 탭을 보고 있는지 (맨 위 영상은 보일 때만 재생)
  final List<HomeBanner> banners; // 맨 위 비주얼에 섞을 배너
  final ValueChanged<HomeBanner>? onBanner;
  final List<String> order; // 칸 순서
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
    required this.onRefresh,
    this.active = true,
    this.banners = const [],
    this.onBanner,
    this.order = kHomeOrder,
  });

  @override
  Widget build(BuildContext context) {
    final d = data;
    // 머리말은 흰 띠, 그 아래는 옅은 회색 바탕 (흰 상자와 바탕 위 칸을 섞어서)
    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          narrowTop(KokHeader(area: area, open: regionOpen, onRegion: onRegion, onSearch: onSearch)),
          if (regionOpen) narrowTop(Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: regionPanel)),
          Expanded(
            child: ColoredBox(
              color: kPageBg,
              child: narrow(d == null
                  ? Center(
                      child: error == null
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : TextButton(onPressed: onRetry, child: const Text('자료를 받지 못했습니다 · 다시 불러오기')),
                    )
                  : RefreshIndicator(
                      onRefresh: onRefresh,
                      color: kAccent,
                      child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.only(bottom: 44), children: [
                        for (final k in order) ..._section(k, d),
                      ]),
                    )),
            ),
          ),
        ]),
      ),
    );
  }

  List<Widget> _section(String k, SongdoData d) => switch (k) {
        'hero' => [_hero(d)],
        'roulette' => [
            const SizedBox(height: 46), // 룰렛 판이 카드 위로 튀어나올 자리
            Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: RouletteBanner(onTap: onRoulette)),
          ],
        'follow' => [_follow()],
        'courses' => [_courses(d)],
        'tops' => [_tops(d)],
        'fresh' => [_fresh()],
        'creators' => [_creators(d)],
        'cuisine' => [_cuisine()],
        _ => const <Widget>[],
      };

  // 맨 위 영상: 이 동네 유튜버 순위에서 오늘의 집 → 영상이 없는 동네는 따라가기 자료에서 이 동네 최근 영상
  (Place, Video?, bool)? _heroPick(SongdoData d) {
    Video? vidOf(Place p) {
      final l = p.vids.where((x) => !x.short).toList();
      if (l.isEmpty) return null;
      return l.firstWhere((x) => x.hd, orElse: () => l.first);
    }

    final p = sessionPick(area.id, heroPool(d));
    if (p != null) {
      final v = vidOf(p);
      if (v != null) return (p, v, false);
    }
    final f = follow;
    if (f != null) {
      final near = [
        for (final q in f.places)
          if (area.contains(q.point) && vidOf(q) != null) q
      ]..sort((a, b) => vidOf(b)!.date.compareTo(vidOf(a)!.date));
      if (near.isNotEmpty) {
        final q = sessionPick('follow-${area.id}', near.take(15).toList())!;
        return (q, vidOf(q), true);
      }
    }
    final top = todaysPlace(d);
    return top == null ? null : (top, null, false);
  }

  Widget _hero(SongdoData d) {
    final pick = _heroPick(d);
    if (pick == null) return const SizedBox();
    final (p, v, fromFollow) = pick;
    return HomeHero(
      key: ValueKey('hero-${area.id}-${p.id}-${v?.id ?? ''}'),
      place: p,
      video: v,
      active: active,
      banners: banners,
      onWhere: () => fromFollow ? onFollowPlace(p) : onWhere(p),
      onBanner: onBanner,
    );
  }

  // 유튜버 따라 먹기 (전국): 바탕 위에 큰 동그라미
  Widget _follow() {
    final f = follow;
    if (f == null || f.channels.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 34),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sectionHead('유튜버 ', '따라 먹기', link: '전국 지도', onLink: () => onFollow('')),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 5, 20, 0),
          child: Text('맛집 채널이 영상에 주소를 적어 둔 집 · 전국 ${commas(f.places.length)}곳', style: const TextStyle(fontSize: 13, color: kSub)),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: f.channels.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final c = f.channels[i];
              return Semantics(
                button: true,
                label: '${c.name} 따라 먹기',
                onTap: () => onFollow(c.id),
                excludeSemantics: true,
                child: GestureDetector(onTap: () => onFollow(c.id), child: ChanAvatar(c, size: 82, lift: true)),
              );
            },
          ),
        ),
      ]),
    );
  }

  // 테마 골라 보기: 사진 한 장을 크게 깐 카드
  Widget _courses(SongdoData d) {
    final list = coursesOf(d, area);
    if (list.isEmpty) return const SizedBox();
    final used = <String>{};
    final hv = _heroPick(d)?.$2; // 맨 위 큰 사진과 같은 영상 표지는 테마 카드에 다시 쓰지 않는다
    if (hv != null) used.add(hv.id);
    final covers = <Video?>[];
    for (final c in list) {
      Video? pick;
      for (final p in c.stops) {
        final l = p.vids.where((x) => !x.short && !used.contains(x.id)).toList();
        if (l.isNotEmpty) {
          pick = l.firstWhere((x) => x.hd, orElse: () => l.first);
          break;
        }
      }
      if (pick != null) used.add(pick.id);
      covers.add(pick);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sectionHead('테마 ', '골라 보기'),
        const SizedBox(height: 14),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => ThemeCard(list[i], cover: covers[i], onTap: () => onCourse(list[i])),
          ),
        ),
      ]),
    );
  }

  // 유튜버가 많이 찾은 집: 흰 상자 안 줄 목록 (썸네일 크게)
  Widget _tops(SongdoData d) {
    final yt = ytRank(d);
    final list = (yt.isNotEmpty ? yt : popRank(d)).take(5).toList();
    if (list.isEmpty) return const SizedBox();
    return homeCard(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        yt.isNotEmpty
            ? sectionHead('유튜버가 ', '많이 찾은 집', link: '순위 전체', onLink: onRankAll, pad: 18)
            : sectionHead('지금 ', '인기 많은 집', link: '순위 전체', onLink: onRankAll, pad: 18),
        if (yt.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 5, 18, 0),
            child: Text('이 동네 유튜브 영상은 모으는 중이라, 구글 별점·리뷰 순으로 보여 드려요', style: TextStyle(fontSize: 12, color: kSub)),
          ),
        const SizedBox(height: 6),
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0) const Divider(height: 1, thickness: 1, color: kHair, indent: 18, endIndent: 18),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: YtRow(place: list[i], rank: i + 1, thumb: 112, pill: false, onTap: () => onWhere(list[i]))),
        ],
      ]),
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 8),
      margin: const EdgeInsets.fromLTRB(14, 30, 14, 0),
    );
  }

  // 새로 올라온 영상: 바탕 위에 넓은 영상 카드
  Widget _fresh() {
    final f = follow;
    if (f == null || f.fresh.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sectionHead('새로 ', '올라온 영상'),
        const SizedBox(height: 14),
        SizedBox(
          height: 262,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: f.fresh.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final (v, p) = f.fresh[i];
              return FreshCard(video: v, place: p, channel: f.names[v.cid] ?? v.channel, width: 300, onTap: () => onFollowPlace(p));
            },
          ),
        ),
      ]),
    );
  }

  // 이 동네 다녀간 유튜버: 흰 상자 안 작은 알약 (위 큰 동그라미와 다르게)
  Widget _creators(SongdoData d) {
    final list = channelsOf(d).take(10).toList();
    if (list.isEmpty) return const SizedBox();
    return homeCard(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sectionHead('이 동네 ', '다녀간 유튜버', link: '전체 보기', onLink: onAllChannels, pad: 18),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < list.length; i++) ChanChip(list[i], first: i == 0, onTap: () => onChannel(list[i])),
          ]),
        ),
      ]),
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 20),
      margin: const EdgeInsets.fromLTRB(14, 32, 14, 0),
    );
  }

  // 무엇이 당기세요?: 작은 한 줄 가로 넘김
  Widget _cuisine() => Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          sectionHead('무엇이 ', '당기세요?', link: '가게 찾기', onLink: onSearch),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: kCuisines.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => SmallChip(label: kCuisines[i], emoji: kCuisineEmoji[kCuisines[i]] ?? '', onTap: () => onCuisine(kCuisines[i])),
            ),
          ),
        ]),
      );
}

// 맨 위 큰 비주얼: 오늘의 영상 사진(천천히 다가가는 움직임) — 누르면 그때 영상 재생 + 배너를 옆으로 넘김
// 자동 재생은 하지 않는다: 수익 영상은 유튜브가 앞에 광고를 붙여 첫 화면이 남의 광고가 되기 때문
// 유튜브 규칙: 영상 위에는 글씨·표시를 올리지 않는다 · 안 보이면 멈춘다 · 한 화면에 하나
class HomeHero extends StatefulWidget {
  final Place place;
  final Video? video;
  final bool active;
  final List<HomeBanner> banners;
  final VoidCallback onWhere;
  final ValueChanged<HomeBanner>? onBanner;
  const HomeHero({super.key, required this.place, required this.video, required this.active, required this.banners, required this.onWhere, this.onBanner});
  @override
  State<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<HomeHero> with SingleTickerProviderStateMixin {
  final page = PageController();
  int index = 0;
  YoutubePlayerController? yt;
  bool sound = false; // 눌러서 영상을 보는 중
  bool seen = true; // 영상이 화면에 절반 넘게 보이는지
  ScrollPosition? _pos;
  Timer? _flip;
  // 사진이 아주 천천히 다가갔다 물러나는 움직임 (영상 대신 살아 있는 느낌만)
  late final AnimationController _zoom = AnimationController(vsync: this, duration: const Duration(seconds: 14));

  bool get hasVideo => widget.video != null;
  int get count => math.max(1, (hasVideo ? 1 : 0) + widget.banners.length);
  bool get onVideo => hasVideo && index == 0;

  @override
  void initState() {
    super.initState();
    _flip = Timer.periodic(const Duration(seconds: 6), (_) => _next());
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  YoutubePlayerController _player() => YoutubePlayerController.fromVideoId(
        videoId: widget.video!.id,
        autoPlay: true, // 누른 다음에만 만든다
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
          playsInline: true,
          strictRelatedVideos: true,
          showVideoAnnotations: false,
        ),
      );

  // 누르면 그때 소리 켜고 재생 (재생한 가게는 다음부터 추천에서 뺀다 — 새 영상이 올라오면 다시)
  void playSound() {
    if (!hasVideo) return;
    markWatched(widget.place);
    if (index != 0 && page.hasClients) page.jumpToPage(0);
    final old = yt;
    setState(() {
      sound = true;
      yt = _player();
    });
    old?.close();
    _sync();
  }

  // 안 보이면 영상은 멈추고, 사진 움직임도 쉰다 (보일 때만 천천히 움직임)
  void _sync() {
    if (!mounted) return;
    final show = widget.active && seen && onVideo;
    final c = yt;
    if (c != null && !show) c.pauseVideo().catchError((_) {});
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (show && c == null && !still) {
      if (!_zoom.isAnimating) _zoom.repeat(reverse: true);
    } else if (_zoom.isAnimating) {
      _zoom.stop();
    }
  }

  void _next() {
    if (!mounted || count < 2 || !page.hasClients) return;
    if (onVideo && sound) return; // 영상을 보는 동안은 넘기지 않음
    page.animateToPage((index + 1) % count, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = Scrollable.maybeOf(context)?.position;
    if (!identical(p, _pos)) {
      _pos?.removeListener(_onScroll);
      _pos = p;
      _pos?.addListener(_onScroll);
    }
  }

  void _onScroll() {
    final w = context.size?.width ?? 0;
    final s = (_pos?.pixels ?? 0) < w * 9 / 16 / 2;
    if (s != seen) {
      seen = s;
      _sync();
    }
  }

  @override
  void didUpdateWidget(HomeHero old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  @override
  void dispose() {
    _pos?.removeListener(_onScroll);
    _flip?.cancel();
    _zoom.dispose();
    yt?.close();
    page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.place, v = widget.video;
    final tint = kindTint(p.kind);
    final plain = Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint, tint.withValues(alpha: 0.72)])),
      alignment: Alignment.center,
      child: KindGlyph(kind: p.kind, size: 64, bg: tint),
    );
    Widget videoSlide() {
      final c = yt;
      if (c != null) return YoutubePlayer(controller: c, aspectRatio: 16 / 9);
      // 사진(천천히 다가감) + 가운데 재생 표시 — 누르면 그때 영상
      return Semantics(
        button: true,
        label: '영상 보기',
        onTap: playSound,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: playSound,
          child: Stack(fit: StackFit.expand, children: [
            ClipRect(
              child: AnimatedBuilder(
                animation: _zoom,
                builder: (_, child) => Transform.scale(
                  scale: 1.0 + 0.07 * Curves.easeInOut.transform(_zoom.value),
                  alignment: const Alignment(0, -0.15),
                  child: child,
                ),
                child: ytWide(v!, fallback: plain),
              ),
            ),
            Center(
              child: ClipOval(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: 58,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.32),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 3),
                      child: Icon(Icons.play_arrow_rounded, size: 34, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
    }

    final slides = <Widget>[
      if (v != null) videoSlide(),
      for (final b in widget.banners) GestureDetector(onTap: () => widget.onBanner?.call(b), child: bannerImage(b)),
    ];
    if (slides.isEmpty) slides.add(GestureDetector(onTap: widget.onWhere, child: plain));
    final bi = index - (v != null ? 1 : 0);
    final banner = bi >= 0 && bi < widget.banners.length ? widget.banners[bi] : null;
    return ColoredBox(
      color: Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: PageView(
            controller: page,
            onPageChanged: (i) {
              setState(() => index = i);
              _sync();
            },
            children: slides,
          ),
        ),
        if (slides.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < slides.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: i == index ? 16 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(color: i == index ? kInk : const Color(0xFFD5D7DC), borderRadius: BorderRadius.circular(3)),
                ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 20),
          child: banner != null ? _bannerInfo(banner) : _placeInfo(p, v),
        ),
      ]),
    );
  }

  Widget _placeInfo(Place p, Video? v) {
    final n = ytCount(p);
    final o = openInfo(p);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(v == null ? '오늘의 추천' : '추천 영상', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kAccent)),
        if (n > 0) ...[
          const SizedBox(width: 8),
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: kAccentTint, borderRadius: BorderRadius.circular(11)),
            child: Text('유튜버 $n명 방문', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kAccent)),
          ),
        ],
        const Spacer(),
        if (v != null && !sound)
          Semantics(
            button: true,
            label: '영상 보기',
            onTap: playSound,
            excludeSemantics: true,
            child: GestureDetector(
              onTap: playSound,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.play_circle_outline_rounded, size: 17, color: kSub),
                  const SizedBox(width: 3),
                  Text(v.dur > 0 ? '영상 보기 · ${durText(v.dur)}' : '영상 보기', style: const TextStyle(fontSize: 12.5, color: kSub)),
                ]),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 7),
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.5, height: 1.25)),
            const SizedBox(height: 4),
            Text(
                [
                  if (v != null) v.channel,
                  if (dongOf(p).isNotEmpty) dongOf(p) else if (p.gu.isNotEmpty) p.gu,
                  if (v == null && p.cat.isNotEmpty) p.cat,
                  if (o != null) o.short
                ].where((x) => x.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, color: kSub)),
          ]),
        ),
        const SizedBox(width: 12),
        Semantics(
          button: true,
          label: '이 집 어디야',
          onTap: widget.onWhere,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: widget.onWhere,
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(21)),
              child: const Text('이 집 어디야', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _bannerInfo(HomeBanner b) => Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('콕플 소식', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kAccent)),
            const SizedBox(height: 7),
            Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.5, height: 1.25)),
            if (b.sub.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(b.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, color: kSub)),
            ],
          ]),
        ),
        if (b.link.isNotEmpty) ...[
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => widget.onBanner?.call(b),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(21)),
              child: const Text('자세히 보기', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ]);
}

// 테마 카드: 사진 한 장을 크게 깔고 그 위에 글자 (아래쪽만 살짝 어둡게)
class ThemeCard extends StatelessWidget {
  final Course c;
  final Video? cover; // 카드 사진 (앞 카드와 겹치지 않게 골라서 넘김)
  final VoidCallback onTap;
  const ThemeCard(this.c, {super.key, this.cover, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cover = this.cover;
    final kind = c.stops.isNotEmpty ? c.stops.first.kind : 'food';
    final tint = kindTint(kind);
    final plain = Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint, tint.withValues(alpha: 0.7)])),
      alignment: Alignment.topRight,
      padding: const EdgeInsets.all(18),
      child: KindGlyph(kind: kind, size: 44, bg: tint),
    );
    return Semantics(
      button: true,
      label: c.name,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 292,
            height: 200,
            child: Stack(fit: StackFit.expand, children: [
              if (cover == null) plain else ytWide(cover, fallback: plain),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      color: const Color(0x73000000),
                      padding: const EdgeInsets.fromLTRB(18, 13, 18, 14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: c.bold, style: const TextStyle(fontWeight: FontWeight.w800)),
                      TextSpan(text: c.light, style: const TextStyle(fontWeight: FontWeight.w300)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 21, color: Colors.white, letterSpacing: -0.5, height: 1.25),
                  ),
                  const SizedBox(height: 3),
                  Text(c.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xE6FFFFFF))),
                ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// 이 동네 다녀간 유튜버: 작은 알약 (사진 + 이름 + 가게 수)
class ChanChip extends StatelessWidget {
  final Chan c;
  final bool first;
  final VoidCallback onTap;
  const ChanChip(this.c, {super.key, this.first = false, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: c.name,
        onTap: onTap,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.only(left: 4, right: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: first ? kAccent : kPillLine, width: 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ChanAvatar(c, label: false, size: 32),
              const SizedBox(width: 8),
              Text(c.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kInk)),
              const SizedBox(width: 5),
              Text('${c.places.length}', style: const TextStyle(fontSize: 12, color: kSub)),
            ]),
          ),
        ),
      );
}

// 작은 알약 단추 (그림 글자 + 이름) — 홈 맨 아래 음식 종류
class SmallChip extends StatelessWidget {
  final String label, emoji;
  final VoidCallback onTap;
  const SmallChip({super.key, required this.label, this.emoji = '', required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: kPillLine, width: 1)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (emoji.isNotEmpty) ...[Text(emoji, style: const TextStyle(fontSize: 17, height: 1.1)), const SizedBox(width: 6)],
              Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kInk)),
            ]),
          ),
        ),
      );
}

// 오늘 뭐 먹지? (홈 띠)
class RouletteBanner extends StatefulWidget {
  final VoidCallback onTap;
  const RouletteBanner({super.key, required this.onTap});
  @override
  State<RouletteBanner> createState() => _RouletteBannerState();
}

class _RouletteBannerState extends State<RouletteBanner> with SingleTickerProviderStateMixin {
  static const turns = [1.35, 0.8, 1.6, 1.1]; // 한 번에 도는 바퀴 (멈추는 자리가 매번 다르게)
  double base = 0; // 지금까지 돈 바퀴
  int round = 0;
  late final AnimationController ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))
    ..addStatusListener((st) {
      if (st == AnimationStatus.completed && mounted) {
        base += turns[round % turns.length];
        round++;
        ctl.forward(from: 0);
      }
    })
    ..forward();

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  // 앞 45%: 휙 돌다가 살짝 넘쳤다 멈춤, 나머지: 쉼
  double get angle {
    final t = ctl.value;
    final f = t < 0.45 ? Curves.easeOutBack.transform(t / 0.45) : 1.0;
    return (base + turns[round % turns.length] * f) * 2 * math.pi;
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '오늘 뭐 먹지?',
        onTap: widget.onTap,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: double.infinity,
              height: 132,
              padding: const EdgeInsets.fromLTRB(22, 20, 150, 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE6DD), Color(0xFFFFF3E2)]),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('고민될 땐 돌려 보세요', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFB4532F))),
                const SizedBox(height: 4),
                mixTitle('오늘 ', '뭐 먹지?', size: 23),
                const Spacer(),
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(18)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('룰렛 돌리기', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white)),
                    SizedBox(width: 4),
                    Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
                  ]),
                ),
              ]),
            ),
            Positioned(
              right: 2,
              top: -30,
              child: AnimatedBuilder(
                animation: ctl,
                builder: (_, __) => SizedBox(width: 152, height: 158, child: CustomPaint(painter: _BannerWheel(angle))),
              ),
            ),
          ]),
        ),
      );
}

// 홈 띠의 룰렛 판: 색 칸 + 음식 그림 + 가운데 「콕」 + 위 바늘
class _BannerWheel extends CustomPainter {
  final double angle;
  _BannerWheel(this.angle);
  static const colors = [Color(0xFFFF5A4E), Color(0xFFFFC531), Color(0xFF3EC79B), Color(0xFFFF9A3D), Color(0xFF5AA9FF), Color(0xFFFF7AA2), Color(0xFF9B7BFF), Color(0xFFFFD86B)];
  static const foods = ['🍜', '🍣', '🍕', '☕', '🥟', '🍰', '🍗', '🍔'];
  @override
  void paint(Canvas c, Size s) {
    final r = s.width / 2 - 4;
    final center = Offset(s.width / 2, s.height - r - 4);
    // 판 그림자 (고르게 퍼지게)
    c.drawCircle(center, r + 2, Paint()..color = const Color(0x22000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    c.drawCircle(center, r + 3, Paint()..color = Colors.white);
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(angle);
    const n = 8;
    const seg = 2 * math.pi / n;
    final rect = Rect.fromCircle(center: Offset.zero, radius: r);
    for (var i = 0; i < n; i++) {
      c.drawArc(rect, -math.pi / 2 + i * seg, seg, true, Paint()..color = colors[i]);
    }
    final sep = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * seg;
      c.drawLine(Offset.zero, Offset(math.cos(a) * r, math.sin(a) * r), sep);
    }
    for (var i = 0; i < n; i++) {
      final mid = -math.pi / 2 + (i + 0.5) * seg;
      final tp = TextPainter(text: TextSpan(text: foods[i], style: const TextStyle(fontSize: 17)), textDirection: TextDirection.ltr)..layout();
      c.save();
      c.rotate(mid + math.pi / 2);
      tp.paint(c, Offset(-tp.width / 2, -r * 0.78));
      c.restore();
    }
    c.restore();
    // 테두리 점 (전구처럼)
    for (var i = 0; i < 16; i++) {
      final a = i * math.pi / 8;
      c.drawCircle(center + Offset(math.cos(a), math.sin(a)) * (r + 0.5), 1.6, Paint()..color = i.isEven ? const Color(0xFFFFE08A) : Colors.white);
    }
    // 가운데
    c.drawCircle(center, r * 0.25, Paint()..color = Colors.white);
    c.drawCircle(center, r * 0.25, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFFFD2C4));
    final hub = TextPainter(
      text: const TextSpan(text: '콕', style: TextStyle(fontFamily: 'Pretendard', fontSize: 15, fontWeight: FontWeight.w900, color: kAccent)),
      textDirection: TextDirection.ltr,
    )..layout();
    hub.paint(c, center - Offset(hub.width / 2, hub.height / 2));
    // 위 바늘
    final top = Offset(center.dx, center.dy - r - 6);
    final needle = ui.Path()
      ..moveTo(top.dx - 9, top.dy - 2)
      ..lineTo(top.dx + 9, top.dy - 2)
      ..lineTo(top.dx, top.dy + 14)
      ..close();
    c.drawShadow(needle, Colors.black, 2, false);
    c.drawPath(needle, Paint()..color = kInk);
    c.drawCircle(Offset(top.dx, top.dy + 1), 2.6, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _BannerWheel o) => o.angle != angle;
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
          width: 268,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            mixTitle(c.bold, c.light, size: 17),
            const SizedBox(height: 3),
            Text(c.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: kSub)),
            const SizedBox(height: 12),
            Row(children: [
              for (var i = 0; i < math.min(s.length, 4); i++) ...[
                if (i > 0) const SizedBox(width: 5),
                ytSmall(s[i], 54, r: 6),
              ],
            ]),
            const SizedBox(height: 11),
            Text([for (var i = 0; i < math.min(s.length, 4); i++) '${i + 1} ${s[i].name}'].join('  '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: kInk, height: 1.3)),
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
  final double width;
  const FreshCard({super.key, required this.video, required this.place, required this.channel, required this.onTap, this.width = 244});
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
          width: width,
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
                        child: Text(badge, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 9),
            Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk, height: 1.32)),
            const SizedBox(height: 4),
            Text([channel, agoText(v.date)].where((x) => x.isNotEmpty).join(' · '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: kSub)),
            Text([place.name, [sidoShort(place.sido), place.gu].where((x) => x.isNotEmpty).join(' ')].where((x) => x.isNotEmpty).join(' · '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: kSub)),
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
          _SegChip(label: '전체', emoji: '🎬', on: current.isEmpty, onTap: () => onPick('')),
          for (final c in f.channels) ...[
            const SizedBox(width: 6),
            _SegChip(
              label: c.name,
              on: current == c.id,
              onTap: () => onPick(c.id),
              lead: ClipOval(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: c.thumb.isEmpty
                      ? Container(color: kAccentTint, alignment: Alignment.center, child: Text(c.initial, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kAccent)))
                      : Image.network(c.thumb, fit: BoxFit.cover, webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                          errorBuilder: (_, __, ___) => Container(color: kAccentTint)),
                ),
              ),
            ),
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
  final double size; // 동그라미 지름
  final bool lift; // 회색 바탕 위: 흰 테 + 옅은 그림자
  const ChanAvatar(this.c, {super.key, this.ring = kPillLine, this.label = true, this.size = 66, this.lift = false});
  static const _bgs = [Color(0xFF3D3D46), Color(0xFF5A4A3C), Color(0xFF46505A), Color(0xFF4F4652), Color(0xFF3F4D45)];
  @override
  Widget build(BuildContext context) {
    final bg = _bgs[c.name.hashCode.abs() % _bgs.length];
    final initial = Container(
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(c.initial, style: TextStyle(fontSize: size * 0.24, fontWeight: FontWeight.w700, color: Colors.white)),
    );
    final circle = Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size >= 40 ? 2 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: lift ? Colors.white : null,
        border: size >= 40 ? Border.all(color: lift ? Colors.white : ring, width: 1) : null,
        boxShadow: lift ? [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 10)] : null,
      ),
      child: c.thumb.isEmpty
          ? initial
          : ClipOval(
              child: Image.network(
                c.thumb,
                fit: BoxFit.cover,
                width: size,
                height: size,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                errorBuilder: (_, __, ___) => initial,
              ),
            ),
    );
    if (!label) return circle;
    return SizedBox(
      width: size + 8,
      child: Column(children: [
        circle,
        const SizedBox(height: 7),
        Text(c.name,
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kInk)),
        const SizedBox(height: 1),
        Text('${c.places.length}곳', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w400, color: kSub)),
      ]),
    );
  }
}

// 유튜버가 찾은 집 한 줄 (시안)
class YtRow extends StatelessWidget {
  final Place place;
  final int rank;
  final VoidCallback onTap;
  final double thumb; // 썸네일 너비
  final bool pill; // 오른쪽 알약 (끄면 유튜버 수를 둘째 줄 앞에)
  const YtRow({super.key, required this.place, required this.rank, required this.onTap, this.thumb = 92, this.pill = true});
  @override
  Widget build(BuildContext context) {
    final n = ytCount(place);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(children: [
          SizedBox(
            width: 20,
            child: Text('$rank', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: rank == 1 ? kAccent : kInk)),
          ),
          const SizedBox(width: 10),
          ytSmall(place, thumb),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(place.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.3)),
              const SizedBox(height: 3),
              Text.rich(
                  TextSpan(children: [
                    if (!pill && n > 0) TextSpan(text: '유튜버 $n명 · ', style: const TextStyle(fontWeight: FontWeight.w700, color: kAccent)),
                    TextSpan(text: [if (myPos.value != null) distText(meters(myPos.value!, place.point)), metaOf(place)].join(' · ')),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: kSub)),
              if (oneLine(place).isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(oneLine(place), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: kInk)),
              ],
            ]),
          ),
          if (pill) ...[
            const SizedBox(width: 8),
            if (n > 0)
              _Pill('유튜버 $n명')
            else if (place.grate > 0)
              _Pill('★ ${place.grate.toStringAsFixed(1)}'),
          ],
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
  final Future<void> Function() onRefresh; // 아래로 당겨 새로 고침
  const VideoView({
    super.key,
    required this.data,
    required this.area,
    required this.regionOpen,
    required this.regionPanel,
    required this.onRegion,
    required this.onSearch,
    required this.onWhere,
    required this.onRefresh,
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
    Widget item((Video, Place) it, bool phone) {
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
                    width: phone ? 34 : 44,
                    height: phone ? 34 : 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), shape: BoxShape.circle),
                    child: LineIcon('play', size: phone ? 13 : 17),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(v.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: phone ? 12.5 : 14, fontWeight: FontWeight.w600, color: kInk, height: 1.3)),
        const SizedBox(height: 3),
        Text('${v.channel} · ${p.name}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: phone ? 10.5 : 11.5, fontWeight: FontWeight.w300, color: kSub)),
        const SizedBox(height: 3),
        Semantics(
          button: true,
          label: '이 집 어디야',
          onTap: () => onWhere(p),
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () => onWhere(p),
            child: Text('📍 이 집 어디야', style: TextStyle(fontSize: phone ? 11 : 11.5, fontWeight: FontWeight.w700, color: kAccent)),
          ),
        ),
      ]);
    }

    return SafeArea(
      bottom: false,
      child: LayoutBuilder(builder: (_, c) {
        // 휴대폰도 태블릿도 한 줄에 2개 (태블릿은 넓게)
        const cols = 2;
        final phone = c.maxWidth < 600;
        final width = math.min(c.maxWidth, 1040.0);
        final gap = phone ? 12.0 : 16.0;
        final side = phone ? 16.0 : 20.0;
        final itemW = (width - side * 2 - gap) / cols;
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
                    : RefreshIndicator(
                        onRefresh: onRefresh,
                        color: kAccent,
                        child: GridView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(side, 4, side, 24),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: gap,
                          mainAxisSpacing: phone ? 18 : 22,
                          mainAxisExtent: itemW * 9 / 16 + (phone ? 84 : 80),
                        ),
                        itemCount: items.length,
                        itemBuilder: (_, i) => item(items[i], phone),
                      )),
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
  final Future<void> Function() onRefresh; // 아래로 당겨 새로 고침
  const SavedView(
      {super.key,
      required this.koks,
      required this.recents,
      required this.onOpen,
      required this.onRemove,
      required this.onRemoveRecent,
      required this.onClearRecents,
      required this.onRefresh});
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
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
          child: AccountStrip(koks: koks.length),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 6),
          child: Row(children: [
            _SegChip(label: koks.isEmpty ? '콕한 집' : '콕한 집 ${koks.length}', emoji: '📌', on: w == 0, onTap: () => setState(() => which = 0)),
            const SizedBox(width: 6),
            _SegChip(label: recents.isEmpty ? '최근 본 집' : '최근 본 집 ${recents.length}', emoji: '🕘', on: w == 1, onTap: () => setState(() => which = 1)),
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
              : RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  color: kAccent,
                  child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, thickness: 1, color: kHair),
                  itemBuilder: (_, i) => w == 0
                      ? row(list[i], onRemove: () => widget.onRemove(list[i]), removeTip: '콕 빼기')
                      : row(list[i], onRemove: () => widget.onRemoveRecent(list[i]), removeTip: '목록에서 지우기', when: true),
                )),
        ),
      ])),
    );
  }
}

// ---- 아래 탭 ----
// 아래 탭 아이콘: 가는 선 + 색 채움 (고른 탭은 진한 색, 안 고른 탭은 옅은 색) — 김부장 그림
const kNavIcons = <String, String>{
  'home_on': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32"><g fill="none" stroke="#23262D" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M23.4 3.6c.5-1 1.9-1.2 2.6-.4" stroke-width="1.2"/><rect x="20.4" y="6" width="3.4" height="6.2" rx=".7" fill="#FF4B2B"/><path d="M7.8 14.2v11a2 2 0 0 0 2 2h12.4a2 2 0 0 0 2-2v-11" fill="#FFF4E2"/><path d="M3.9 15.6L15 6.1a1.6 1.6 0 0 1 2 0l11.1 9.5a.9.9 0 0 1-.6 1.6H4.5a.9.9 0 0 1-.6-1.6z" fill="#FF4B2B"/><path d="M13.4 27.2v-4.6a2.6 2.6 0 0 1 5.2 0v4.6z" fill="#FFC531"/><circle cx="17.3" cy="24.6" r=".6" fill="#23262D" stroke="none"/><rect x="9.6" y="19.4" width="2.6" height="2.6" rx=".5" fill="#7CC4FF" stroke-width="1.3"/><rect x="19.8" y="19.4" width="2.6" height="2.6" rx=".5" fill="#7CC4FF" stroke-width="1.3"/></g></svg>',
  'home_off': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32"><g fill="none" stroke="#23262D" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M23.4 3.6c.5-1 1.9-1.2 2.6-.4" stroke-width="1.2"/><rect x="20.4" y="6" width="3.4" height="6.2" rx=".7" fill="#FFC9BD"/><path d="M7.8 14.2v11a2 2 0 0 0 2 2h12.4a2 2 0 0 0 2-2v-11" fill="#FFFFFF"/><path d="M3.9 15.6L15 6.1a1.6 1.6 0 0 1 2 0l11.1 9.5a.9.9 0 0 1-.6 1.6H4.5a.9.9 0 0 1-.6-1.6z" fill="#FFC9BD"/><path d="M13.4 27.2v-4.6a2.6 2.6 0 0 1 5.2 0v4.6z" fill="#FFE7A6"/><circle cx="17.3" cy="24.6" r=".6" fill="#23262D" stroke="none"/><rect x="9.6" y="19.4" width="2.6" height="2.6" rx=".5" fill="#D9EEFF" stroke-width="1.3"/><rect x="19.8" y="19.4" width="2.6" height="2.6" rx=".5" fill="#D9EEFF" stroke-width="1.3"/></g></svg>',
  'video_on': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32"><g fill="none" stroke="#23262D" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M16 9.6L11.2 4.4M16 9.6l5.3-5.8"/><circle cx="11" cy="4.2" r="1.3" fill="#FF4B2B"/><circle cx="21.5" cy="3.6" r="1.3" fill="#FF4B2B"/><rect x="3.8" y="9.6" width="24.4" height="16.6" rx="4" fill="#FFC531"/><rect x="6.8" y="12.6" width="14.4" height="10.6" rx="2.4" fill="#FFFFFF"/><path d="M12.6 15.3v5.2l4.4-2.6z" fill="#FF4B2B" stroke-width="1.3"/><circle cx="24.6" cy="15.2" r="1.25" fill="#FFFFFF" stroke-width="1.3"/><circle cx="24.6" cy="20.2" r="1.25" fill="#FFFFFF" stroke-width="1.3"/><path d="M9.2 26.2l-1.2 2.4M22.8 26.2l1.2 2.4"/></g></svg>',
  'video_off': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32"><g fill="none" stroke="#23262D" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M16 9.6L11.2 4.4M16 9.6l5.3-5.8"/><circle cx="11" cy="4.2" r="1.3" fill="#FFC9BD"/><circle cx="21.5" cy="3.6" r="1.3" fill="#FFC9BD"/><rect x="3.8" y="9.6" width="24.4" height="16.6" rx="4" fill="#FFE7A6"/><rect x="6.8" y="12.6" width="14.4" height="10.6" rx="2.4" fill="#FFFFFF"/><path d="M12.6 15.3v5.2l4.4-2.6z" fill="#FFC9BD" stroke-width="1.3"/><circle cx="24.6" cy="15.2" r="1.25" fill="#FFFFFF" stroke-width="1.3"/><circle cx="24.6" cy="20.2" r="1.25" fill="#FFFFFF" stroke-width="1.3"/><path d="M9.2 26.2l-1.2 2.4M22.8 26.2l1.2 2.4"/></g></svg>',
  'map_on': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32"><g fill="none" stroke="#23262D" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3.6 8.4L11 5.6v19.3l-7.4 2.8z" fill="#7EDBB9"/><path d="M11 5.6l9.8 2.8v19.3L11 24.9z" fill="#3EC79B"/><path d="M20.8 8.4l7.6-2.8v19.3l-7.6 2.8z" fill="#7EDBB9"/><path d="M6.4 22.6c2.2-1.2 3.4-3 5.8-3.4 2.4-.4 3.4 1 5.6-.2" stroke-dasharray="1.6 2.2" stroke-width="1.4"/><path d="M21.8 21.4s-4.4-4.2-4.4-7.6a4.4 4.4 0 0 1 8.8 0c0 3.4-4.4 7.6-4.4 7.6z" fill="#FF4B2B"/><circle cx="21.8" cy="13.8" r="1.6" fill="#FFFFFF" stroke-width="1.3"/></g></svg>',
  'map_off': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32"><g fill="none" stroke="#23262D" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3.6 8.4L11 5.6v19.3l-7.4 2.8z" fill="#DDF5EC"/><path d="M11 5.6l9.8 2.8v19.3L11 24.9z" fill="#C3EEDF"/><path d="M20.8 8.4l7.6-2.8v19.3l-7.6 2.8z" fill="#DDF5EC"/><path d="M6.4 22.6c2.2-1.2 3.4-3 5.8-3.4 2.4-.4 3.4 1 5.6-.2" stroke-dasharray="1.6 2.2" stroke-width="1.4"/><path d="M21.8 21.4s-4.4-4.2-4.4-7.6a4.4 4.4 0 0 1 8.8 0c0 3.4-4.4 7.6-4.4 7.6z" fill="#FFC9BD"/><circle cx="21.8" cy="13.8" r="1.6" fill="#FFFFFF" stroke-width="1.3"/></g></svg>',
  'kok_on': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32"><g fill="none" stroke="#23262D" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><ellipse cx="16" cy="28.4" rx="5" ry="1.3" fill="#23262D" fill-opacity="0.16" stroke="none"/><path d="M16 27.4s-9-8.2-9-14.4a9 9 0 0 1 18 0c0 6.2-9 14.4-9 14.4z" fill="#FF4B2B"/><path d="M16 17.6c-.3-.2-4-2.7-4-5.2a2.2 2.2 0 0 1 4-1.3 2.2 2.2 0 0 1 4 1.3c0 2.5-3.7 5-4 5.2z" fill="#FFFFFF" stroke-width="1.3"/><path d="M27.2 3.4v3.2M25.6 5h3.2" stroke="#FFC531" stroke-width="1.6"/><path d="M4.6 6.2v2.2M3.5 7.3h2.2" stroke="#FFC531" stroke-width="1.4"/></g></svg>',
  'kok_off': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32"><g fill="none" stroke="#23262D" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><ellipse cx="16" cy="28.4" rx="5" ry="1.3" fill="#23262D" fill-opacity="0.08" stroke="none"/><path d="M16 27.4s-9-8.2-9-14.4a9 9 0 0 1 18 0c0 6.2-9 14.4-9 14.4z" fill="#FFC9BD"/><path d="M16 17.6c-.3-.2-4-2.7-4-5.2a2.2 2.2 0 0 1 4-1.3 2.2 2.2 0 0 1 4 1.3c0 2.5-3.7 5-4 5.2z" fill="#FFFFFF" stroke-width="1.3"/><path d="M27.2 3.4v3.2M25.6 5h3.2" stroke="#FFE7A6" stroke-width="1.6"/><path d="M4.6 6.2v2.2M3.5 7.3h2.2" stroke="#FFE7A6" stroke-width="1.4"/></g></svg>',
};

class NavIcon extends StatelessWidget {
  final String name;
  final bool on;
  final double size;
  const NavIcon(this.name, {super.key, required this.on, this.size = 32});
  @override
  Widget build(BuildContext context) => AnimatedScale(
        scale: on ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        child: SvgPicture.string(kNavIcons['${name}_${on ? 'on' : 'off'}']!, width: size, height: size),
      );
}

class KokNav extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onTap;
  final VoidCallback onCenter; // 가운데 「오늘 뭐 먹지?」 (룰렛)
  const KokNav({super.key, required this.tab, required this.onTap, required this.onCenter});
  @override
  Widget build(BuildContext context) {
    Widget item(int i, String icon, String label) => Expanded(
          child: Semantics(
            button: true,
            label: label,
            selected: tab == i,
            onTap: () => onTap(i),
            excludeSemantics: true,
            child: InkWell(
              onTap: () => onTap(i),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                NavIcon(icon, on: tab == i),
                const SizedBox(height: 3),
                Text(label,
                    style: TextStyle(
                        fontSize: 13, fontWeight: tab == i ? FontWeight.w700 : FontWeight.w500, color: tab == i ? kInk : const Color(0xFF555A63), height: 1.1)),
              ]),
            ),
          ),
        );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kHair, width: 1))),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kHomeMax),
            child: SizedBox(
              height: 68,
              child: Row(children: [
                item(0, 'home', '홈'),
                item(1, 'video', '영상'),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: '뭐 먹지 돌리기',
                    onTap: onCenter,
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: onCenter,
                      behavior: HitTestBehavior.opaque,
                      child: Center(child: Transform.translate(offset: const Offset(0, -13), child: const _CenterBtn())),
                    ),
                  ),
                ),
                item(2, 'map', '지도'),
                item(3, 'kok', '내 콕'),
              ]),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

// 가운데 둥근 단추: 오늘 뭐 먹지? (누르면 룰렛)
class _CenterBtn extends StatelessWidget {
  const _CenterBtn();
  @override
  Widget build(BuildContext context) => Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFF3D5E), Color(0xFFFF7A2E)]),
          boxShadow: [BoxShadow(color: const Color(0xFFFF5A3C).withValues(alpha: 0.32), blurRadius: 16)],
        ),
        padding: const EdgeInsets.all(8),
        child: MediaQuery.withNoTextScaling(
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('오늘', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xE6FFFFFF), height: 1.1)),
              SizedBox(height: 1),
              Text('뭐 먹지?', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1, letterSpacing: -0.3)),
            ]),
          ),
        ),
      );
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
              ValueListenableBuilder<int>(
                valueListenable: authTick,
                builder: (_, __, ___) {
                  final u = fbUser;
                  final nm = u == null ? '' : ((u.displayName ?? '').isNotEmpty ? u.displayName! : (u.email ?? '회원'));
                  return group('계정', [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        const CircleAvatar(radius: 22, backgroundColor: Color(0xFFF1F1F4), child: LineIcon('user', size: 22, color: kSub)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(u == null ? '로그인하지 않았어요' : nm, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
                            const SizedBox(height: 2),
                            Text(u == null ? '로그인 없이도 모든 기능을 쓸 수 있어요' : (u.email ?? ''),
                                style: const TextStyle(fontSize: 11.5, color: kSub)),
                          ]),
                        ),
                      ]),
                    ),
                    if (u == null)
                      row('로그인 · 회원가입', sub: '카카오 · 구글 · 이메일', onTap: () => openLogin(context))
                    else ...[
                      if (adminUnverified)
                        row('관리자 메일 인증',
                            sub: '받은 메일의 링크를 누른 뒤 여기를 눌러 주세요',
                            onTap: () async {
                              final m = await checkVerify();
                              if (context.mounted) admToast(context, m);
                            }),
                      if (isAdmin)
                        row('관리자 화면',
                            sub: '배너 · 팝업 · 메인 순서 · 가게 관리',
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPage(places: allPlaces(), onChanged: onAdminChanged)))),
                      row('로그아웃', onTap: () => fbAuth.signOut()),
                      row('회원 탈퇴', sub: '계정을 지워요', onTap: () => leaveAccount(context)),
                    ],
                  ]);
                },
              ),
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
