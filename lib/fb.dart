part of 'main.dart';

// ---------------- 파이어베이스: 관리자·회원·배너·팝업·가게 보호 ----------------
// 콘솔에서 받은 공개 설정 값 (비밀번호가 아니라 앱마다 들어가는 값). 비어 있으면 파이어베이스 기능은 꺼진 채로 돈다.
const kFb = <String, String>{
  'apiKey': 'AIzaSyCtAYeMr_86li7WmmkXUL6Nx0ae8xmG5ME', // 웹용 공개 키
  'androidApiKey': 'AIzaSyB5wrd2GrSG7LqmrZqCvcWBBRWH7glm5Os', // 안드로이드용 공개 키
  'authDomain': 'kokple.firebaseapp.com',
  'projectId': 'kokple',
  'storageBucket': 'kokple.firebasestorage.app',
  'messagingSenderId': '233879188710',
  'webAppId': '1:233879188710:web:543f8fd620c76f0685f727',
  'androidAppId': '1:233879188710:android:35792ff90ca0509d85f727',
};
const kAdminEmails = ['dfmail@naver.com']; // 관리자 화면을 여는 계정 (쓰기 권한은 파이어베이스 규칙이 따로 막는다)

Future<bool>? _fbF;
bool fbOn = false;
Future<bool> fbReady() => _fbF ??= _fbInit();
Future<bool> _fbInit() async {
  if ((kFb['projectId'] ?? '').isEmpty) return false;
  try {
    await fc.Firebase.initializeApp(
      options: fc.FirebaseOptions(
        apiKey: kIsWeb ? kFb['apiKey']! : kFb['androidApiKey']!,
        appId: kIsWeb ? kFb['webAppId']! : kFb['androidAppId']!,
        messagingSenderId: kFb['messagingSenderId']!,
        projectId: kFb['projectId']!,
        authDomain: kFb['authDomain'],
        storageBucket: kFb['storageBucket'],
      ),
    );
    fbOn = true;
  } catch (_) {
    fbOn = false;
  }
  return fbOn;
}

fs.FirebaseFirestore get fsdb => fs.FirebaseFirestore.instance;
fa.FirebaseAuth get fbAuth => fa.FirebaseAuth.instance;
fa.User? get fbUser => fbOn ? fbAuth.currentUser : null;
bool get isAdmin => kAdminEmails.contains(fbUser?.email?.toLowerCase()) && (fbUser?.emailVerified ?? false);
bool get adminUnverified => kAdminEmails.contains(fbUser?.email?.toLowerCase()) && !(fbUser?.emailVerified ?? false);

// 관리자 화면에서 쓰는 앱 쪽 연결 (지도 화면이 채운다)
List<Place> Function() allPlaces = () => const [];
VoidCallback onAdminChanged = () {};

// 로그인 상태가 바뀌면 화면을 다시 그리게
final ValueNotifier<int> authTick = ValueNotifier(0);
void watchAuth() {
  if (!fbOn) return;
  fbAuth.setLanguageCode('ko').catchError((_) {}); // 인증·비밀번호 메일을 한국어로
  fbAuth.authStateChanges().listen((_) => authTick.value++);
}

// 기간 (YYYY-MM-DD 글자, 비면 제한 없음)
bool inPeriod(Map j, DateTime now) {
  DateTime? t(dynamic v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
  final s = t(j['start']), e = t(j['end']);
  if (s != null && now.isBefore(s)) return false;
  if (e != null && now.isAfter(e.add(const Duration(days: 1)))) return false;
  return true;
}

// ---- 메인 설정 (칸 순서 · 배너 · 팝업) ----
const kHomeNames = {
  'hero': '맨 위 큰 비주얼',
  'roulette': '오늘 뭐 먹지 룰렛',
  'follow': '유튜버 따라 먹기',
  'courses': '테마 골라 보기',
  'tops': '유튜버가 많이 찾은 집',
  'fresh': '새로 올라온 영상',
  'creators': '이 동네 다녀간 유튜버',
  'cuisine': '무엇이 당기세요 (음식 분류)',
};

class HomeRemote {
  final List<String> order;
  final List<HomeBanner> banners;
  final Map<String, dynamic>? popup;
  HomeRemote(this.order, this.banners, this.popup);
}

List<String> fixOrder(List<dynamic> raw) {
  final out = [for (final e in raw) '$e'].where(kHomeOrder.contains).toList();
  for (final k in kHomeOrder) {
    if (!out.contains(k)) out.add(k);
  }
  return out;
}

// 배너 그림은 따로 두고 휴대폰에 저장해 둔다 (판이 바뀔 때만 다시 받음 — 무료 한도 아끼기)
Future<String> bannerImg(String id, int ver) async {
  SharedPreferences? sp;
  try {
    sp = await SharedPreferences.getInstance();
    final hit = sp.getString('bimg_${id}_$ver');
    if (hit != null) return hit;
  } catch (_) {}
  try {
    final d = await fsdb.doc('bannerImg/$id').get();
    final s = '${d.data()?['data'] ?? ''}';
    if (s.isNotEmpty) {
      try {
        for (final k in sp?.getKeys().where((k) => k.startsWith('bimg_${id}_')) ?? const <String>{}) {
          await sp?.remove(k);
        }
        await sp?.setString('bimg_${id}_$ver', s);
      } catch (_) {}
    }
    return s;
  } catch (_) {
    return '';
  }
}

Future<HomeRemote?> loadHomeRemote() async {
  if (!await fbReady()) return null;
  try {
    final now = DateTime.now();
    final cfg = (await fsdb.doc('config/home').get()).data() ?? {};
    final bs = await fsdb.collection('banners').get();
    final list = <(int, HomeBanner)>[];
    for (final d in bs.docs) {
      final j = d.data();
      if (j['on'] != true || !inPeriod(j, now)) continue;
      final img = await bannerImg(d.id, ((j['ver'] ?? 0) as num).toInt());
      if (img.isEmpty) continue;
      list.add((((j['order'] ?? 0) as num).toInt(), HomeBanner({...j, 'id': d.id, 'image': img})));
    }
    list.sort((a, b) => a.$1.compareTo(b.$1));
    Map<String, dynamic>? pop;
    if (cfg['popup'] is Map) {
      final p = Map<String, dynamic>.from(cfg['popup'] as Map);
      if (p['on'] == true && inPeriod(p, now)) {
        final img = ((p['ver'] ?? 0) as num).toInt();
        final s = await bannerImg('popup', img);
        pop = {...p, 'image': s};
      }
    }
    return HomeRemote(fixOrder((cfg['order'] ?? []) as List), [for (final b in list) b.$2], pop);
  } catch (_) {
    return null;
  }
}

// ---- 가게 보호 (관리자가 고친 항목 잠금 · 보호 · 숨김) ----
// places/{가게 id}: ov(고친 값), locks(잠근 항목), protect(보호), hidden(숨김)
class PlaceGuard {
  final Map<String, dynamic> ov;
  final List<String> locks;
  final bool protect, hidden;
  PlaceGuard(Map<String, dynamic> j)
      : ov = Map<String, dynamic>.from((j['ov'] ?? {}) as Map),
        locks = [for (final e in (j['locks'] ?? []) as List) '$e'],
        protect = j['protect'] == true,
        hidden = j['hidden'] == true;
}

// 관리자 화면에서 고칠 수 있는 항목 (자료 칸 이름 → 화면 이름)
const kEditable = {
  'name': '가게 이름',
  'cat': '업종',
  'tel': '전화',
  'addr': '주소',
  'week': '영업시간 (한 줄에 하루)',
  'home': '홈페이지·블로그 주소',
  'insta': '인스타그램 주소',
};

Map<String, PlaceGuard> guards = {};
Future<void> loadGuards() async {
  if (!await fbReady()) return;
  try {
    final q = await fsdb.collection('places').get();
    guards = {for (final d in q.docs) d.id: PlaceGuard(d.data())};
  } catch (_) {}
}

// 고친 값을 덮어 가게를 다시 만든다 (원래 자료는 그대로 둔다)
Place guarded(Place p) {
  final g = guards[p.id];
  if (g == null || g.ov.isEmpty) return p;
  return Place({...p.raw, ...g.ov}, p.areaId);
}

Future<void> saveGuard(Place p, {Map<String, dynamic>? ov, List<String>? locks, bool? protect, bool? hidden, String note = ''}) async {
  final ref = fsdb.collection('places').doc(p.id);
  final before = (await ref.get()).data();
  final after = <String, dynamic>{
    'ov': ov ?? (before?['ov'] ?? {}),
    'locks': locks ?? (before?['locks'] ?? []),
    'protect': protect ?? (before?['protect'] ?? false),
    'hidden': hidden ?? (before?['hidden'] ?? false),
    'name': p.name,
    'area': p.areaId,
    'by': fbUser?.email ?? '',
    'at': fs.FieldValue.serverTimestamp(),
  };
  await ref.set(after);
  await ref.collection('history').add({
    'before': before,
    'after': {...after, 'at': null},
    'note': note,
    'by': fbUser?.email ?? '',
    'at': fs.FieldValue.serverTimestamp(),
  });
  guards[p.id] = PlaceGuard(after);
}

// 고친 내역에서 이전 상태로 되돌리기
Future<void> restoreGuard(Place p, Map<String, dynamic>? before) async {
  final ref = fsdb.collection('places').doc(p.id);
  final now = (await ref.get()).data();
  if (before == null) {
    await ref.delete();
    guards.remove(p.id);
  } else {
    final b = {...before, 'by': fbUser?.email ?? '', 'at': fs.FieldValue.serverTimestamp()};
    await ref.set(b);
    guards[p.id] = PlaceGuard(b);
  }
  await ref.collection('history').add({'before': now, 'after': before, 'note': '되돌리기', 'by': fbUser?.email ?? '', 'at': fs.FieldValue.serverTimestamp()});
}

// ---- 회원 ----
Future<String?> signInGoogle() async {
  try {
    final p = fa.GoogleAuthProvider();
    if (kIsWeb) {
      await fbAuth.signInWithPopup(p);
    } else {
      await fbAuth.signInWithProvider(p);
    }
    return null;
  } on fa.FirebaseAuthException catch (e) {
    return authMsg(e.code);
  } catch (_) {
    return '구글 로그인을 마치지 못했습니다';
  }
}

Future<String?> signInEmail(String email, String pass, {bool join = false}) async {
  try {
    if (join) {
      final c = await fbAuth.createUserWithEmailAndPassword(email: email, password: pass);
      await c.user?.sendEmailVerification();
    } else {
      await fbAuth.signInWithEmailAndPassword(email: email, password: pass);
    }
    return null;
  } on fa.FirebaseAuthException catch (e) {
    return authMsg(e.code);
  } catch (_) {
    return '로그인을 마치지 못했습니다';
  }
}

// 관리자 메일 인증 확인: 메일의 링크를 누른 뒤 이걸 누르면 새 표시를 받아 관리자 화면이 열린다
Future<String> checkVerify() async {
  final u = fbAuth.currentUser;
  if (u == null) return '먼저 로그인해 주세요';
  try {
    await u.reload();
    final now = fbAuth.currentUser;
    if (now != null && now.emailVerified) {
      await now.getIdToken(true); // 새 표시가 들어간 출입증으로 바꿔야 쓰기 규칙이 통과한다
      authTick.value++;
      return '인증됐어요. 관리자 화면이 열렸어요';
    }
    await now?.sendEmailVerification();
    return '인증 메일을 다시 보냈어요. 메일의 링크를 누른 뒤 한 번 더 눌러 주세요';
  } on fa.FirebaseAuthException catch (e) {
    return e.code == 'too-many-requests' ? '조금 뒤에 다시 눌러 주세요' : authMsg(e.code);
  } catch (_) {
    return '확인하지 못했어요. 잠시 뒤 다시 눌러 주세요';
  }
}

String authMsg(String code) => switch (code) {
      'invalid-email' => '이메일 모양이 맞지 않아요',
      'user-not-found' || 'wrong-password' || 'invalid-credential' => '이메일이나 비밀번호가 맞지 않아요',
      'email-already-in-use' => '이미 가입한 이메일이에요. 로그인해 주세요',
      'weak-password' => '비밀번호를 6자 넘게 넣어 주세요',
      'too-many-requests' => '잠시 뒤에 다시 해 주세요',
      'popup-closed-by-user' || 'web-context-canceled' || 'canceled' => '로그인 창을 닫았어요',
      'network-request-failed' => '인터넷 연결을 확인해 주세요',
      _ => '로그인을 마치지 못했어요 ($code)',
    };
