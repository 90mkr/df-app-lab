part of 'main.dart';

// ---------------- 후기 (스티커가 주인공) ----------------
// 저장: reviews/{가게id_회원id_날짜} (같은 가게 하루 한 개) · reviewImg/{후기id_0~2} 사진 원본 · reports/{후기id_신고자id}
// 파이어베이스 무료 요금제라 사진도 문서에 글자(base64)로 넣는다 — 원본은 1080px, 목록용 작은 사진(320px)은 후기 안에.

const kStickers = <String, String>{
  'yt_ok': '유튜버 입맛 인정',
  'again': '또 올 집',
  'life': '인생 맛집',
  'meh': '기대보다 아쉬움',
  'wait_ok': '웨이팅할 만함',
  'wait_no': '웨이팅은 비추',
  'big': '양 많음',
  'value': '가성비 굿',
  'solo': '혼밥 OK',
  'date': '데이트 추천',
  'kind': '사장님 친절',
  'menu': '꼭 시키세요',
};
const kStickerGroups = <(String, List<String>)>[
  ('맛은 어땠나요?', ['yt_ok', 'again', 'life', 'meh']),
  ('어떤 집이었나요?', ['wait_ok', 'wait_no', 'big', 'value', 'solo', 'date', 'kind']),
];
// 함께 붙일 수 없는 짝 (하나를 고르면 다른 하나는 빠짐)
const kStickerClash = {'wait_ok': 'wait_no', 'wait_no': 'wait_ok', 'life': 'meh', 'meh': 'life'};
const kStickerMax = 5;
const kStickerInk = Color(0xFF501101); // 스티커 선 색 (메뉴 판 글씨)
const kReportWhy = ['광고·홍보 글', '욕설·비하', '사람 얼굴·개인정보 사진', '이 가게와 상관없는 내용', '기타'];

String stickerName(String k, [String menu = '']) => k == 'menu' ? (menu.trim().isEmpty ? '꼭 시키세요' : '${menu.trim()} 꼭 시키세요') : (kStickers[k] ?? k);

// 한국 날짜를 20261122 같은 숫자로
int kDayNum([DateTime? t]) {
  final k = (t ?? DateTime.now()).toUtc().add(const Duration(hours: 9));
  return k.year * 10000 + k.month * 100 + k.day;
}

String agoTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return '방금';
  if (d.inMinutes < 60) return '${d.inMinutes}분 전';
  if (d.inHours < 24) return '${d.inHours}시간 전';
  if (d.inDays < 7) return '${d.inDays}일 전';
  return '${t.month}월 ${t.day}일';
}

// 메뉴 이름이 길면 가운데 띄어쓰기에서 두 줄로
String _menuLines(String m) {
  final s = m.trim();
  if (s.length <= 5 || !s.contains(' ')) return s;
  final mid = s.length / 2;
  var best = -1;
  for (var i = 0; i < s.length; i++) {
    if (s[i] == ' ' && (best < 0 || (i - mid).abs() < (best - mid).abs())) best = i;
  }
  return best < 0 ? s : '${s.substring(0, best)}\n${s.substring(best + 1)}';
}

// 스티커 그림 (메뉴 스티커는 판 위에 메뉴 이름을 씀)
class StickerImg extends StatelessWidget {
  final String k;
  final double size;
  final String menu;
  const StickerImg(this.k, {super.key, this.size = 72, this.menu = ''});
  @override
  Widget build(BuildContext context) {
    final img = Image.asset('assets/stickers/$k.png', width: size, height: size, fit: BoxFit.contain, filterQuality: FilterQuality.medium, gaplessPlayback: true);
    final label = stickerName(k, menu);
    if (k != 'menu' || menu.trim().isEmpty) return Semantics(label: label, image: true, excludeSemantics: true, child: img);
    return Semantics(
      label: label,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(children: [
          img,
          Positioned(
            left: size * 0.31,
            top: size * 0.12,
            width: size * 0.565,
            height: size * 0.235,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_menuLines(menu),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(fontSize: size * 0.115, fontWeight: FontWeight.w900, color: kStickerInk, height: 1.08, letterSpacing: -0.4)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// 작은 자리용: 이름표를 빼고 캐릭터 쪽만
class StickerFace extends StatelessWidget {
  final String k;
  final double size;
  const StickerFace(this.k, {super.key, this.size = 26});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size * 0.70,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: size,
            maxHeight: size,
            child: Image.asset('assets/stickers/$k.png', width: size, height: size, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
          ),
        ),
      );
}

// 스티커 여러 장을 살짝 겹치고 기울여서 (붙인 느낌)
class StickerPile extends StatelessWidget {
  final List<String> st;
  final String menu;
  final double size;
  final double step; // 다음 스티커까지 거리 (크기 대비)
  const StickerPile(this.st, {super.key, this.menu = '', this.size = 66, this.step = 0.74});
  static const _tilt = [-0.07, 0.05, -0.03, 0.06, -0.05];
  @override
  Widget build(BuildContext context) {
    if (st.isEmpty) return const SizedBox();
    final w = size + (st.length - 1) * size * step;
    return SizedBox(
      width: w,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        for (var i = st.length - 1; i >= 0; i--)
          Positioned(
            left: i * size * step,
            top: 0,
            child: Transform.rotate(angle: _tilt[i % _tilt.length], child: StickerImg(st[i], size: size, menu: menu)),
          ),
      ]),
    );
  }
}

// ---- 후기 자료 ----
class Review {
  final String id;
  final Map<String, dynamic> raw;
  Review(this.id, this.raw);
  String _s(String k) => '${raw[k] ?? ''}';
  List<String> _l(String k) => raw[k] is List ? [for (final x in raw[k] as List) '$x'] : const <String>[];
  int _i(String k) => raw[k] is num ? (raw[k] as num).toInt() : 0;
  String get uid => _s('uid');
  String get nick => _s('nick').isEmpty ? '콕플러' : _s('nick');
  String get pid => _s('pid');
  String get pname => _s('pname');
  String get menu => _s('menu');
  String get text => _s('text');
  Map<String, dynamic> get rec => raw['rec'] is Map ? Map<String, dynamic>.from(raw['rec'] as Map) : {'id': pid, 'n': pname};
  List<String> get st => _l('st').where(kStickers.containsKey).toList();
  List<String> get th => _l('th');
  List<String> get likes => _l('likes');
  int get star => _i('star').clamp(0, 5);
  int get ph => _i('ph');
  int get lc => math.max(_i('lc'), 0);
  int get day => _i('day');
  bool get hidden => raw['hidden'] == true;
  bool get edited => raw['ed'] != null;
  DateTime get at {
    final a = raw['at'];
    if (a is fs.Timestamp) return a.toDate();
    if (a is DateTime) return a;
    return DateTime.now();
  }

  bool get mine => (reviews.demo && uid == 'demo') || (fbOn && fbUser != null && fbUser!.uid == uid);
  bool get liked => fbOn && fbUser != null && likes.contains(fbUser!.uid);
  String get stickerText => [for (final k in st) stickerName(k, menu)].join(' · ');
  Review copy(Map<String, dynamic> m) => Review(id, {...raw, ...m});
}

// 고른 사진: 새로 고른 것(원본·작은 사진) 또는 이미 올린 것(자리 번호·작은 사진)
class ReviewPhoto {
  final Uint8List? full, thumb;
  final int keep;
  final String keepThumb;
  const ReviewPhoto.fresh(Uint8List this.full, Uint8List this.thumb)
      : keep = -1,
        keepThumb = '';
  const ReviewPhoto.kept(this.keep, this.keepThumb)
      : full = null,
        thumb = null;
}

// 스티커 순위 (메뉴 스티커는 메뉴 이름별로)
List<(String, String, int)> stickerRank(Iterable<Review> l) {
  final m = <String, int>{}, menus = <String, int>{};
  for (final r in l.where((r) => !r.hidden)) {
    for (final k in r.st) {
      if (k == 'menu') {
        final n = r.menu.trim();
        if (n.isNotEmpty) menus[n] = (menus[n] ?? 0) + 1;
      } else {
        m[k] = (m[k] ?? 0) + 1;
      }
    }
  }
  final out = [for (final e in m.entries) (e.key, '', e.value), for (final e in menus.entries) ('menu', e.key, e.value)];
  out.sort((a, b) => b.$3.compareTo(a.$3));
  return out;
}

class ReviewStore {
  final ValueNotifier<int> tick = ValueNotifier(0);
  List<Review> latest = const [], popular = const [];
  bool homeLoaded = false, homeFailed = false, _homeLoading = false;
  String justPosted = ''; // 방금 내가 올린 후기 (메인 맨 앞)
  final Map<String, List<Review>> place = {};
  final Map<String, Future<List<Review>>> _pf = {};
  List<Review>? mine;
  String _mineUid = '';
  final Map<String, Uint8List> _thumbs = {}, _full = {};
  String? _nick;
  String _nickUid = '';
  bool demo = false; // 화면 점검용 (웹 주소에 ?demo=1)

  void bump() => tick.value++;

  void onAuth() {
    mine = null;
    _mineUid = '';
    _nick = null;
    bump();
  }

  List<Review> visible(String pid) => (place[pid] ?? const <Review>[]).where((r) => !r.hidden || r.mine || isAdmin).toList();
  Review? todayMine(String pid) => (place[pid] ?? const <Review>[]).where((r) => r.mine && r.day == kDayNum()).firstOrNull;

  void _put(Review r) {
    List<Review> rep(List<Review> l) => [for (final x in l) x.id == r.id ? r : x];
    latest = rep(latest);
    popular = rep(popular);
    for (final k in place.keys.toList()) {
      place[k] = rep(place[k]!);
    }
    if (mine != null) mine = rep(mine!);
    bump();
  }

  void _add(Review r) {
    latest = [r, ...latest.where((x) => x.id != r.id)];
    place[r.pid] = [r, ...(place[r.pid] ?? const <Review>[]).where((x) => x.id != r.id)];
    if (mine != null) mine = [r, ...mine!.where((x) => x.id != r.id)];
    bump();
  }

  void _drop(String id) {
    latest = latest.where((x) => x.id != id).toList();
    popular = popular.where((x) => x.id != id).toList();
    for (final k in place.keys.toList()) {
      place[k] = place[k]!.where((x) => x.id != id).toList();
    }
    if (mine != null) mine = mine!.where((x) => x.id != id).toList();
    if (justPosted == id) justPosted = '';
    bump();
  }

  // 메인 카드 순서: 방금 내가 쓴 후기 → 인기 후기(공감 많은 순) → 최근 후기
  List<(Review, bool)> homeCards() {
    final out = <(Review, bool)>[];
    final seen = <String>{};
    final jp = justPosted.isEmpty ? null : [...latest, ...?mine].where((r) => r.id == justPosted).firstOrNull;
    if (jp != null && !jp.hidden) {
      out.add((jp, false));
      seen.add(jp.id);
    }
    for (final r in popular.take(3)) {
      if (seen.add(r.id)) out.add((r, true));
    }
    for (final r in latest) {
      if (seen.add(r.id)) out.add((r, false));
    }
    return out.take(20).toList();
  }

  Future<void> loadHome({bool force = false}) async {
    if ((homeLoaded && !force) || _homeLoading || demo) return;
    _homeLoading = true;
    try {
      if (!await fbReady()) return;
      final col = fsdb.collection('reviews');
      final res = await Future.wait([
        col.orderBy('at', descending: true).limit(24).get(),
        col.orderBy('lc', descending: true).limit(12).get(),
      ]);
      latest = [for (final d in res[0].docs) Review(d.id, d.data())].where((r) => !r.hidden).toList();
      popular = [for (final d in res[1].docs) Review(d.id, d.data())].where((r) => !r.hidden && r.lc >= 2).toList();
      homeLoaded = true;
      homeFailed = false;
    } catch (_) {
      homeFailed = !homeLoaded; // 못 받으면(인터넷·권한) 메인 후기 칸을 잠깐 숨김
    } finally {
      _homeLoading = false;
      bump();
    }
  }

  Future<List<Review>> loadPlace(String pid, {bool force = false}) {
    if (demo) return Future.value(place[pid] ??= _demoFor(pid));
    if (!force && place.containsKey(pid)) return Future.value(place[pid]!);
    return _pf[pid] ??= () async {
      try {
        if (!await fbReady()) return const <Review>[];
        final q = await fsdb.collection('reviews').where('pid', isEqualTo: pid).limit(100).get();
        final l = [for (final d in q.docs) Review(d.id, d.data())]..sort((a, b) => b.at.compareTo(a.at));
        place[pid] = l;
        bump();
        return l;
      } catch (_) {
        return const <Review>[];
      } finally {
        _pf.remove(pid);
      }
    }();
  }

  Future<List<Review>> loadMine({bool force = false}) async {
    if (demo) return mine ??= latest.take(3).toList();
    final u = fbOn ? fbUser : null;
    if (u == null) return const [];
    if (!force && mine != null && _mineUid == u.uid) return mine!;
    try {
      final q = await fsdb.collection('reviews').where('uid', isEqualTo: u.uid).get();
      mine = [for (final d in q.docs) Review(d.id, d.data())]..sort((a, b) => b.at.compareTo(a.at));
      _mineUid = u.uid;
      bump();
      return mine!;
    } catch (_) {
      return mine ?? const [];
    }
  }

  // 작은 사진 (글자 → 그림, 한 번 풀면 기억)
  Uint8List? thumb(Review r, int i) {
    final th = r.th;
    if (i >= th.length || th[i].isEmpty) return null;
    final key = '${r.id}#$i#${th[i].length}';
    final hit = _thumbs[key];
    if (hit != null) return hit;
    try {
      if (_thumbs.length > 300) _thumbs.clear();
      return _thumbs[key] = base64Decode(th[i]);
    } catch (_) {
      return null;
    }
  }

  // 원본 사진 (누르면 그때 받음)
  Future<Uint8List?> full(Review r, int i) async {
    final key = '${r.id}_$i#${i < r.th.length ? r.th[i].length : 0}';
    final hit = _full[key];
    if (hit != null) return hit;
    if (demo) return thumb(r, i);
    try {
      final d = await fsdb.doc('reviewImg/${r.id}_$i').get();
      final s = '${d.data()?['d'] ?? ''}';
      if (s.isEmpty) return null;
      if (_full.length > 24) _full.clear();
      return _full[key] = base64Decode(s);
    } catch (_) {
      return null;
    }
  }

  // 닉네임: 처음엔 「바삭한 콕플러」처럼 정해 주고, 바꾸면 계정에 저장
  static String defaultNick(String uid) {
    const a = ['바삭한', '든든한', '새콤한', '달콤한', '매콤한', '고소한', '따끈한', '쫄깃한', '아삭한', '촉촉한'];
    var h = 0;
    for (final c in uid.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return '${a[h % a.length]} 콕플러';
  }

  Future<String> nick() async {
    final u = fbOn ? fbUser : null;
    if (u == null) return '콕플러';
    if (_nick != null && _nickUid == u.uid) return _nick!;
    try {
      final d = await fsdb.doc('users/${u.uid}').get();
      final n = '${d.data()?['nick'] ?? ''}'.trim();
      _nick = n.isNotEmpty ? n : defaultNick(u.uid);
    } catch (_) {
      _nick = defaultNick(u.uid);
    }
    _nickUid = u.uid;
    return _nick!;
  }

  void _saveNick(String n) {
    final u = fbOn ? fbUser : null;
    if (u == null || n == _nick) return;
    _nick = n;
    _nickUid = u.uid;
    fsdb.doc('users/${u.uid}').set({'nick': n}, fs.SetOptions(merge: true)).catchError((_) {});
  }

  // 쓰기·고치기 (잘못되면 알림 글, 되면 null)
  Future<String?> save({
    required String pid,
    required String pname,
    required Map<String, dynamic> rec,
    Review? old,
    required List<String> st,
    required String menu,
    required int star,
    required String text,
    required String nick,
    required List<ReviewPhoto> photos,
  }) async {
    if (demo) {
      // 화면 점검용: 저장하지 않고 화면에만 넣는다
      final body = <String, dynamic>{'nick': nick, 'st': st, 'menu': st.contains('menu') ? menu.trim() : '', 'star': star, 'text': text.trim(), 'ph': photos.length, 'th': [for (final p in photos) p.thumb != null ? base64Encode(p.thumb!) : p.keepThumb]};
      if (old == null) {
        final rid = 'demo_new_${DateTime.now().millisecondsSinceEpoch}';
        justPosted = rid;
        _add(Review(rid, {...body, 'uid': 'demo', 'pid': pid, 'pname': pname, 'rec': rec, 'likes': <String>[], 'lc': 0, 'hidden': false, 'at': DateTime.now(), 'day': kDayNum()}));
      } else {
        _put(old.copy({...body, 'ed': DateTime.now()}));
      }
      return null;
    }
    final u = fbOn ? fbUser : null;
    if (u == null) return '로그인해 주세요';
    final day = old?.day ?? kDayNum();
    final rid = old?.id ?? '${pid}_${u.uid}_$day';
    try {
      if (old == null) {
        final ex = await fsdb.doc('reviews/$rid').get();
        if (ex.exists) return '오늘은 이 집 후기를 이미 남겼어요. 내 콕 → 내가 쓴 후기에서 고칠 수 있어요';
      }
      // 자리가 바뀌는 사진은 원본을 먼저 읽어 둔다
      final moved = <int, String>{};
      for (var j = 0; j < photos.length; j++) {
        final k = photos[j].keep;
        if (k >= 0 && k != j) {
          final d = await fsdb.doc('reviewImg/${rid}_$k').get();
          moved[k] = '${d.data()?['d'] ?? ''}';
        }
      }
      for (var j = 0; j < photos.length; j++) {
        final p = photos[j];
        if (p.keep == j) continue;
        final d = p.full != null ? base64Encode(p.full!) : (moved[p.keep] ?? '');
        if (d.isEmpty) continue;
        await fsdb.doc('reviewImg/${rid}_$j').set({'uid': u.uid, 'rid': rid, 'd': d});
      }
      for (var j = photos.length; j < (old?.ph ?? 0); j++) {
        await fsdb.doc('reviewImg/${rid}_$j').delete().catchError((_) {});
      }
      final body = <String, dynamic>{
        'nick': nick,
        'st': st,
        'menu': st.contains('menu') ? menu.trim() : '',
        'star': star,
        'text': text.trim(),
        'ph': photos.length,
        'th': [for (final p in photos) p.thumb != null ? base64Encode(p.thumb!) : p.keepThumb],
      };
      if (old == null) {
        final head = <String, dynamic>{'uid': u.uid, 'pid': pid, 'pname': pname, 'rec': rec, 'likes': <String>[], 'lc': 0, 'hidden': false, 'day': day};
        await fsdb.doc('reviews/$rid').set({...body, ...head, 'at': fs.FieldValue.serverTimestamp()});
        justPosted = rid;
        _add(Review(rid, {...body, ...head, 'at': DateTime.now()}));
      } else {
        await fsdb.doc('reviews/$rid').update({...body, 'ed': fs.FieldValue.serverTimestamp()});
        _thumbs.removeWhere((k, _) => k.startsWith('$rid#'));
        _full.removeWhere((k, _) => k.startsWith('${rid}_'));
        _put(old.copy({...body, 'ed': DateTime.now()}));
      }
      _saveNick(nick);
      return null;
    } on fs.FirebaseException catch (e) {
      return e.code == 'permission-denied' ? '올리지 못했어요. 잠시 뒤 다시 해 주세요' : '올리지 못했어요 (${e.code})';
    } catch (_) {
      return '올리지 못했어요. 인터넷 연결을 확인해 주세요';
    }
  }

  Future<String?> remove(Review r) async {
    if (demo) {
      _drop(r.id);
      return null;
    }
    try {
      for (var i = 0; i < r.ph; i++) {
        await fsdb.doc('reviewImg/${r.id}_$i').delete().catchError((_) {});
      }
      await fsdb.doc('reviews/${r.id}').delete();
      if (isAdmin) await _dropReports(r.id);
      _drop(r.id);
      return null;
    } catch (_) {
      return '지우지 못했어요. 잠시 뒤 다시 해 주세요';
    }
  }

  // 공감 (내 표시만 넣고 빼기 — 먼저 화면에 반영하고 안 되면 되돌림)
  Future<void> like(Review r) async {
    final u = fbOn ? fbUser : null;
    if (u == null && !demo) return;
    final me = u?.uid ?? 'demo';
    final on = !r.likes.contains(me);
    final nr = r.copy({'likes': on ? [...r.likes, me] : r.likes.where((x) => x != me).toList(), 'lc': math.max(0, r.lc + (on ? 1 : -1))});
    _put(nr);
    if (demo) return;
    try {
      await fsdb.doc('reviews/${r.id}').update({
        'likes': on ? fs.FieldValue.arrayUnion([me]) : fs.FieldValue.arrayRemove([me]),
        'lc': fs.FieldValue.increment(on ? 1 : -1),
      });
    } catch (_) {
      _put(r);
    }
  }

  Future<String> report(Review r, String why) async {
    final u = fbOn ? fbUser : null;
    if (u == null) return '로그인해 주세요';
    try {
      await fsdb.doc('reports/${r.id}_${u.uid}').set({
        'uid': u.uid,
        'rid': r.id,
        'why': why,
        'pname': r.pname,
        'text': r.text.length > 80 ? r.text.substring(0, 80) : r.text,
        'at': fs.FieldValue.serverTimestamp(),
      });
      return '신고했어요. 확인한 뒤 처리할게요';
    } on fs.FirebaseException catch (e) {
      return e.code == 'permission-denied' ? '이미 신고한 후기예요' : '신고하지 못했어요 (${e.code})';
    } catch (_) {
      return '신고하지 못했어요. 인터넷 연결을 확인해 주세요';
    }
  }

  // 관리자: 숨기기 · 다시 보이기 (숨기면 그 후기 신고는 정리)
  Future<String?> setHidden(Review r, bool v) async {
    try {
      await fsdb.doc('reviews/${r.id}').update({'hidden': v});
      if (v) await _dropReports(r.id);
      _put(r.copy({'hidden': v}));
      if (v) {
        latest = latest.where((x) => x.id != r.id).toList();
        popular = popular.where((x) => x.id != r.id).toList();
        bump();
      }
      return null;
    } catch (_) {
      return '바꾸지 못했어요';
    }
  }

  Future<void> _dropReports(String rid) async {
    try {
      final q = await fsdb.collection('reports').where('rid', isEqualTo: rid).get();
      for (final d in q.docs) {
        await d.reference.delete();
      }
    } catch (_) {}
  }

  // 탈퇴: 내가 쓴 후기·사진, 내 공감 표시, 내 신고를 모두 지운다
  Future<void> wipeMine() async {
    final u = fbOn ? fbUser : null;
    if (u == null) return;
    try {
      final q = await fsdb.collection('reviews').where('uid', isEqualTo: u.uid).get();
      for (final d in q.docs) {
        final ph = (d.data()['ph'] is num) ? (d.data()['ph'] as num).toInt() : 0;
        for (var i = 0; i < ph; i++) {
          await fsdb.doc('reviewImg/${d.id}_$i').delete().catchError((_) {});
        }
        await d.reference.delete();
      }
    } catch (_) {}
    try {
      final q = await fsdb.collection('reviews').where('likes', arrayContains: u.uid).get();
      for (final d in q.docs) {
        await d.reference.update({'likes': fs.FieldValue.arrayRemove([u.uid]), 'lc': fs.FieldValue.increment(-1)});
      }
    } catch (_) {}
    try {
      final q = await fsdb.collection('reports').where('uid', isEqualTo: u.uid).get();
      for (final d in q.docs) {
        await d.reference.delete();
      }
    } catch (_) {}
    try {
      await fsdb.doc('users/${u.uid}').delete();
    } catch (_) {}
    latest = latest.where((r) => r.uid != u.uid).toList();
    popular = popular.where((r) => r.uid != u.uid).toList();
    place.clear();
    onAuth();
  }

  // ---- 화면 점검용 예시 (웹 ?demo=1 에서만, 저장하지 않음) ----
  static const _demoTexts = [
    '국물이 진하고 김치가 정말 맛있어요. 웨이팅 20분이었는데 그럴 만해요',
    '양이 엄청 많아서 둘이 하나 시켜도 될 정도',
    '혼자 가도 편한 자리. 사장님이 반찬 더 챙겨 주셨어요',
    '',
    '기대가 컸는지 조금 아쉬웠어요. 그래도 고기는 좋았어요',
    '분위기 좋아서 데이트로 딱이에요',
  ];
  static const _demoSt = [
    ['again', 'wait_ok', 'menu'],
    ['big', 'value'],
    ['solo', 'kind', 'again'],
    ['life', 'yt_ok', 'menu', 'value', 'again'],
    ['meh', 'wait_no'],
    ['date', 'again'],
  ];
  static const _demoNick = ['바삭한 콕플러', '송도먹보', '든든한 콕플러', '점심은국밥', '맛집탐정', '새콤한 콕플러'];
  static const _demoMenu = ['묵은지 김치찜', '', '', '차돌짬뽕', '', ''];
  String _demoPhoto = '';

  List<Review> _demoFor(String pid, [String pname = '']) => [
        for (var i = 0; i < _demoTexts.length; i++)
          Review('demo_${pid}_$i', {
            'uid': i == 1 ? 'demo' : 'u$i',
            'nick': _demoNick[i],
            'pid': pid,
            'pname': pname.isEmpty ? '군봉묵은지김치찜' : pname,
            'rec': {'id': pid, 'n': pname.isEmpty ? '군봉묵은지김치찜' : pname},
            'st': _demoSt[i],
            'menu': _demoMenu[i],
            'star': i == 4 ? 3 : (i.isEven ? 5 : 4),
            'text': _demoTexts[i],
            'ph': (i == 0 || i == 3) && _demoPhoto.isNotEmpty ? 1 : 0,
            'th': (i == 0 || i == 3) && _demoPhoto.isNotEmpty ? [_demoPhoto] : <String>[],
            'likes': [for (var k = 0; k < (i == 3 ? 7 : i); k++) 'x$k'],
            'lc': i == 3 ? 7 : i,
            'hidden': false,
            'at': DateTime.now().subtract(Duration(minutes: 3 + i * 47)),
            'day': i == 1 ? kDayNum() - 1 : kDayNum(),
          }),
      ];

  Future<void> startDemo(List<Place> places) async {
    demo = true;
    try {
      final b = await rootBundle.load('assets/brand/intro.jpg');
      _demoPhoto = base64Encode(b.buffer.asUint8List());
    } catch (_) {}
    final ps = places.take(6).toList();
    latest = [
      for (var i = 0; i < 6; i++) _demoFor(ps.isEmpty ? 'p$i' : ps[i % ps.length].id, ps.isEmpty ? '' : ps[i % ps.length].name)[i],
    ];
    popular = latest.where((r) => r.lc >= 2).toList()..sort((a, b) => b.lc.compareTo(a.lc));
    homeLoaded = true;
    bump();
  }
}

final reviews = ReviewStore();

// ---- 사진 고르기 (안드로이드: 방향 바로잡기 · 줄이기 · 얼굴 크게 나온 사진 막기) ----
const _photoCh = MethodChannel('kokple/photo');

class PreppedPhoto {
  final Uint8List full, thumb;
  final bool face;
  PreppedPhoto(this.full, this.thumb, this.face);
}

Future<PreppedPhoto?> prepPhoto(String path) async {
  try {
    final m = await _photoCh.invokeMapMethod<String, dynamic>('prep', {'path': path, 'full': 1080, 'thumb': 320});
    if (m == null || m['full'] is! Uint8List || m['thumb'] is! Uint8List) return null;
    return PreppedPhoto(m['full'] as Uint8List, m['thumb'] as Uint8List, m['faceBig'] == true);
  } catch (_) {
    return null;
  }
}

// ---- 후기 쓰기 열기: 로그인 → (오늘 쓴 후기가 있으면 고치기) → 쓰기 창 → 축하 ----
Future<void> openReviewSheet(BuildContext context, {required String pid, required String pname, required Map<String, dynamic> rec, String sub = '', Review? old}) async {
  void toast(String t) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 2)));
  if (!reviews.demo) {
    if (!await fbReady()) {
      toast('후기는 준비 중이에요');
      return;
    }
    if (!context.mounted) return;
    if (fbUser == null) {
      await openLogin(context);
      if (fbUser == null || !context.mounted) return;
    }
  }
  var o = old;
  if (o == null && !reviews.demo) {
    await reviews.loadPlace(pid);
    o = reviews.todayMine(pid);
  }
  final nick = reviews.demo ? '바삭한 콕플러' : await reviews.nick();
  if (!context.mounted) return;
  final saved = await showModalBottomSheet<Review>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.08),
    builder: (_) => ReviewSheet(pid: pid, pname: pname, rec: rec, sub: sub, old: o, nick: nick),
  );
  if (saved == null || !context.mounted) return;
  if (o == null) {
    celebrateReview(context, saved.st, saved.menu);
  } else {
    toast('후기를 고쳤어요');
  }
}

// 가게 → 후기에 남길 가게 정보 (메인 카드에서 그 집을 다시 열 때 씀)
Map<String, dynamic> reviewRec(Place p) => {
      'id': p.id,
      'n': p.name,
      'k': p.kind,
      'c': p.cat,
      'la': p.lat,
      'ln': p.lng,
      'a': p.areaId,
      'an': p.areaId == 'follow' ? [sidoShort(p.sido), p.gu].where((x) => x.isNotEmpty).join(' ') : dongOf(p),
    };

// ---- 후기 쓰기 창 (아래에서 올라와 한 화면에서 끝) ----
class ReviewSheet extends StatefulWidget {
  final String pid, pname, sub, nick;
  final Map<String, dynamic> rec;
  final Review? old;
  const ReviewSheet({super.key, required this.pid, required this.pname, required this.rec, this.sub = '', this.old, required this.nick});
  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  final sel = <String>[];
  final menuC = TextEditingController(), textC = TextEditingController();
  final menuF = FocusNode();
  int star = 0;
  final photos = <ReviewPhoto>[];
  late String nick = widget.nick;
  bool busy = false, picking = false;
  String bounce = '';
  int bounceN = 0;
  String msg = '';
  Timer? _msgT;

  @override
  void initState() {
    super.initState();
    final o = widget.old;
    if (o != null) {
      sel.addAll(o.st);
      menuC.text = o.menu;
      textC.text = o.text;
      star = o.star;
      for (var i = 0; i < o.th.length; i++) {
        photos.add(ReviewPhoto.kept(i, o.th[i]));
      }
    }
  }

  @override
  void dispose() {
    menuC.dispose();
    textC.dispose();
    menuF.dispose();
    _msgT?.cancel();
    super.dispose();
  }

  void say(String t) {
    _msgT?.cancel();
    setState(() => msg = t);
    _msgT = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => msg = '');
    });
  }

  void tap(String k) {
    if (sel.contains(k)) {
      setState(() {
        sel.remove(k);
        bounce = k;
        bounceN++;
      });
      return;
    }
    final c = kStickerClash[k];
    if (sel.length >= kStickerMax && !(c != null && sel.contains(c))) {
      say('스티커는 $kStickerMax개까지 붙일 수 있어요');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      if (c != null) sel.remove(c);
      sel.add(k);
      bounce = k;
      bounceN++;
    });
    if (k == 'menu' && menuC.text.trim().isEmpty) menuF.requestFocus();
  }

  Future<void> pick() async {
    final left = 3 - photos.length;
    if (left <= 0 || picking) return;
    setState(() => picking = true);
    var face = 0, fail = 0;
    try {
      final picker = ImagePicker();
      final xs = left >= 2 ? await picker.pickMultiImage(limit: left) : [if (await picker.pickImage(source: ImageSource.gallery) case final x?) x];
      for (final x in xs.take(left)) {
        final p = await prepPhoto(x.path);
        if (p == null) {
          fail++;
          continue;
        }
        if (p.face) {
          face++;
          continue;
        }
        photos.add(ReviewPhoto.fresh(p.full, p.thumb));
      }
    } catch (_) {
      fail++;
    }
    if (!mounted) return;
    setState(() => picking = false);
    if (face > 0) {
      say('사람 얼굴이 크게 나온 사진${face > 1 ? ' $face장' : ''}은 올릴 수 없어요');
    } else if (fail > 0) {
      say('사진을 불러오지 못했어요');
    }
  }

  Future<void> changeNick() async {
    final c = TextEditingController(text: nick);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('후기에 보일 이름', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '예: 송도먹보'),
          onSubmitted: (s) => Navigator.pop(ctx, s),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('바꾸기', style: TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
    final n = (v ?? '').trim();
    if (n.isNotEmpty && mounted) setState(() => nick = n.length > 12 ? n.substring(0, 12) : n);
  }

  Future<void> submit() async {
    if (sel.isEmpty || busy) return;
    if (sel.contains('menu') && menuC.text.trim().isEmpty) {
      say('「꼭 시키세요」에 넣을 메뉴 이름을 적어 주세요');
      menuF.requestFocus();
      return;
    }
    setState(() => busy = true);
    final st = List<String>.from(sel); // 고른 순서대로 (처음 고른 스티커가 대표)
    final err = await reviews.save(
      pid: widget.pid,
      pname: widget.pname,
      rec: widget.rec,
      old: widget.old,
      st: st,
      menu: menuC.text,
      star: star,
      text: textC.text,
      nick: nick,
      photos: photos,
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (err != null) {
      say(err);
      return;
    }
    final saved = (reviews.place[widget.pid] ?? const <Review>[]).where((r) => r.mine && r.day == (widget.old?.day ?? kDayNum())).firstOrNull ??
        Review(widget.old?.id ?? '', {'st': st, 'menu': menuC.text.trim()});
    Navigator.pop(context, saved);
  }

  Widget cell(String k, double size) {
    final on = sel.contains(k);
    final dim = !on && sel.length >= kStickerMax;
    final n = sel.indexOf(k) + 1;
    return Semantics(
      button: true,
      selected: on,
      label: stickerName(k, k == 'menu' ? menuC.text : ''),
      onTap: () => tap(k),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => tap(k),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(clipBehavior: Clip.none, children: [
            // 고른 스티커: 뒤에 옅은 동그라미가 퍼지며 깔림
            Positioned.fill(
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutBack,
                  width: on ? size * 0.9 : size * 0.4,
                  height: on ? size * 0.9 : size * 0.4,
                  decoration: BoxDecoration(color: on ? kAccentTint : const Color(0x00FFF1EE), shape: BoxShape.circle),
                ),
              ),
            ),
            TweenAnimationBuilder<double>(
              key: ValueKey('$k-${bounce == k ? bounceN : 0}'),
              tween: Tween(begin: bounce == k ? 0.78 : 1.0, end: 1.0),
              duration: const Duration(milliseconds: 520),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v * (on ? 1.06 : 0.96), child: child),
              child: AnimatedOpacity(
                opacity: dim ? 0.35 : 1,
                duration: const Duration(milliseconds: 200),
                child: StickerImg(k, size: size, menu: k == 'menu' ? menuC.text : ''),
              ),
            ),
            if (on)
              Positioned(
                right: -2,
                top: -2,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.4, end: 1),
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.elasticOut,
                  builder: (_, v, child) => Transform.scale(scale: v, child: child),
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: kAccent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1)),
                    child: Text('$n', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget label(String t, {String? sub}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
          if (sub != null) TextSpan(text: '  $sub', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w400, color: kSub)),
        ])),
      );

  InputDecoration deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFFA5A9B2)),
        isDense: true,
        counterText: '',
        filled: true,
        fillColor: const Color(0xFFF5F5F7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kAccent.withValues(alpha: 0.5), width: 1)),
      );

  Widget photoTile(int i) {
    final p = photos[i];
    final bytes = p.thumb ?? (p.keepThumb.isNotEmpty ? base64Decode(p.keepThumb) : null);
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(clipBehavior: Clip.none, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: bytes == null ? Container(color: kLine) : Image.memory(bytes, width: 72, height: 72, fit: BoxFit.cover, gaplessPlayback: true),
        ),
        Positioned(
          right: -6,
          top: -6,
          child: Semantics(
            button: true,
            label: '사진 빼기',
            child: GestureDetector(
              onTap: () => setState(() => photos.removeAt(i)),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: kInk, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1)),
                child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final inset = mq.viewInsets.bottom;
    final h = math.min(mq.size.height * 0.92, mq.size.height - inset - mq.padding.top - 8);
    final ready = sel.isNotEmpty && !busy;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kHomeMax),
          child: Container(
            height: h,
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
            child: Column(children: [
              Container(margin: const EdgeInsets.only(top: 8), width: 36, height: 4, decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      mixTitle(widget.old == null ? '후기 ' : '후기 ', widget.old == null ? '남기기' : '고치기', size: 20),
                      const SizedBox(height: 3),
                      Text([widget.pname, if (widget.sub.isNotEmpty) widget.sub].join(' · '),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: kSub)),
                    ]),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), tooltip: '닫기', icon: const Icon(Icons.close_rounded, size: 24, color: kInk)),
                ]),
              ),
              Expanded(
                child: LayoutBuilder(builder: (_, c) {
                  final cs = ((c.maxWidth - 40) / 4).clamp(60.0, 104.0); // 그림 둘레가 비어 있어 칸 사이를 붙여도 넉넉
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                    children: [
                      Row(children: [
                        const Text('스티커를 골라 붙여 주세요', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.3)),
                        const Spacer(),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                          decoration: BoxDecoration(color: sel.isEmpty ? const Color(0xFFF3F3F5) : kAccentTint, borderRadius: BorderRadius.circular(12)),
                          child: Text('${sel.length} / $kStickerMax',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel.isEmpty ? kSub : kPointText)),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      for (final (t, ks) in kStickerGroups) ...[
                        label(t),
                        Wrap(spacing: 0, runSpacing: 6, children: [for (final k in ks) cell(k, cs)]),
                        const SizedBox(height: 18),
                      ],
                      label('이 메뉴는 꼭', sub: '메뉴 이름을 적으면 스티커에 들어가요'),
                      Row(children: [
                        cell('menu', cs),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: menuC,
                            focusNode: menuF,
                            maxLength: 20,
                            textInputAction: TextInputAction.done,
                            style: const TextStyle(fontSize: 14.5, color: kInk),
                            decoration: deco('메뉴 이름 (예: 김치찜)'),
                            onChanged: (s) => setState(() {
                              if (s.trim().isNotEmpty && !sel.contains('menu') && sel.length < kStickerMax) {
                                sel.add('menu');
                                bounce = 'menu';
                                bounceN++;
                              }
                            }),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 22),
                      const Divider(height: 1, thickness: 1, color: kHair),
                      const SizedBox(height: 18),
                      Row(children: [
                        const Text('별점', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
                        const SizedBox(width: 4),
                        const Text('(선택)', style: TextStyle(fontSize: 11.5, color: kSub)),
                        const SizedBox(width: 10),
                        for (var i = 1; i <= 5; i++)
                          Semantics(
                            button: true,
                            label: '별 $i개',
                            child: GestureDetector(
                              onTap: () => setState(() => star = star == i ? 0 : i),
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                                child: Icon(Icons.star_rounded, size: 24, color: i <= star ? const Color(0xFFFFB321) : const Color(0xFFE2E3E8)),
                              ),
                            ),
                          ),
                      ]),
                      const SizedBox(height: 14),
                      TextField(
                        controller: textC,
                        maxLength: 80,
                        minLines: 1,
                        maxLines: 2,
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(fontSize: 14.5, color: kInk, height: 1.4),
                        decoration: deco('한 줄 평 (선택) · 예: 국물이 진하고 김치가 맛있어요'),
                      ),
                      const SizedBox(height: 16),
                      label('사진', sub: '선택 · 3장까지'),
                      if (kIsWeb && photos.isEmpty)
                        const Text('사진은 콕플 앱에서 올릴 수 있어요', style: TextStyle(fontSize: 12.5, color: kSub))
                      else
                        Wrap(spacing: 10, runSpacing: 10, children: [
                          for (var i = 0; i < photos.length; i++) photoTile(i),
                          if (photos.length < 3 && !kIsWeb)
                            Semantics(
                              button: true,
                              label: '사진 넣기',
                              child: GestureDetector(
                                onTap: pick,
                                child: Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(color: const Color(0xFFF5F5F7), borderRadius: BorderRadius.circular(12)),
                                  child: picking
                                      ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)))
                                      : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                          const Icon(Icons.add_a_photo_outlined, size: 22, color: kSub),
                                          const SizedBox(height: 3),
                                          Text('${photos.length}/3', style: const TextStyle(fontSize: 11, color: kSub)),
                                        ]),
                                ),
                              ),
                            ),
                        ]),
                      const SizedBox(height: 8),
                      const Text('사람 얼굴이 크게 나온 사진은 올라가지 않아요.\n음식·가게 사진을 올려 주세요.', style: TextStyle(fontSize: 11.5, color: kSub, height: 1.4)),
                    ],
                  );
                }),
              ),
              // 아래 고정: 이름 + 올리기 단추
              Container(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 12 + (inset > 0 ? 0 : mq.padding.bottom)),
                decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kHair))),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    child: msg.isEmpty
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kPointText)),
                          ),
                  ),
                  Row(children: [
                    Flexible(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: nick, style: const TextStyle(fontWeight: FontWeight.w700, color: kInk)),
                          const TextSpan(text: ' 이름으로 올려요'),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: kSub),
                      ),
                    ),
                    TextButton(
                      onPressed: changeNick,
                      style: TextButton.styleFrom(foregroundColor: kInk, padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
                      child: const Text('이름 바꾸기', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: kSub)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Semantics(
                    button: true,
                    enabled: ready,
                    label: widget.old == null ? '후기 올리기' : '고친 후기 올리기',
                    onTap: ready ? submit : null,
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: ready ? submit : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 54,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: ready ? kAccent : const Color(0xFFEDEDF0),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: busy
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                            : Text(
                                sel.isEmpty ? '스티커를 하나 이상 골라 주세요' : (widget.old == null ? '후기 올리기' : '고친 후기 올리기'),
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ready ? Colors.white : const Color(0xFF9EA2AB)),
                              ),
                      ),
                    ),
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

// ---- 올리고 나면: 고른 스티커가 톡톡 튀어나오며 「후기가 등록됐어요!」 ----
void celebrateReview(BuildContext context, List<String> st, String menu) {
  final ov = Overlay.maybeOf(context, rootOverlay: true);
  if (ov == null) return;
  late OverlayEntry e;
  e = OverlayEntry(builder: (_) => _Celebrate(st: st, menu: menu, onDone: () => e.remove()));
  ov.insert(e);
  HapticFeedback.mediumImpact();
}

class _Celebrate extends StatefulWidget {
  final List<String> st;
  final String menu;
  final VoidCallback onDone;
  const _Celebrate({required this.st, required this.menu, required this.onDone});
  @override
  State<_Celebrate> createState() => _CelebrateState();
}

class _CelebrateState extends State<_Celebrate> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: Duration(milliseconds: reviews.demo ? 7000 : 2300))
    ..forward().whenComplete(() => widget.onDone());

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.st.take(3).toList();
    const size = 118.0;
    final xs = st.length == 1 ? [0.0] : (st.length == 2 ? [-56.0, 56.0] : [-92.0, 0.0, 92.0]);
    const tilts = [-0.14, 0.04, 0.16];
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
        animation: c,
        builder: (_, __) {
          final t = c.value;
          final fade = t < 0.84 ? 1.0 : (1 - (t - 0.84) / 0.16).clamp(0.0, 1.0);
          return Opacity(
            opacity: fade,
            child: Center(
              child: SizedBox(
                width: 320,
                height: 260,
                child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                  Transform.scale(
                    scale: 0.6 + 0.4 * Curves.easeOut.transform((t / 0.2).clamp(0.0, 1.0)),
                    child: Container(
                      width: 380,
                      height: 340,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [Color(0xF2FFFFFF), Color(0xCCFFFFFF), Color(0x00FFFFFF)], stops: [0.0, 0.55, 1.0]),
                      ),
                    ),
                  ),
                  // 반짝이 (밖으로 퍼짐)
                  for (var i = 0; i < 10; i++)
                    Builder(builder: (_) {
                      final a = i / 10 * math.pi * 2 + 0.3;
                      final p = Curves.easeOutCubic.transform(((t - 0.12) / 0.6).clamp(0.0, 1.0));
                      final r = 40 + p * 120;
                      return Transform.translate(
                        offset: Offset(math.cos(a) * r, math.sin(a) * r * 0.8 - 30),
                        child: Opacity(
                          opacity: (1 - p).clamp(0.0, 1.0),
                          child: Icon(i.isEven ? Icons.auto_awesome : Icons.circle, size: i.isEven ? 18 : 7, color: i % 3 == 0 ? const Color(0xFFFFC531) : kAccent),
                        ),
                      );
                    }),
                  for (var i = 0; i < st.length; i++)
                    Builder(builder: (_) {
                      final start = 0.04 + i * 0.09;
                      final p = ((t - start) / 0.42).clamp(0.0, 1.0);
                      final s = Curves.elasticOut.transform(p);
                      return Transform.translate(
                        offset: Offset(xs[i], -34 + (1 - p) * 30),
                        child: Transform.rotate(angle: tilts[i] * s, child: Transform.scale(scale: s, child: StickerImg(st[i], size: size, menu: widget.menu))),
                      );
                    }),
                  Positioned(
                    bottom: 0,
                    child: Opacity(
                      opacity: ((t - 0.25) / 0.15).clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, 10 * (1 - ((t - 0.25) / 0.2).clamp(0.0, 1.0))),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24)],
                          ),
                          child: const Text('후기가 등록됐어요!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kInk, letterSpacing: -0.3, decoration: TextDecoration.none)),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
      ),
    );
  }
}

// ---- 가게 화면: 이름 아래 스티커 순위 ----
class ReviewRankLine extends StatefulWidget {
  final String pid;
  const ReviewRankLine({super.key, required this.pid});
  @override
  State<ReviewRankLine> createState() => _ReviewRankLineState();
}

class _ReviewRankLineState extends State<ReviewRankLine> {
  @override
  void initState() {
    super.initState();
    reviews.loadPlace(widget.pid); // 아래 후기 칸이 아직 안 그려졌어도 순위는 바로
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: reviews.tick,
        builder: (_, __, ___) {
          final rank = stickerRank(reviews.visible(widget.pid)).take(3).toList();
          if (rank.isEmpty) return const SizedBox();
          return Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (var i = 0; i < rank.length; i++) ...[
                Row(mainAxisSize: MainAxisSize.min, children: [
                  StickerFace(rank[i].$1, size: 26),
                  const SizedBox(width: 2),
                  Text(rank[i].$1 == 'menu' ? '${rank[i].$2} 꼭' : kStickers[rank[i].$1]!, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kInk)),
                  const SizedBox(width: 3),
                  Text('${rank[i].$3}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: kPointText)),
                ]),
              ],
            ]),
          );
        },
      );
}

// ---- 가게 화면: 후기 남기기(크게) + 후기 목록 ----
class PlaceReviews extends StatefulWidget {
  final Place place;
  const PlaceReviews({super.key, required this.place});
  @override
  State<PlaceReviews> createState() => _PlaceReviewsState();
}

class _PlaceReviewsState extends State<PlaceReviews> {
  bool all = false;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    reviews.loadPlace(widget.place.id).whenComplete(() {
      if (mounted) setState(() => loaded = true);
    });
  }

  void write(Review? old) {
    final p = widget.place;
    openReviewSheet(context, pid: p.id, pname: p.name, rec: reviewRec(p), sub: dongOf(p), old: old);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: reviews.tick,
        builder: (context, __, ___) {
          final l = reviews.visible(widget.place.id);
          final today = reviews.todayMine(widget.place.id);
          final show = all ? l : l.take(4).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ReviewWriteButton(edit: today != null, onTap: () => write(today)),
            const SizedBox(height: 22),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _Title(text: l.isEmpty ? '후기' : '후기 ${l.length}'),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 1),
                child: Text('콕플 회원이 스티커로 남긴 후기', style: TextStyle(fontSize: 11.5, color: kGray)),
              ),
            ]),
            const SizedBox(height: 4),
            if (l.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(loaded ? '아직 후기가 없어요. 첫 스티커를 붙여 주세요!' : '후기를 불러오는 중…', style: const TextStyle(fontSize: 13, color: kGray)),
              ),
            for (final r in show) ReviewTile(r: r, onEdit: () => write(r)),
            if (!all && l.length > show.length)
              TextButton(
                onPressed: () => setState(() => all = true),
                style: TextButton.styleFrom(foregroundColor: kInk, minimumSize: const Size(0, 44)),
                child: Text('후기 ${l.length - show.length}개 더 보기', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
          ]);
        },
      );
}

// 후기 남기기 단추: 큼직하게, 캐릭터 스티커가 단추 위로 살짝 걸침
class ReviewWriteButton extends StatelessWidget {
  final bool edit;
  final VoidCallback onTap;
  const ReviewWriteButton({super.key, this.edit = false, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: edit ? '오늘 쓴 후기 고치기' : '후기 남기기',
        onTap: onTap,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            height: 76,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 60,
                child: Container(
                  decoration: BoxDecoration(
                    color: kAccent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: kAccent.withValues(alpha: 0.22), blurRadius: 16)],
                  ),
                  padding: const EdgeInsets.only(left: 96, right: 16),
                  alignment: Alignment.centerLeft,
                  child: Row(children: [
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(edit ? '오늘 쓴 후기 고치기' : '후기 남기기',
                            maxLines: 1, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3, height: 1.2)),
                        const SizedBox(height: 2),
                        Text(edit ? '스티커·한 줄 평을 바꿀 수 있어요' : '스티커 한 장이면 끝',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.86), height: 1.2)),
                      ]),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 26, color: Colors.white),
                  ]),
                ),
              ),
              Positioned(left: 6, top: -6, child: Transform.rotate(angle: -0.1, child: const StickerFace('yt_ok', size: 92))),
            ]),
          ),
        ),
      );
}

// 후기 한 개 (스티커 크게, 글은 작게)
class ReviewTile extends StatelessWidget {
  final Review r;
  final VoidCallback? onEdit;
  final bool showPlace;
  final VoidCallback? onPlace;
  const ReviewTile({super.key, required this.r, this.onEdit, this.showPlace = false, this.onPlace});

  @override
  Widget build(BuildContext context) {
    void toast(String t) => ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 2)));
    final meta = [r.nick, agoTime(r.at), if (r.edited) '고침'].join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kHair))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showPlace)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: onPlace,
              child: Row(children: [
                const Icon(Icons.place_rounded, size: 15, color: kAccent),
                const SizedBox(width: 3),
                Flexible(child: Text(r.pname, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk))),
                const Icon(Icons.chevron_right_rounded, size: 18, color: kSub),
              ]),
            ),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Align(alignment: Alignment.centerLeft, child: FittedBox(fit: BoxFit.scaleDown, child: StickerPile(r.st, menu: r.menu, size: 86, step: 0.72)))),
          if (r.star > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.star_rounded, size: 15, color: Color(0xFFFFB321)),
                Text('${r.star}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
              ]),
            ),
        ]),
        if (r.hidden)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFF3F3F5), borderRadius: BorderRadius.circular(10)),
            child: const Text('신고가 들어와 숨긴 후기예요 (나와 관리자만 보여요)', style: TextStyle(fontSize: 11.5, color: kSub)),
          ),
        if (r.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(r.text, style: const TextStyle(fontSize: 13.5, color: kInk, height: 1.4)),
        ],
        const SizedBox(height: 5),
        Text(meta, style: const TextStyle(fontSize: 11.5, color: kSub)),
        if (r.ph > 0) ...[
          const SizedBox(height: 10),
          Row(children: [
            for (var i = 0; i < math.min(r.ph, r.th.length); i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => showReviewPhoto(context, r, i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: reviews.thumb(r, i) == null
                        ? Container(width: 76, height: 76, color: kLine)
                        : Image.memory(reviews.thumb(r, i)!, width: 76, height: 76, fit: BoxFit.cover, gaplessPlayback: true),
                  ),
                ),
              ),
          ]),
        ],
        const SizedBox(height: 6),
        Row(children: [
          LikeButton(r: r),
          const Spacer(),
          if (r.mine) ...[
            _tileBtn('고치기', onEdit),
            _tileBtn('지우기', () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  content: const Text('이 후기를 지울까요? 사진도 함께 지워져요.', style: TextStyle(fontSize: 14.5, height: 1.45)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('지우기', style: TextStyle(color: kInk, fontWeight: FontWeight.w700))),
                  ],
                ),
              );
              if (ok == true) {
                final e = await reviews.remove(r);
                toast(e ?? '후기를 지웠어요');
              }
            }),
          ] else
            _tileBtn('신고', () => reportReview(context, r)),
          if (isAdmin && !r.mine)
            _tileBtn(r.hidden ? '다시 보이기' : '숨기기', () async {
              final e = await reviews.setHidden(r, !r.hidden);
              toast(e ?? (r.hidden ? '다시 보이게 했어요' : '숨겼어요'));
            }),
        ]),
      ]),
    );
  }

  static Widget _tileBtn(String t, VoidCallback? onTap) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(foregroundColor: kSub, padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 34)),
        child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: kSub)),
      );
}

// 공감 단추: 하트 스티커가 톡 튀며 수가 올라감
class LikeButton extends StatefulWidget {
  final Review r;
  final bool small;
  const LikeButton({super.key, required this.r, this.small = false});
  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> with SingleTickerProviderStateMixin {
  late final AnimationController pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void dispose() {
    pop.dispose();
    super.dispose();
  }

  Future<void> tap() async {
    if (!reviews.demo && (!fbOn || fbUser == null)) {
      await openLogin(context);
      if (!fbOn || fbUser == null) return;
    }
    if (!widget.r.liked) {
      pop.forward(from: 0);
      HapticFeedback.lightImpact();
    }
    reviews.like(widget.r);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final on = r.liked || (reviews.demo && r.likes.contains('demo'));
    final s = widget.small;
    return Semantics(
      button: true,
      selected: on,
      label: '공감 ${r.lc}',
      onTap: tap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: tap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: s ? 28 : 32,
          padding: EdgeInsets.only(left: s ? 6 : 8, right: s ? 9 : 12),
          decoration: BoxDecoration(
            color: on ? kAccentTint : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? kAccent.withValues(alpha: 0.35) : kPillLine, width: 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedBuilder(
              animation: pop,
              builder: (_, child) {
                final t = pop.value;
                final sc = t == 0 ? 1.0 : 1 + 0.5 * math.sin(t * math.pi) * (1 - t * 0.4);
                return Transform.scale(scale: sc, child: child);
              },
              child: Opacity(opacity: on ? 1 : 0.55, child: Image.asset('assets/stickers/like.png', width: s ? 18 : 21, height: s ? 18 : 21)),
            ),
            const SizedBox(width: 4),
            Text(r.lc > 0 ? '공감 ${r.lc}' : '공감',
                style: TextStyle(fontSize: s ? 11.5 : 12.5, fontWeight: FontWeight.w700, color: on ? kPointText : kInk, height: 1.1)),
          ]),
        ),
      ),
    );
  }
}

// 신고: 까닭 하나 고르기
Future<void> reportReview(BuildContext context, Review r) async {
  if (!fbOn || fbUser == null) {
    await openLogin(context);
    if (!fbOn || fbUser == null || !context.mounted) return;
  }
  if (!context.mounted) return;
  final why = await showModalBottomSheet<String>(
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
          padding: EdgeInsets.fromLTRB(22, 20, 22, 10 + MediaQuery.of(ctx).padding.bottom),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('후기 신고', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kInk)),
            const SizedBox(height: 4),
            const Text('관리자가 확인한 뒤 숨겨요. 신고한 사람은 밝히지 않아요.', style: TextStyle(fontSize: 12.5, color: kSub)),
            const SizedBox(height: 10),
            for (final w in kReportWhy)
              InkWell(
                onTap: () => Navigator.pop(ctx, w),
                child: Container(
                  height: 48,
                  alignment: Alignment.centerLeft,
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: kHair))),
                  child: Text(w, style: const TextStyle(fontSize: 15, color: kInk)),
                ),
              ),
          ]),
        ),
      ),
    ),
  );
  if (why == null || !context.mounted) return;
  final m = await reviews.report(r, why);
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
  }
}

// 사진 크게 보기 (작은 사진을 먼저 보여 주고 원본을 받아 바꿈)
void showReviewPhoto(BuildContext context, Review r, int i) {
  showDialog(
    context: context,
    barrierColor: Colors.black,
    builder: (ctx) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(children: [
        PageView(
          controller: PageController(initialPage: i),
          children: [
            for (var k = 0; k < math.min(r.ph, r.th.length); k++)
              FutureBuilder<Uint8List?>(
                future: reviews.full(r, k),
                builder: (_, s) {
                  final b = s.data ?? reviews.thumb(r, k);
                  return InteractiveViewer(child: Center(child: b == null ? const SizedBox() : Image.memory(b, fit: BoxFit.contain, gaplessPlayback: true)));
                },
              ),
          ],
        ),
        Positioned(
          top: MediaQuery.of(ctx).padding.top + 6,
          right: 6,
          child: IconButton(onPressed: () => Navigator.pop(ctx), tooltip: '닫기', icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28)),
        ),
      ]),
    ),
  );
}

// ---- 메인: 방금 올라온 후기 (스티커가 카드 밖으로 걸친 가로 카드) ----
class ReviewStrip extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>> onOpen;
  const ReviewStrip({super.key, required this.onOpen});
  @override
  State<ReviewStrip> createState() => _ReviewStripState();
}

class _ReviewStripState extends State<ReviewStrip> {
  bool fb = true;

  @override
  void initState() {
    super.initState();
    if (reviews.demo) {
      if (!reviews.homeLoaded) reviews.startDemo(allPlaces().where((p) => p.top && p.vids.isNotEmpty).toList());
      return;
    }
    fbReady().then((ok) {
      if (!mounted) return;
      if (!ok) setState(() => fb = false);
      reviews.loadHome();
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: reviews.tick,
        builder: (context, __, ___) {
          if (!fb || (reviews.homeFailed && !reviews.demo)) return const SizedBox();
          final cards = reviews.homeCards();
          return Padding(
            padding: const EdgeInsets.only(top: 34),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  mixTitle('방금 ', '올라온 후기', size: 18),
                  const SizedBox(width: 4),
                  Transform.translate(offset: const Offset(0, 4), child: Transform.rotate(angle: 0.12, child: const StickerFace('again', size: 34))),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 3, 20, 0),
                child: Text('콕플 회원이 스티커로 남긴 진짜 한 줄', style: TextStyle(fontSize: 13, color: kSub)),
              ),
              const SizedBox(height: 8),
              if (cards.isEmpty)
                reviews.homeLoaded ? const _ReviewEmpty() : const SizedBox(height: 60)
              else
                SizedBox(
                  height: 262,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                    itemCount: cards.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) {
                      final (r, hot) = cards[i];
                      return ReviewCard(r: r, hot: hot, fresh: r.id == reviews.justPosted, tilt: i.isEven ? -0.018 : 0.016, onTap: () => widget.onOpen(r.rec));
                    },
                  ),
                ),
            ]),
          );
        },
      );
}

class _ReviewEmpty extends StatelessWidget {
  const _ReviewEmpty();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
        child: Container(
          height: 132,
          decoration: kokCard().copyWith(borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.fromLTRB(18, 0, 10, 0),
          child: Row(children: [
            const Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('첫 후기를 기다려요', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kInk, letterSpacing: -0.3)),
                SizedBox(height: 4),
                Text('가게 화면에서 스티커 한 장이면\n후기가 끝나요', style: TextStyle(fontSize: 12.5, color: kSub, height: 1.4)),
              ]),
            ),
            SizedBox(
              width: 150,
              height: 132,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned(left: 0, top: 26, child: Transform.rotate(angle: -0.16, child: const StickerImg('again', size: 84))),
                Positioned(left: 62, top: 6, child: Transform.rotate(angle: 0.12, child: const StickerImg('value', size: 84))),
              ]),
            ),
          ]),
        ),
      );
}

class ReviewCard extends StatelessWidget {
  final Review r;
  final bool hot, fresh;
  final double tilt;
  final VoidCallback onTap;
  const ReviewCard({super.key, required this.r, this.hot = false, this.fresh = false, this.tilt = 0, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const w = 168.0, top = 20.0, stage = 112.0;
    final th = reviews.thumb(r, 0);
    final st = r.st;
    final first = st.isEmpty ? 'again' : st.first;
    final second = st.length > 1 ? st[1] : null;
    final more = st.length - 2;
    final line = r.text.isNotEmpty
        ? r.text
        : [for (final k in st.take(2)) stickerName(k, r.menu)].join(' · ') + (st.length > 2 ? ' 외 ${st.length - 2}' : '');
    return Semantics(
      button: true,
      label: '${r.pname} 후기: ${r.stickerText}${r.text.isEmpty ? '' : ', ${r.text}'} · ${r.nick}',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Transform.rotate(
          angle: tilt,
          child: SizedBox(
            width: w,
            height: 246,
            child: Stack(clipBehavior: Clip.none, children: [
              // 카드 몸통
              Positioned(
                left: 0,
                right: 0,
                top: top,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kCardLine, width: 1),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 14)],
                  ),
                ),
              ),
              // 사진(있으면) 또는 스티커 무대
              Positioned(
                left: 8,
                right: 8,
                top: top + 8,
                height: stage,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: th != null
                      ? Image.memory(th, fit: BoxFit.cover, gaplessPlayback: true)
                      : CustomPaint(painter: _StagePainter(), child: const SizedBox.expand()),
                ),
              ),
              // 스티커: 사진이 있으면 오른쪽 위 모서리에 걸쳐 붙이고, 없으면 무대 가운데 크게
              if (th != null)
                Positioned(right: -10, top: -4, child: Transform.rotate(angle: 0.12, child: StickerImg(first, size: 100, menu: r.menu)))
              else ...[
                Positioned(left: second == null ? 22 : 4, top: 0, child: Transform.rotate(angle: -0.06, child: StickerImg(first, size: 122, menu: r.menu))),
                if (second != null) Positioned(right: -2, top: 70, child: Transform.rotate(angle: 0.16, child: StickerImg(second, size: 64, menu: r.menu))),
                if (more > 0)
                  Positioned(
                    left: 16,
                    top: top + 8 + stage - 26,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9), border: Border.all(color: const Color(0xFFFFD9C7), width: 1)),
                      child: Text('+$more', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kPointText, height: 1.2)),
                    ),
                  ),
              ],
              // 글: 한 줄 평(없으면 스티커 이름) · 닉네임 · 가게
              Positioned(
                left: 13,
                right: 12,
                top: top + 8 + stage + 10,
                bottom: 10,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (fresh || hot)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(fresh ? '내 후기 · 방금' : '인기 후기', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kPointText, height: 1.2)),
                    ),
                  Text(line,
                      maxLines: fresh || hot ? 1 : 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kInk, height: 1.35)),
                  const Spacer(),
                  Row(children: [
                    Expanded(
                      child: Text('${r.nick} · ${agoTime(r.at)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kSub)),
                    ),
                    if (r.lc > 0) ...[
                      Image.asset('assets/stickers/like.png', width: 14, height: 14),
                      const SizedBox(width: 2),
                      Text('${r.lc}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kPointText)),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Row(children: [
                    const Icon(Icons.place_rounded, size: 13, color: kAccent),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(r.pname, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// 사진 없는 카드의 무대: 옅은 크림색 + 작은 점 (스티커 붙인 노트 느낌)
class _StagePainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFFFF6EE));
    final dot = Paint()..color = const Color(0xFFFFE2CF);
    for (var y = 9.0; y < s.height; y += 16) {
      for (var x = ((y ~/ 16).isEven ? 9.0 : 17.0); x < s.width; x += 16) {
        c.drawCircle(Offset(x, y), 1.6, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ---- 내 콕: 내가 쓴 후기 ----
class MyReviews extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>> onOpen;
  const MyReviews({super.key, required this.onOpen});
  @override
  State<MyReviews> createState() => _MyReviewsState();
}

class _MyReviewsState extends State<MyReviews> {
  String? _uid = '-';
  bool _loading = false;

  void _load({bool force = true}) {
    _loading = true;
    reviews.loadMine(force: force).whenComplete(() {
      _loading = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: authTick,
        builder: (context, __, ___) => ValueListenableBuilder<int>(
          valueListenable: reviews.tick,
          builder: (context, __, ___) {
            final uid = reviews.demo ? 'demo' : (fbOn ? fbUser?.uid : null);
            if (uid == null) {
              return const Center(
                child: Text('로그인하면 내가 쓴 후기를\n여기에 모아 볼 수 있어요.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kSub, height: 1.5)),
              );
            }
            if (uid != _uid && !_loading) {
              _uid = uid;
              WidgetsBinding.instance.addPostFrameCallback((_) => _load());
            }
            final l = reviews.mine;
            if (l == null) {
              return Center(
                child: _loading || uid != _uid
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent))
                    : TextButton(onPressed: _load, child: const Text('후기를 받지 못했어요 · 다시 불러오기', style: TextStyle(fontSize: 13, color: kInk))),
              );
            }
            if (l.isEmpty) {
              return const Center(
                child: Text('아직 쓴 후기가 없어요.\n가게 화면의 「후기 남기기」로 스티커를 붙여 보세요.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kSub, height: 1.5)),
              );
            }
            // 기록: 후기 수 · 받은 공감 · 많이 쓴 스티커
            final likes = l.fold<int>(0, (a, r) => a + r.lc);
            final top = stickerRank(l).firstOrNull;
            Widget stat(String n, String t) => Expanded(
                  child: Column(children: [
                    Text(n, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kInk, letterSpacing: -0.4, height: 1.1)),
                    const SizedBox(height: 3),
                    Text(t, style: const TextStyle(fontSize: 11.5, color: kSub)),
                  ]),
                );
            return RefreshIndicator(
              color: kAccent,
              onRefresh: () => reviews.loadMine(force: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
                    decoration: kokCard().copyWith(borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      stat('${l.length}', '쓴 후기'),
                      Container(width: 1, height: 34, color: kHair),
                      stat(commas(likes), '받은 공감'),
                      Container(width: 1, height: 34, color: kHair),
                      Expanded(
                        child: Column(children: [
                          if (top != null) StickerFace(top.$1, size: 34) else const SizedBox(height: 26),
                          const SizedBox(height: 2),
                          Text(top == null ? '많이 쓴 스티커' : (top.$1 == 'menu' ? '${top.$2} 꼭' : kStickers[top.$1]!),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: kInk)),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  for (final r in l)
                    ReviewTile(
                      r: r,
                      showPlace: true,
                      onPlace: () => widget.onOpen(r.rec),
                      onEdit: () => openReviewSheet(context, pid: r.pid, pname: r.pname, rec: r.rec, sub: '${r.rec['an'] ?? ''}', old: r),
                    ),
                ],
              ),
            );
          },
        ),
      );
}

// ---- 관리자: 신고 들어온 후기 · 숨긴 후기 (촘촘한 표처럼 한 줄씩) ----
class ReviewAdminTab extends StatefulWidget {
  const ReviewAdminTab({super.key});
  @override
  State<ReviewAdminTab> createState() => _ReviewAdminTabState();
}

class _ReviewAdminTabState extends State<ReviewAdminTab> {
  int seg = 0;
  bool loading = true;
  String err = '';
  List<(String, Review?, List<Map<String, dynamic>>)> reported = [];
  List<Review> hidden = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      err = '';
    });
    try {
      final q = await fsdb.collection('reports').orderBy('at', descending: true).limit(300).get();
      final by = <String, List<Map<String, dynamic>>>{};
      for (final d in q.docs) {
        final j = d.data();
        by.putIfAbsent('${j['rid'] ?? ''}', () => []).add(j);
      }
      final out = <(String, Review?, List<Map<String, dynamic>>)>[];
      for (final e in by.entries) {
        final d = await fsdb.doc('reviews/${e.key}').get();
        out.add((e.key, d.exists ? Review(d.id, d.data()!) : null, e.value));
      }
      final h = await fsdb.collection('reviews').where('hidden', isEqualTo: true).limit(100).get();
      reported = out;
      hidden = [for (final d in h.docs) Review(d.id, d.data())]..sort((a, b) => b.at.compareTo(a.at));
    } catch (e) {
      err = '불러오지 못했어요 ($e)';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> act(Future<String?> Function() f, String done) async {
    final e = await f();
    if (!mounted) return;
    admToast(context, e ?? done);
    load();
  }

  Widget row(Review? r, String rid, {List<Map<String, dynamic>> reps = const [], required List<Widget> btns}) {
    final why = <String, int>{};
    for (final x in reps) {
      final w = '${x['why'] ?? ''}';
      why[w] = (why[w] ?? 0) + 1;
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kHair))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 86,
          child: r == null ? const Text('(지워진 후기)', style: TextStyle(fontSize: 12, color: kSub)) : FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: StickerPile(r.st, menu: r.menu, size: 40, step: 0.6)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r == null ? rid : '${r.pname} · ${r.nick} · ${agoTime(r.at)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
            if (r != null && (r.text.isNotEmpty || r.ph > 0))
              Text([if (r.text.isNotEmpty) r.text, if (r.ph > 0) '사진 ${r.ph}장'].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: kInk, height: 1.35)),
            if (reps.isNotEmpty)
              Text('신고 ${reps.length} · ${why.entries.map((e) => '${e.key} ${e.value}').join(', ')}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kPointText)),
            if (r != null && r.ph > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  for (var i = 0; i < math.min(r.ph, r.th.length); i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: GestureDetector(
                        onTap: () => showReviewPhoto(context, r, i),
                        child: reviews.thumb(r, i) == null ? const SizedBox() : Image.memory(reviews.thumb(r, i)!, width: 44, height: 44, fit: BoxFit.cover),
                      ),
                    ),
                ]),
              ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: btns),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final segs = ['신고 들어온 후기 ${reported.length}', '숨긴 후기 ${hidden.length}'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          for (var i = 0; i < segs.length; i++)
            GestureDetector(
              onTap: () => setState(() => seg = i),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: seg == i ? kInk : Colors.white,
                  border: Border(
                    top: const BorderSide(color: kPillLine),
                    bottom: const BorderSide(color: kPillLine),
                    left: i == 0 ? const BorderSide(color: kPillLine) : BorderSide.none,
                    right: const BorderSide(color: kPillLine),
                  ),
                ),
                child: Text(segs[i], style: TextStyle(fontSize: 13, fontWeight: seg == i ? FontWeight.w700 : FontWeight.w500, color: seg == i ? Colors.white : kInk)),
              ),
            ),
          const Spacer(),
          admBtn('새로 고침', load),
        ]),
      ),
      if (err.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(err, style: const TextStyle(fontSize: 12.5, color: kPointText))),
      Expanded(
        child: loading
            ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
            : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 30), children: [
                if (seg == 0) ...[
                  if (reported.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('신고 들어온 후기가 없어요.', style: TextStyle(fontSize: 13, color: kSub))),
                  for (final (rid, r, reps) in reported)
                    row(r, rid, reps: reps, btns: [
                      if (r != null && !r.hidden) admBtn('숨기기', () => act(() => reviews.setHidden(r, true), '숨겼어요'), strong: true),
                      admBtn('문제없음', () => act(() async {
                            await reviews._dropReports(rid);
                            return null;
                          }, '신고를 정리했어요')),
                      if (r != null) admBtn('후기 지우기', () => act(() => reviews.remove(r), '후기를 지웠어요'), danger: true),
                    ]),
                ] else ...[
                  if (hidden.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('숨긴 후기가 없어요.', style: TextStyle(fontSize: 13, color: kSub))),
                  for (final r in hidden)
                    row(r, r.id, btns: [
                      admBtn('다시 보이기', () => act(() => reviews.setHidden(r, false), '다시 보이게 했어요')),
                      admBtn('후기 지우기', () => act(() => reviews.remove(r), '후기를 지웠어요'), danger: true),
                    ]),
                ],
              ]),
      ),
    ]);
  }
}
