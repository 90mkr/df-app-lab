part of 'main.dart';

// ---------------- 로그인 · 회원가입 ----------------
class LoginSheet extends StatefulWidget {
  const LoginSheet({super.key});
  @override
  State<LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<LoginSheet> {
  final email = TextEditingController(), pass = TextEditingController();
  bool join = false, busy = false;
  String msg = '';

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> run(Future<String?> Function() f, {bool joined = false}) async {
    setState(() {
      busy = true;
      msg = '';
    });
    final e = await f();
    if (!mounted) return;
    setState(() {
      busy = false;
      msg = e ?? '';
    });
    if (e == null) Navigator.pop(context, joined ? 'join' : 'ok');
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom;
    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF6F6F8),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        );
    Widget social(String label, Color bg, Color fg, Widget icon, VoidCallback? onTap, {Color? line}) => SizedBox(
          width: double.infinity,
          height: 48,
          child: TextButton(
            onPressed: busy ? null : onTap,
            style: TextButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: fg,
              disabledForegroundColor: fg.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: line == null ? BorderSide.none : BorderSide(color: line)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              icon,
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            ]),
          ),
        );
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(22, 22, 22, 22 + bottom),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            mixTitle(join ? '콕플 ' : '콕플에 ', join ? '회원가입' : '로그인', size: 19),
            const SizedBox(height: 6),
            const Text('콕한 집이 계정에 남아 휴대폰을 바꿔도 그대로예요', style: TextStyle(fontSize: 13, color: kSub)),
            const SizedBox(height: 18),
            social('카카오로 계속하기', const Color(0xFFFEE500), const Color(0xFF191919), const Icon(Icons.chat_bubble_rounded, size: 18), () => run(signInKakao)),
            const SizedBox(height: 8),
            social('구글로 계속하기', Colors.white, kInk, const Text('G', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF4285F4))),
                () => run(signInGoogle),
                line: kPillLine),
            const SizedBox(height: 18),
            const Row(children: [
              Expanded(child: Divider(color: kHair)),
              Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('이메일로', style: TextStyle(fontSize: 12, color: kSub))),
              Expanded(child: Divider(color: kHair)),
            ]),
            const SizedBox(height: 12),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: deco('이메일')),
            const SizedBox(height: 8),
            TextField(controller: pass, obscureText: true, autofillHints: const [AutofillHints.password], decoration: deco(join ? '비밀번호 (6자 넘게)' : '비밀번호')),
            if (msg.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(msg, style: const TextStyle(fontSize: 12.5, color: kAccent)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton(
                onPressed: busy ? null : () => run(() => signInEmail(email.text.trim(), pass.text, join: join), joined: join),
                style: TextButton.styleFrom(backgroundColor: kInk, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(join ? '가입하기' : '로그인', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 4),
            Row(children: [
              TextButton(
                onPressed: () => setState(() {
                  join = !join;
                  msg = '';
                }),
                child: Text(join ? '이미 가입했어요 · 로그인' : '처음이에요 · 회원가입', style: const TextStyle(fontSize: 13, color: kInk)),
              ),
              const Spacer(),
              if (!join)
                TextButton(
                  onPressed: () async {
                    final e = email.text.trim();
                    if (e.isEmpty) {
                      setState(() => msg = '이메일을 먼저 넣어 주세요');
                      return;
                    }
                    try {
                      await fbAuth.sendPasswordResetEmail(email: e);
                      setState(() => msg = '비밀번호를 새로 정하는 메일을 보냈어요');
                    } on fa.FirebaseAuthException catch (x) {
                      setState(() => msg = authMsg(x.code));
                    }
                  },
                  child: const Text('비밀번호 찾기', style: TextStyle(fontSize: 13, color: kSub)),
                ),
            ]),
            const Text('가입하면 서비스 이용약관과 개인정보처리방침에 동의하는 것으로 봅니다.', style: TextStyle(fontSize: 11, color: kSub)),
          ]),
        ),
      ),
    );
  }
}

Future<bool> openLogin(BuildContext context) async {
  if (!await fbReady()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('로그인은 준비 중이에요')));
    }
    return false;
  }
  if (!context.mounted) return false;
  final ok = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.08),
    builder: (_) => const LoginSheet(),
  );
  if (ok == 'join' && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(seconds: 6), content: Text('가입했어요. 메일함에 온 인증 링크를 눌러 주세요')));
  }
  return ok != null;
}

// ---------------- 관리자 화면 ----------------
// 촘촘한 표처럼: 한 줄에 하나, 위에 칸 고르기
class AdminPage extends StatefulWidget {
  final List<Place> places; // 지금 받아 둔 모든 동네 가게 (가게 관리에서 찾기)
  final VoidCallback onChanged; // 저장 뒤 앱 화면을 다시 그리게
  const AdminPage({super.key, required this.places, required this.onChanged});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int tab = 0;
  static const tabs = ['메인 순서', '배너', '팝업', '공지사항', '문의함', '가게 관리', '확인 대기', '후보 확인', '후기 신고', '지역 수집'];

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 16, 6),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), tooltip: '뒤로', icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: kInk)),
                const Text('관리자', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.4)),
                const Spacer(),
                Text(fbUser?.email ?? '', style: const TextStyle(fontSize: 12, color: kSub)),
              ]),
            ),
            // 칸 고르기: 네모 칸을 붙여서 (그누보드식)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                for (var i = 0; i < tabs.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => tab = i),
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tab == i ? kInk : Colors.white,
                        border: Border(
                          top: const BorderSide(color: kPillLine),
                          bottom: const BorderSide(color: kPillLine),
                          left: i == 0 ? const BorderSide(color: kPillLine) : BorderSide.none,
                          right: const BorderSide(color: kPillLine),
                        ),
                      ),
                      child: Text(tabs[i], style: TextStyle(fontSize: 13.5, fontWeight: tab == i ? FontWeight.w700 : FontWeight.w500, color: tab == i ? Colors.white : kInk)),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: kHair),
            Expanded(
              child: switch (tab) {
                0 => _OrderTab(onChanged: widget.onChanged),
                1 => _BannerTab(onChanged: widget.onChanged),
                2 => _PopupTab(onChanged: widget.onChanged),
                3 => const NoticeAdminTab(),
                4 => const AskAdminTab(), // 앱 안으로 들어온 제안·제휴·문의·정보 수정 (메일 대신)
                5 => _PlaceTab(places: widget.places, onChanged: widget.onChanged),
                6 => _PendingTab(places: widget.places, onChanged: widget.onChanged),
                7 => const _PicksTab(),
                8 => const ReviewAdminTab(),
                _ => const RegionProgressTab(),
              },
            ),
          ]),
        ),
      );
}

// 공용: 작은 단추 · 입력칸 · 알림
Widget admBtn(String label, VoidCallback? onTap, {bool strong = false, bool danger = false}) => SizedBox(
      height: 34,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          backgroundColor: strong ? kInk : Colors.white,
          foregroundColor: strong ? Colors.white : (danger ? kAccent : kInk),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: strong ? BorderSide.none : const BorderSide(color: kPillLine)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );

InputDecoration admDeco(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: kPillLine)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: kPillLine)),
    );

void admToast(BuildContext context, String t) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 2)));

// 그림 고르기 → 줄여서 글자(base64)로 (파이어베이스 무료 요금제는 파일 보관함이 없어 문서에 넣는다)
Future<String?> pickImageData() async {
  final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
  if (x == null) return null;
  final b = await x.readAsBytes();
  if (b.length > 700 * 1024) return '';
  return 'data:image/jpeg;base64,${base64Encode(b)}';
}

// ---- 메인 칸 순서 ----
class _OrderTab extends StatefulWidget {
  final VoidCallback onChanged;
  const _OrderTab({required this.onChanged});
  @override
  State<_OrderTab> createState() => _OrderTabState();
}

class _OrderTabState extends State<_OrderTab> {
  List<String>? order;
  @override
  void initState() {
    super.initState();
    fsdb.doc('config/home').get().then((d) {
      if (mounted) setState(() => order = fixOrder((d.data()?['order'] ?? []) as List));
    }).catchError((_) {
      if (mounted) setState(() => order = [...kHomeOrder]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    if (o == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    return Column(children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text('끌어서 순서를 바꾸고 저장하면 앱 홈에 바로 반영돼요', style: TextStyle(fontSize: 12.5, color: kSub)),
      ),
      Expanded(
        child: ReorderableListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          onReorder: (a, b) => setState(() {
            if (b > a) b--;
            o.insert(b, o.removeAt(a));
          }),
          children: [
            for (var i = 0; i < o.length; i++)
              Container(
                key: ValueKey(o[i]),
                height: 48,
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kHair))),
                child: Row(children: [
                  SizedBox(width: 28, child: Text('${i + 1}', style: const TextStyle(fontSize: 13, color: kSub))),
                  Expanded(child: Text(kHomeNames[o[i]] ?? o[i], style: const TextStyle(fontSize: 14, color: kInk))),
                  const Icon(Icons.drag_handle_rounded, color: kSub, size: 20),
                ]),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          admBtn('처음 순서로', () => setState(() => order = [...kHomeOrder])),
          const Spacer(),
          admBtn('저장', () async {
            try {
              await fsdb.doc('config/home').set({'order': o, 'at': fs.FieldValue.serverTimestamp()}, fs.SetOptions(merge: true));
              widget.onChanged();
              if (context.mounted) admToast(context, '순서를 저장했어요');
            } catch (e) {
              if (context.mounted) admToast(context, '저장하지 못했어요: $e');
            }
          }, strong: true),
        ]),
      ),
    ]);
  }
}

// ---- 배너 ----
class _BannerTab extends StatefulWidget {
  final VoidCallback onChanged;
  const _BannerTab({required this.onChanged});
  @override
  State<_BannerTab> createState() => _BannerTabState();
}

class _BannerTabState extends State<_BannerTab> {
  List<fs.QueryDocumentSnapshot<Map<String, dynamic>>>? docs;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final q = await fsdb.collection('banners').get();
      final l = q.docs.toList()..sort((a, b) => ((a.data()['order'] ?? 0) as num).compareTo((b.data()['order'] ?? 0) as num));
      if (mounted) setState(() => docs = l);
    } catch (_) {
      if (mounted) setState(() => docs = []);
    }
  }

  Future<void> edit([fs.QueryDocumentSnapshot<Map<String, dynamic>>? d]) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => _BannerEdit(id: d?.id, data: d?.data(), nextOrder: (docs?.length ?? 0) + 1),
    );
    if (ok == true) {
      await load();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = docs;
    if (l == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          const Expanded(child: Text('맨 위 큰 비주얼에 추천 영상과 섞여 옆으로 넘어가요 (16:9 그림)', style: TextStyle(fontSize: 12.5, color: kSub))),
          admBtn('배너 추가', () => edit(), strong: true),
        ]),
      ),
      const Divider(height: 1, color: kHair),
      Expanded(
        child: l.isEmpty
            ? const Center(child: Text('등록한 배너가 없어요', style: TextStyle(fontSize: 13, color: kSub)))
            : ListView.separated(
                itemCount: l.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: kHair),
                itemBuilder: (_, i) {
                  final j = l[i].data();
                  final on = j['on'] == true;
                  final period = [j['start'] ?? '', j['end'] ?? ''].where((x) => '$x'.isNotEmpty).join(' ~ ');
                  return InkWell(
                    onTap: () => edit(l[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(children: [
                        SizedBox(width: 26, child: Text('${j['order'] ?? i + 1}', style: const TextStyle(fontSize: 13, color: kSub))),
                        Expanded(
                          child: Text('${j['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: kInk)),
                        ),
                        Text(period.isEmpty ? '기간 없음' : period, style: const TextStyle(fontSize: 12, color: kSub)),
                        const SizedBox(width: 10),
                        Text(on ? '켜짐' : '꺼짐', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? kPointText : kSub)),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

class _BannerEdit extends StatefulWidget {
  final String? id;
  final Map<String, dynamic>? data;
  final int nextOrder;
  const _BannerEdit({this.id, this.data, required this.nextOrder});
  @override
  State<_BannerEdit> createState() => _BannerEditState();
}

class _BannerEditState extends State<_BannerEdit> {
  late final title = TextEditingController(text: '${widget.data?['title'] ?? ''}');
  late final sub = TextEditingController(text: '${widget.data?['sub'] ?? ''}');
  late final link = TextEditingController(text: '${widget.data?['link'] ?? ''}');
  late final start = TextEditingController(text: '${widget.data?['start'] ?? ''}');
  late final end = TextEditingController(text: '${widget.data?['end'] ?? ''}');
  late final order = TextEditingController(text: '${widget.data?['order'] ?? widget.nextOrder}');
  late bool on = widget.data?['on'] ?? true;
  String? image; // 새로 고른 그림
  bool busy = false;

  @override
  void dispose() {
    for (final c in [title, sub, link, start, end, order]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (title.text.trim().isEmpty) return admToast(context, '제목을 넣어 주세요');
    if (widget.id == null && image == null) return admToast(context, '그림을 골라 주세요');
    setState(() => busy = true);
    try {
      final ref = widget.id == null ? fsdb.collection('banners').doc() : fsdb.collection('banners').doc(widget.id);
      final ver = ((widget.data?['ver'] ?? 0) as num).toInt() + (image != null ? 1 : 0);
      if (image != null) await fsdb.doc('bannerImg/${ref.id}').set({'data': image});
      await ref.set({
        'title': title.text.trim(),
        'sub': sub.text.trim(),
        'link': link.text.trim(),
        'start': start.text.trim(),
        'end': end.text.trim(),
        'order': int.tryParse(order.text.trim()) ?? widget.nextOrder,
        'on': on,
        'ver': ver,
        'by': fbUser?.email ?? '',
        'at': fs.FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        admToast(context, '저장하지 못했어요: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = image;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.id == null ? '배너 추가' : '배너 고치기', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () async {
              final s = await pickImageData();
              if (s == null) return;
              if (s.isEmpty) {
                if (context.mounted) admToast(context, '그림이 너무 커요 (700KB 아래로)');
                return;
              }
              setState(() => image = s);
            },
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(color: const Color(0xFFF6F6F8), borderRadius: BorderRadius.circular(8), border: Border.all(color: kPillLine)),
                clipBehavior: Clip.antiAlias,
                child: img != null
                    ? bannerImage(HomeBanner({'image': img}))
                    : Center(
                        child: Text(widget.id == null ? '눌러서 그림 고르기 (16:9)' : '눌러서 그림 바꾸기 (안 바꾸면 그대로)', style: const TextStyle(fontSize: 13, color: kSub)),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(controller: title, decoration: admDeco('제목 (그림 아래에 보여요)')),
          const SizedBox(height: 8),
          TextField(controller: sub, decoration: admDeco('작은 설명 (없어도 돼요)')),
          const SizedBox(height: 8),
          TextField(controller: link, decoration: admDeco('누르면 갈 곳: 주소(https://…) 또는 비워 두기')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: start, decoration: admDeco('시작 2026-12-01'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: end, decoration: admDeco('끝 2026-12-31'))),
            const SizedBox(width: 8),
            SizedBox(width: 70, child: TextField(controller: order, keyboardType: TextInputType.number, decoration: admDeco('순서'))),
          ]),
          const SizedBox(height: 4),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: on, onChanged: (v) => setState(() => on = v), title: const Text('앱에 보이기', style: TextStyle(fontSize: 14))),
          Row(children: [
            if (widget.id != null)
              admBtn('지우기', busy
                  ? null
                  : () async {
                      try {
                        await fsdb.doc('bannerImg/${widget.id}').delete();
                        await fsdb.collection('banners').doc(widget.id).delete();
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        if (context.mounted) admToast(context, '지우지 못했어요: $e');
                      }
                    }, danger: true),
            const Spacer(),
            admBtn('닫기', () => Navigator.pop(context)),
            const SizedBox(width: 8),
            admBtn(busy ? '저장 중' : '저장', busy ? null : save, strong: true),
          ]),
        ]),
      ),
    );
  }
}

// ---- 팝업 (앱 켤 때 한 번, 오늘 하루 보지 않기) ----
class _PopupTab extends StatefulWidget {
  final VoidCallback onChanged;
  const _PopupTab({required this.onChanged});
  @override
  State<_PopupTab> createState() => _PopupTabState();
}

class _PopupTabState extends State<_PopupTab> {
  final title = TextEditingController(), body = TextEditingController(), link = TextEditingController();
  final start = TextEditingController(), end = TextEditingController();
  bool on = false, loaded = false, busy = false;
  int ver = 0;
  String? image;

  @override
  void initState() {
    super.initState();
    fsdb.doc('config/home').get().then((d) {
      final p = d.data()?['popup'];
      if (p is Map) {
        title.text = '${p['title'] ?? ''}';
        body.text = '${p['body'] ?? ''}';
        link.text = '${p['link'] ?? ''}';
        start.text = '${p['start'] ?? ''}';
        end.text = '${p['end'] ?? ''}';
        on = p['on'] == true;
        ver = ((p['ver'] ?? 0) as num).toInt();
      }
      if (mounted) setState(() => loaded = true);
    }).catchError((_) {
      if (mounted) setState(() => loaded = true);
    });
  }

  @override
  void dispose() {
    for (final c in [title, body, link, start, end]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('앱을 켤 때 한 번 떠요. 「오늘 하루 보지 않기」를 누른 사람은 그날 다시 안 떠요.', style: TextStyle(fontSize: 12.5, color: kSub)),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: () async {
          final s = await pickImageData();
          if (s == null) return;
          if (s.isEmpty) {
            if (context.mounted) admToast(context, '그림이 너무 커요 (700KB 아래로)');
            return;
          }
          setState(() => image = s);
        },
        child: Container(
          height: 160,
          decoration: BoxDecoration(color: const Color(0xFFF6F6F8), borderRadius: BorderRadius.circular(8), border: Border.all(color: kPillLine)),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: image != null
              ? bannerImage(HomeBanner({'image': image}))
              : const Text('눌러서 그림 고르기 (없으면 글자만)', style: TextStyle(fontSize: 13, color: kSub)),
        ),
      ),
      const SizedBox(height: 10),
      TextField(controller: title, decoration: admDeco('제목')),
      const SizedBox(height: 8),
      TextField(controller: body, maxLines: 4, minLines: 2, decoration: admDeco('내용')),
      const SizedBox(height: 8),
      TextField(controller: link, decoration: admDeco('자세히 보기 주소 (없어도 돼요)')),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(controller: start, decoration: admDeco('시작 2026-12-01'))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: end, decoration: admDeco('끝 2026-12-31'))),
      ]),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: on, onChanged: (v) => setState(() => on = v), title: const Text('팝업 켜기', style: TextStyle(fontSize: 14))),
      Align(
        alignment: Alignment.centerRight,
        child: admBtn(busy ? '저장 중' : '저장', busy
            ? null
            : () async {
                setState(() => busy = true);
                try {
                  final v = ver + (image != null ? 1 : 0);
                  if (image != null) await fsdb.doc('bannerImg/popup').set({'data': image});
                  await fsdb.doc('config/home').set({
                    'popup': {
                      'on': on,
                      'title': title.text.trim(),
                      'body': body.text.trim(),
                      'link': link.text.trim(),
                      'start': start.text.trim(),
                      'end': end.text.trim(),
                      'ver': v,
                    },
                    'at': fs.FieldValue.serverTimestamp(),
                  }, fs.SetOptions(merge: true));
                  ver = v;
                  widget.onChanged();
                  if (context.mounted) admToast(context, '팝업을 저장했어요');
                } catch (e) {
                  if (context.mounted) admToast(context, '저장하지 못했어요: $e');
                }
                if (mounted) setState(() => busy = false);
              }, strong: true),
      ),
    ]);
  }
}

// ---- 가게 관리: 찾기 → 고치기 · 잠금 · 보호 · 숨김 · 고친 내역 ----
class _PlaceTab extends StatefulWidget {
  final List<Place> places;
  final VoidCallback onChanged;
  const _PlaceTab({required this.places, required this.onChanged});
  @override
  State<_PlaceTab> createState() => _PlaceTabState();
}

class _PlaceTabState extends State<_PlaceTab> {
  String q = '';
  bool onlyGuarded = false;

  @override
  Widget build(BuildContext context) {
    final k = q.replaceAll(' ', '').toLowerCase();
    final seen = <String>{};
    final list = [
      for (final p in widget.places)
        if (seen.add(p.id) &&
            (onlyGuarded ? guards.containsKey(p.id) : k.isNotEmpty) &&
            (k.isEmpty || p.name.replaceAll(' ', '').toLowerCase().contains(k) || p.addr.contains(q.trim())))
          p
    ].take(80).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Expanded(child: TextField(onChanged: (v) => setState(() => q = v), decoration: admDeco('가게 이름이나 주소로 찾기'))),
          const SizedBox(width: 8),
          admBtn(onlyGuarded ? '전체' : '고친 가게만', () => setState(() => onlyGuarded = !onlyGuarded)),
        ]),
      ),
      const Divider(height: 1, color: kHair),
      Expanded(
        child: list.isEmpty
            ? Center(child: Text(onlyGuarded ? '고친 가게가 없어요' : '가게 이름을 넣어 찾아 주세요', style: const TextStyle(fontSize: 13, color: kSub)))
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: kHair),
                itemBuilder: (_, i) {
                  final p = list[i];
                  final g = guards[p.id];
                  return InkWell(
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaceEditPage(place: p)));
                      if (mounted) setState(() {});
                      widget.onChanged();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(children: [
                        Expanded(
                          child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: kInk)),
                        ),
                        Text([dongOf(p), p.cat].where((x) => x.isNotEmpty).join(' · '), style: const TextStyle(fontSize: 12, color: kSub)),
                        if (g != null) ...[
                          const SizedBox(width: 8),
                          if (g.protect) const Text('보호', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kPointText)),
                          if (g.hidden) const Text(' 숨김', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kAccent)),
                          if (g.locks.isNotEmpty) Text(' 잠금 ${g.locks.length}', style: const TextStyle(fontSize: 12, color: kInk)),
                        ],
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

class PlaceEditPage extends StatefulWidget {
  final Place place;
  const PlaceEditPage({super.key, required this.place});
  @override
  State<PlaceEditPage> createState() => _PlaceEditPageState();
}

class _PlaceEditPageState extends State<PlaceEditPage> {
  late final Place base = widget.place;
  late final PlaceGuard? g = guards[base.id];
  late final Map<String, TextEditingController> ctl = {
    for (final k in kEditable.keys) k: TextEditingController(text: _value(k)),
  };
  late final Set<String> locks = {...?g?.locks};
  late bool protect = g?.protect ?? false;
  late bool hidden = g?.hidden ?? false;
  final note = TextEditingController();
  bool busy = false;
  List<Map<String, dynamic>>? history;

  // 지금 보이는 값 (고친 값이 있으면 그것)
  String _value(String k) {
    final v = g?.ov[k] ?? base.raw[k];
    if (v is List) return v.join('\n');
    return '${v ?? ''}';
  }

  dynamic _parse(String k, String s) => k == 'week' ? s.split('\n').map((x) => x.trim()).where((x) => x.isNotEmpty).toList() : s.trim();

  @override
  void initState() {
    super.initState();
    fsdb.collection('places').doc(base.id).collection('history').orderBy('at', descending: true).limit(20).get().then((q) {
      if (mounted) setState(() => history = [for (final d in q.docs) d.data()]);
    }).catchError((_) {
      if (mounted) setState(() => history = []);
    });
  }

  @override
  void dispose() {
    for (final c in ctl.values) {
      c.dispose();
    }
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    // 원래 자료와 다르게 고친 항목만 남기고, 고친 항목은 저절로 잠근다
    final ov = <String, dynamic>{};
    for (final k in kEditable.keys) {
      final now = _parse(k, ctl[k]!.text);
      final orig = base.raw[k];
      final same = now is List ? (orig is List && orig.map((e) => '$e').join('\n') == now.join('\n')) : '${orig ?? ''}' == now;
      if (!same) {
        ov[k] = now;
        locks.add(k);
      }
    }
    try {
      await saveGuard(base, ov: ov, locks: locks.toList(), protect: protect, hidden: hidden, note: note.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        admToast(context, '저장하지 못했어요: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 16, 6),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), tooltip: '뒤로', icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: kInk)),
                Expanded(child: Text(base.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                admBtn(busy ? '저장 중' : '저장', busy ? null : save, strong: true),
              ]),
            ),
            const Divider(height: 1, color: kHair),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: protect,
                  onChanged: (v) => setState(() => protect = v),
                  title: const Text('보호', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  subtitle: const Text('자동 수집에서 빠지거나 폐업으로 나와도 앱에서 사라지지 않아요', style: TextStyle(fontSize: 12)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: hidden,
                  onChanged: (v) => setState(() => hidden = v),
                  title: const Text('숨김', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  subtitle: const Text('앱에 보이지 않게 (지우지는 않아요 — 다시 켜면 돌아와요)', style: TextStyle(fontSize: 12)),
                ),
                const Divider(color: kHair),
                const SizedBox(height: 6),
                const Text('고친 항목은 저절로 잠겨서 자동 수집이 덮어쓰지 못해요. 자물쇠를 풀면 다시 자동 값을 써요.', style: TextStyle(fontSize: 12, color: kSub)),
                const SizedBox(height: 10),
                for (final e in kEditable.entries) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: TextField(
                        controller: ctl[e.key],
                        maxLines: e.key == 'week' ? 7 : 1,
                        minLines: 1,
                        decoration: admDeco(e.value),
                      ),
                    ),
                    IconButton(
                      tooltip: locks.contains(e.key) ? '잠금 풀기' : '잠그기',
                      onPressed: () => setState(() => locks.contains(e.key) ? locks.remove(e.key) : locks.add(e.key)),
                      icon: Icon(locks.contains(e.key) ? Icons.lock_rounded : Icons.lock_open_rounded, size: 20, color: locks.contains(e.key) ? kInk : kSub),
                    ),
                  ]),
                  const SizedBox(height: 8),
                ],
                TextField(controller: note, decoration: admDeco('고친 까닭 (내역에 남아요, 없어도 돼요)')),
                const SizedBox(height: 22),
                const Text('고친 내역', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                if (history == null)
                  const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                else if (history!.isEmpty)
                  const Text('아직 고친 적이 없어요', style: TextStyle(fontSize: 12.5, color: kSub))
                else
                  for (final h in history!)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kHair))),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            [
                              h['at'] is fs.Timestamp ? (h['at'] as fs.Timestamp).toDate().toString().substring(0, 16) : '',
                              '${h['by'] ?? ''}',
                              '${h['note'] ?? ''}',
                            ].where((x) => x.isNotEmpty).join(' · '),
                            style: const TextStyle(fontSize: 12.5, color: kInk),
                          ),
                        ),
                        admBtn('이 전으로', () async {
                          try {
                            final b = h['before'];
                            await restoreGuard(base, b is Map ? Map<String, dynamic>.from(b) : null);
                            if (context.mounted) Navigator.pop(context);
                          } catch (e) {
                            if (context.mounted) admToast(context, '되돌리지 못했어요: $e');
                          }
                        }),
                      ]),
                    ),
              ]),
            ),
          ]),
        ),
      );
}

// ---- 확인 대기: 수집에서 빠지거나 폐업으로 나온 가게 (바로 지우지 않고 여기 모음) ----
class _PendingTab extends StatefulWidget {
  final List<Place> places;
  final VoidCallback onChanged;
  const _PendingTab({required this.places, required this.onChanged});
  @override
  State<_PendingTab> createState() => _PendingTabState();
}

class _PendingTabState extends State<_PendingTab> {
  List<Map<String, dynamic>>? items;
  @override
  void initState() {
    super.initState();
    http.get(Uri.parse('${dataUrl('pending.json')}?t=${DateTime.now().millisecondsSinceEpoch}')).then((r) {
      final j = r.statusCode == 200 ? jsonDecode(utf8.decode(r.bodyBytes)) : null;
      final l = j is Map ? (j['items'] ?? []) as List : const [];
      if (mounted) setState(() => items = [for (final e in l) Map<String, dynamic>.from(e as Map)]);
    }).catchError((_) {
      if (mounted) setState(() => items = []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = items;
    if (l == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    final open = [for (final e in l) if (!guards.containsKey('${e['id']}') || (!guards['${e['id']}']!.protect && !guards['${e['id']}']!.hidden)) e];
    if (open.isEmpty) return const Center(child: Text('확인할 가게가 없어요', style: TextStyle(fontSize: 13, color: kSub)));
    return ListView.separated(
      itemCount: open.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: kHair),
      itemBuilder: (_, i) {
        final e = open[i];
        final p = widget.places.where((x) => x.id == '${e['id']}').firstOrNull;
        Future<void> decide({bool? protect, bool? hidden}) async {
          final pl = p ?? Place({'id': e['id'], 'name': e['name'] ?? '', 'lat': e['lat'] ?? 0, 'lng': e['lng'] ?? 0}, '${e['area'] ?? ''}');
          try {
            await saveGuard(pl, protect: protect, hidden: hidden, note: '확인 대기: ${e['why'] ?? ''}');
            if (mounted) setState(() {});
            widget.onChanged();
          } catch (x) {
            if (context.mounted) admToast(context, '저장하지 못했어요: $x');
          }
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${e['name'] ?? ''}', style: const TextStyle(fontSize: 14, color: kInk)),
                Text('${e['why'] ?? ''} · ${e['since'] ?? ''}', style: const TextStyle(fontSize: 12, color: kSub)),
              ]),
            ),
            admBtn('유지(보호)', () => decide(protect: true)),
            const SizedBox(width: 6),
            admBtn('숨김', () => decide(hidden: true), danger: true),
          ]),
        );
      },
    );
  }
}

// ---- 후보 확인 (쯔양 등 주소 안 적는 유튜버): 맞음(공개) · 틀림(다른 가게로) · 제외 · 직접 연결 ----
class _PicksTab extends StatefulWidget {
  const _PicksTab();
  @override
  State<_PicksTab> createState() => _PicksTabState();
}

class _PicksTabState extends State<_PicksTab> {
  List<Map<String, dynamic>>? items;
  List<Map<String, dynamic>> nofind = [];
  Map<String, Map<String, dynamic>> dec = {};
  bool done = false, lost = false; // 정한 것도 보기 · 못 찾은 영상 보기
  String updated = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await http.get(Uri.parse('${dataUrl('picks.json')}?t=${DateTime.now().millisecondsSinceEpoch}'));
      final j = r.statusCode == 200 ? jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic> : <String, dynamic>{};
      final q = await fsdb.collection('picks').get();
      if (!mounted) return;
      setState(() {
        items = [for (final e in (j['items'] ?? []) as List) Map<String, dynamic>.from(e as Map)];
        nofind = [for (final e in (j['nofind'] ?? []) as List) Map<String, dynamic>.from(e as Map)];
        updated = '${j['updated'] ?? ''}';
        dec = {for (final d in q.docs) d.id: d.data()};
        // 김부장이 대표님 자료로 대신 맞음 처리한 것 (관리자 화면에서 정한 것이 먼저)
        for (final it in items!) {
          final a = it['auto'];
          if (a is Map && !dec.containsKey('${it['key']}')) dec['${it['key']}'] = Map<String, dynamic>.from(a);
        }
      });
    } catch (_) {
      if (mounted) setState(() => items = []);
    }
  }

  Future<void> decide(String key, Map<String, dynamic> it, String status, {Map<String, dynamic>? place, String query = ''}) async {
    final d = <String, dynamic>{
      'status': status,
      'vid': it['vid'] ?? '',
      't': it['t'] ?? '',
      'cid': it['cid'] ?? '',
      if (place != null) 'place': place,
      if (query.isNotEmpty) 'query': query,
      'name': it['name'] ?? '',
      'by': fbUser?.email ?? '',
      'at': fs.FieldValue.serverTimestamp(),
    };
    try {
      await fsdb.collection('picks').doc(key).set(d);
      if (mounted) setState(() => dec[key] = d);
    } catch (e) {
      if (mounted) admToast(context, '저장하지 못했어요: $e');
    }
  }

  // 틀림: 다른 후보 고르기 또는 가게 이름을 직접 적기
  Future<void> wrong(String key, Map<String, dynamic> it) async {
    final cands = [for (final c in (it['cands'] ?? []) as List) Map<String, dynamic>.from(c as Map)];
    final q = TextEditingController(text: '${it['name'] ?? ''}');
    final r = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('「${it['name']}」 다른 가게로 고르기', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (var i = 0; i < cands.length; i++)
            InkWell(
              onTap: () => Navigator.pop(ctx, i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${cands[i]['name']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      Text('${cands[i]['addr']} · ${'${cands[i]['cat']}'.split(' > ').last}', style: const TextStyle(fontSize: 12, color: kSub)),
                    ]),
                  ),
                  const Text('이 집', style: TextStyle(fontSize: 13, color: kPointText, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          const Divider(color: kHair),
          const Text('목록에 없으면 가게 이름(지역 포함)을 적어 주세요. 다음 자료 갱신 때 카카오에서 찾아 후보로 다시 올려요.', style: TextStyle(fontSize: 12, color: kSub)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: q, decoration: admDeco('예: 인천 구월동 ○○식당'))),
            const SizedBox(width: 8),
            admBtn('직접 연결', () => Navigator.pop(ctx, q.text.trim()), strong: true),
          ]),
        ]),
      ),
    );
    if (r is int) {
      await decide(key, it, 'ok', place: cands[r]);
    } else if (r is String && r.isNotEmpty) {
      await decide(key, it, 'manual', query: r);
    }
    q.dispose();
  }

  Widget thumb(String vid) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network('https://i.ytimg.com/vi/$vid/mqdefault.jpg',
            width: 96, height: 54, fit: BoxFit.cover, webHtmlElementStrategy: WebHtmlElementStrategy.fallback, errorBuilder: (_, __, ___) => Container(width: 96, height: 54, color: const Color(0xFFEDEDF0))),
      );

  @override
  Widget build(BuildContext context) {
    final l = items;
    if (l == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (l.isEmpty && nofind.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('쯔양 영상에서 뽑은 가게 후보가 여기에 모여요.\n구글 AI 키를 넣고 자료를 모으면 시작합니다.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kSub, height: 1.5)),
        ),
      );
    }
    final open = [for (final it in l) if (done || !dec.containsKey('${it['key']}')) it];
    final lostOpen = [for (final it in nofind) if (done || !dec.containsKey('${it['vid']}_m')) it];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Row(children: [
          Expanded(
            child: Text('남은 후보 ${l.where((x) => !dec.containsKey('${x['key']}')).length} · 못 찾은 영상 ${nofind.length} · $updated',
                style: const TextStyle(fontSize: 12, color: kSub)),
          ),
          admBtn(lost ? '후보 보기' : '못 찾은 영상', () => setState(() => lost = !lost)),
          const SizedBox(width: 6),
          admBtn(done ? '남은 것만' : '정한 것도', () => setState(() => done = !done)),
        ]),
      ),
      const Divider(height: 1, color: kHair),
      Expanded(
        child: lost
            ? ListView.separated(
                itemCount: lostOpen.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: kHair),
                itemBuilder: (_, i) {
                  final it = lostOpen[i];
                  final key = '${it['vid']}_m';
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(children: [
                      GestureDetector(onTap: () => openUrl('https://www.youtube.com/watch?v=${it['vid']}'), child: thumb('${it['vid']}')),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${it['t']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: kInk)),
                          Text('${it['ch']} · ${it['date']}${it['inc'] == true ? ' · 인천' : ''}', style: const TextStyle(fontSize: 11.5, color: kSub)),
                        ]),
                      ),
                      if (dec.containsKey(key))
                        Text('${dec[key]!['query'] ?? ''}', style: const TextStyle(fontSize: 12, color: kPointText))
                      else
                        admBtn('직접 연결', () => wrong(key, {...it, 'name': '', 'cands': const []})),
                    ]),
                  );
                },
              )
            : ListView.separated(
                itemCount: open.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: kHair),
                itemBuilder: (_, i) {
                  final it = open[i];
                  final key = '${it['key']}';
                  final cands = (it['cands'] ?? []) as List;
                  final b = (it['best'] ?? -1) as int;
                  final best = b >= 0 && b < cands.length ? Map<String, dynamic>.from(cands[b] as Map) : null;
                  final d = dec[key];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      GestureDetector(onTap: () => openUrl('https://www.youtube.com/watch?v=${it['vid']}'), child: thumb('${it['vid']}')),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            if (it['check'] == true)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(border: Border.all(color: kAccent), borderRadius: BorderRadius.circular(3)),
                                child: Text('${it['note'] ?? ''}'.isNotEmpty ? '${it['note']}' : '확인 필요',
                                    style: const TextStyle(fontSize: 10.5, color: kAccent, fontWeight: FontWeight.w700)),
                              ),
                            Expanded(
                              child: Text('${it['name']}${'${it['region'] ?? ''}'.isNotEmpty ? ' · ${it['region']}' : ''}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
                            ),
                          ]),
                          const SizedBox(height: 2),
                          Text(best == null ? '카카오에서 못 찾음' : '→ ${best['name']} · ${best['addr']}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: best == null ? kAccent : kInk)),
                          Text('${it['t']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: kSub)),
                          if (d != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                  switch ('${d['status']}') {
                                    'ok' => '맞음 · ${(d['place'] as Map?)?['name'] ?? ''}${'${d['by'] ?? ''}'.isNotEmpty ? ' · 김부장 처리' : ' (다음 자료 갱신 때 지도에)'}',
                                    'skip' => '${d['why'] ?? ''}'.isNotEmpty ? '제외 · ${d['why']} · 김부장 처리' : '제외함',
                                    'manual' => '직접 연결: ${d['query']}',
                                    _ => '${d['status']}',
                                  },
                                  style: const TextStyle(fontSize: 12, color: kPointText, fontWeight: FontWeight.w600)),
                            ),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      Column(children: [
                        admBtn('맞음', best == null ? null : () => decide(key, it, 'ok', place: best), strong: true),
                        const SizedBox(height: 4),
                        admBtn('틀림', () => wrong(key, it)),
                        const SizedBox(height: 4),
                        admBtn('제외', () => decide(key, it, 'skip'), danger: true),
                      ]),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }
}

// ---- 앱 켤 때 팝업 ----
Future<void> showHomePopup(BuildContext context, Map<String, dynamic> p) async {
  final ver = ((p['ver'] ?? 0) as num).toInt();
  final today = nowKst().toIso8601String().substring(0, 10);
  try {
    final sp = await SharedPreferences.getInstance();
    if (sp.getString('popup_skip') == '$today|$ver|${p['title']}') return;
  } catch (_) {}
  if (!context.mounted) return;
  final img = '${p['image'] ?? ''}';
  await showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (img.isNotEmpty) ConstrainedBox(constraints: const BoxConstraints(maxHeight: 360), child: bannerImage(HomeBanner({'image': img}))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if ('${p['title'] ?? ''}'.isNotEmpty) Text('${p['title']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kInk)),
              if ('${p['body'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('${p['body']}', style: const TextStyle(fontSize: 14, color: kInk, height: 1.45)),
              ],
            ]),
          ),
          Row(children: [
            TextButton(
              onPressed: () async {
                try {
                  final sp = await SharedPreferences.getInstance();
                  await sp.setString('popup_skip', '$today|$ver|${p['title']}');
                } catch (_) {}
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('오늘 하루 보지 않기', style: TextStyle(fontSize: 13, color: kSub)),
            ),
            const Spacer(),
            if ('${p['link'] ?? ''}'.startsWith('http'))
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  openUrl('${p['link']}');
                },
                child: const Text('자세히 보기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kAccent)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk))),
            const SizedBox(width: 6),
          ]),
        ]),
      ),
    ),
  );
}

// 회원 탈퇴: 한 번 더 묻고 계정을 지운다 (오래전에 로그인했으면 다시 로그인해야 함)
Future<void> leaveAccount(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('회원 탈퇴', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: const Text('계정과 계정에 저장한 콕한 집, 내가 쓴 후기·사진을 모두 지워요. 되돌릴 수 없어요. 이 휴대폰에 있는 목록은 그대로 남아요.', style: TextStyle(fontSize: 14, height: 1.45)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('탈퇴하기', style: TextStyle(color: kInk, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await reviews.wipeMine(); // 내가 쓴 후기·사진·공감·신고, 계정 문서까지
    await fbUser?.delete();
    if (context.mounted) admToast(context, '탈퇴했어요. 그동안 고마웠어요');
  } on fa.FirebaseAuthException catch (e) {
    if (context.mounted) admToast(context, e.code == 'requires-recent-login' ? '보안을 위해 다시 로그인한 뒤 탈퇴해 주세요' : authMsg(e.code));
  }
}

// ---------- 계정 (위쪽 사람 단추 · 내 콕 맨 위) ----------
String userName(fa.User u) => (u.displayName ?? '').trim().isNotEmpty ? u.displayName!.trim() : ((u.email ?? '').isNotEmpty ? u.email!.split('@').first : '회원');

String userSub(fa.User u) {
  final ids = u.providerData.map((p) => p.providerId).toList();
  if (ids.any((x) => x.contains('kakao'))) return '카카오 계정';
  if (ids.contains('google.com')) return '구글 계정';
  return u.email ?? '이메일 계정';
}

// 계정 사진: 카카오·구글 사진이 있으면 그 사진, 없으면 이름 첫 글자
class UserAvatar extends StatelessWidget {
  final fa.User? user;
  final double size;
  const UserAvatar(this.user, {super.key, this.size = 30});
  @override
  Widget build(BuildContext context) {
    final u = user;
    final initial = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: kAccentTint, shape: BoxShape.circle),
      child: u == null
          ? LineIcon('user', size: size * 0.62, color: kAccent)
          : Text(userName(u).characters.first, style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: kAccent)),
    );
    final url = u?.photoURL ?? '';
    if (!url.startsWith('http')) return initial;
    return ClipOval(
      child: Image.network(url,
          width: size, height: size, fit: BoxFit.cover, webHtmlElementStrategy: WebHtmlElementStrategy.fallback, errorBuilder: (_, __, ___) => initial),
    );
  }
}

// 카카오 바로 시작 (내 콕 맨 위 단추) — 창을 거치지 않고 한 번에
Future<void> quickKakao(BuildContext context) async {
  if (!await fbReady()) {
    if (context.mounted) admToast(context, '로그인은 준비 중이에요');
    return;
  }
  final e = await signInKakao();
  if (e != null && context.mounted) admToast(context, e);
}

void openAdmin(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPage(places: allPlaces(), onChanged: onAdminChanged)));

// 위쪽 사람 단추: 로그인 전이면 로그인 창, 로그인했으면 계정 메뉴
Future<void> openAccount(BuildContext context) async {
  final u = fbOn ? fbUser : null;
  if (u == null) {
    await openLogin(context);
    return;
  }
  if (!context.mounted) return;
  Widget item(BuildContext ctx, String label, VoidCallback onTap, {Color color = kInk}) => InkWell(
        onTap: () {
          Navigator.pop(ctx);
          onTap();
        },
        child: Container(
          height: 50,
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: kHair))),
          child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: color)),
        ),
      );
  await showModalBottomSheet(
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
          padding: EdgeInsets.fromLTRB(22, 22, 22, 12 + MediaQuery.of(ctx).padding.bottom),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              UserAvatar(u, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(userName(u), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kInk)),
                  const SizedBox(height: 2),
                  Text(userSub(u), style: const TextStyle(fontSize: 12, color: kSub)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            if (isAdmin) item(ctx, '관리자 화면', () => openAdmin(context)),
            item(ctx, '설정', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()))),
            item(ctx, '로그아웃', () => fbAuth.signOut(), color: kSub),
          ]),
        ),
      ),
    ),
  );
}

// 위쪽 사람 단추 (홈·영상 머리줄)
class AccountButton extends StatelessWidget {
  const AccountButton({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: authTick,
        builder: (context, __, ___) {
          final u = fbOn ? fbUser : null;
          return IconButton(
            onPressed: () => openAccount(context),
            visualDensity: VisualDensity.compact,
            tooltip: u == null ? '로그인' : '내 계정',
            icon: u == null ? const LineIcon('user', size: 24) : UserAvatar(u, size: 28),
          );
        },
      );
}

// 내 콕 맨 위 계정 줄: 로그인 전이면 카카오로 바로 시작, 로그인했으면 내 계정 (관리자면 관리자 단추)
class AccountStrip extends StatelessWidget {
  final int koks;
  const AccountStrip({super.key, required this.koks});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: authTick,
        builder: (context, __, ___) {
          final u = fbOn ? fbUser : null;
          final box = BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE6E8EC)),
            boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 14)],
          );
          if (u == null) {
            // 두 줄: 위엔 왜 로그인하는지, 아래엔 카카오 바로 시작 + 다른 방법 (작은 휴대폰에서도 글이 잘리지 않게)
            Widget btn(String label, VoidCallback onTap, {required bool kakao}) => Semantics(
                  button: true,
                  label: kakao ? '카카오로 로그인' : '구글이나 이메일로 로그인',
                  onTap: onTap,
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: onTap,
                    child: Container(
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: kakao ? const Color(0xFFFEE500) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: kakao ? null : Border.all(color: kPillLine),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (kakao) ...[
                          const Icon(Icons.chat_bubble_rounded, size: 15, color: Color(0xFF191919)),
                          const SizedBox(width: 6),
                        ],
                        Text(label,
                            maxLines: 1,
                            style: TextStyle(fontSize: 13.5, fontWeight: kakao ? FontWeight.w700 : FontWeight.w500, color: const Color(0xFF191919))),
                      ]),
                    ),
                  ),
                );
            return Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: box,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  UserAvatar(null, size: 40),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text.rich(
                          TextSpan(children: [
                            TextSpan(text: '로그인', style: TextStyle(fontWeight: FontWeight.w700)),
                            TextSpan(text: '하고 콕한 집 지키기', style: TextStyle(fontWeight: FontWeight.w400)),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, color: kInk, letterSpacing: -0.3)),
                      SizedBox(height: 2),
                      Text('휴대폰을 바꿔도 그대로 볼 수 있어요', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: kSub)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(flex: 3, child: btn('카카오로 시작하기', () => quickKakao(context), kakao: true)),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: btn('구글 · 이메일', () => openLogin(context), kakao: false)),
                ]),
              ]),
            );
          }
          return InkWell(
            onTap: () => openAccount(context),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: box,
              child: Row(children: [
                UserAvatar(u, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(userName(u), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: kInk)),
                    const SizedBox(height: 2),
                    Text(koks > 0 ? '콕한 집 $koks곳 저장 중' : '콕하면 계정에 저장돼요',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kSub)),
                  ]),
                ),
                if (isAdmin) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => openAdmin(context),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), border: Border.all(color: kPillLine)),
                      child: const Text('관리자', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kInk)),
                    ),
                  ),
                ],
                const Icon(Icons.chevron_right_rounded, size: 22, color: kSub),
              ]),
            ),
          );
        },
      );
}

// ---------------- 지역 수집: 인천 → 서울 → 경기 → 광역시 → 그 밖의 시·군 순서와 진행 상황 ----------------
// 자료는 매일 수집이 끝날 때 collector/auto_areas.py가 web/data/progress.json에 적는다.
class RegionProgressTab extends StatefulWidget {
  const RegionProgressTab({super.key});
  @override
  State<RegionProgressTab> createState() => _RegionProgressTabState();
}

class _RegionProgressTabState extends State<RegionProgressTab> {
  Map<String, dynamic>? data;
  String? error;
  final Set<int> opened = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final res = await http.get(Uri.parse('${dataUrl('progress.json')}?t=${DateTime.now().millisecondsSinceEpoch}'));
      if (res.statusCode != 200) throw Exception('${res.statusCode}');
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (mounted) setState(() => data = j);
    } catch (e) {
      if (mounted) setState(() => error = '진행 상황을 받지 못했습니다');
    }
  }

  static String _md(String s) {
    // 2026-11-22 19:01 → 11.22
    final m = RegExp(r'\d{4}-(\d{2})-(\d{2})').firstMatch(s);
    return m == null ? '' : '${int.parse(m.group(1)!)}.${int.parse(m.group(2)!)}';
  }

  Widget pill(String st, int? o) {
    final (t, bg, fg, line) = switch (st) {
      'done' => ('완료', kAccentTint, kPointText, const Color(0xFFFFC9B8)),
      'run' => ('모으는 중', kInk, Colors.white, kInk),
      'covered' => ('포함', Colors.white, kSub, kLine),
      _ => ('대기 ${o ?? ''}', Colors.white, kInk, kPillLine),
    };
    return Container(
      width: 66,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11), border: Border.all(color: line, width: 1)),
      child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg, height: 1.1)),
    );
  }

  Widget row(Map<String, dynamic> r) {
    final st = '${r['st']}';
    final views = (r['v'] as num?)?.toInt() ?? 0;
    final name = Text('${r['n']}',
        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: st == 'queue' ? FontWeight.w500 : FontWeight.w700, color: st == 'covered' ? kSub : kInk));
    final yt = Text('유튜버 ${r['yt']}곳', style: const TextStyle(fontSize: 12, color: kSub));
    // 대기: 한 줄 (촘촘하게)
    if (st == 'queue') {
      return Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kHair, width: 1))),
        child: Row(children: [
          pill(st, (r['o'] as num?)?.toInt()),
          const SizedBox(width: 10),
          Expanded(child: name),
          if (views > 0) ...[Text('앱에서 $views번 봄', style: const TextStyle(fontSize: 11.5, color: kSub)), const SizedBox(width: 10)],
          yt,
        ]),
      );
    }
    // 완료 · 모으는 중 · 포함: 두 줄 (아래 줄에 모은 내용)
    final all = (r['all'] as num?)?.toInt() ?? 0;
    final up = _md('${r['up'] ?? ''}');
    final detail = switch (st) {
      'covered' => '「${r['in']}」 수집에 함께 들어가요',
      _ when all == 0 => '구글 무료량이 다시 채워지면 시작해요',
      _ => '가게 $all곳  ·  별점 ${r['rated']}  ·  영업시간 ${r['hours']}  ·  블로그 ${r['blog']}${up.isEmpty ? '' : '  ·  $up 갱신'}',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kHair, width: 1))),
      child: Row(children: [
        pill(st, null),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: name), yt]),
            const SizedBox(height: 2),
            Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: st == 'done' ? kInk : kSub)),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null) {
      return Center(
        child: error == null
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent))
            : TextButton(onPressed: () => setState(() {
                error = null;
                load();
              }), child: Text('$error · 다시 받기')),
      );
    }
    final g = (d['google'] as Map?) ?? const {};
    final used = (g['used'] as num?)?.toInt() ?? 0, limit = math.max(1, (g['limit'] as num?)?.toInt() ?? 900);
    final rows = [for (final r in (d['rows'] as List? ?? const [])) (r as Map).cast<String, dynamic>()];
    final phases = [for (final p in (d['phases'] as List? ?? const [])) '$p'];
    int count(String st) => rows.where((r) => r['st'] == st).length;
    final refill = '${g['refill'] ?? ''}';
    final rm = RegExp(r'\d{4}-(\d{2})-(\d{2})').firstMatch(refill);
    final refillText = rm == null ? '다음 달 1일' : '${int.parse(rm.group(1)!)}월 ${int.parse(rm.group(2)!)}일';
    final rf = RegExp(r'(\d{4})-(\d{2})').firstMatch('${g['refresh_from'] ?? ''}');
    final refreshText = rf == null ? '' : '${rf.group(1)}년 ${int.parse(rf.group(2)!)}월';
    final full = g['full'] is List ? g['full'] as List : null, lite = g['lite'] is List ? g['lite'] as List : null;
    final blog = d['blog'] as Map?;
    final blogUsed = (blog?['used'] as num?)?.toInt() ?? 0, blogLimit = math.max(1, (blog?['limit'] as num?)?.toInt() ?? 30000);
    final blogCap = (blog?['cap'] as num?)?.toInt() ?? blogLimit;
    final run = rows.where((r) => r['st'] == 'run').firstOrNull;
    final next = rows.where((r) => r['st'] == 'queue').firstOrNull;
    return RefreshIndicator(
      onRefresh: load,
      color: kAccent,
      child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        // 요약: 구글 무료량 · 완료/모으는 중/대기 · 지금과 다음
        Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: kokCard().copyWith(borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('이번 달 구글 조회', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
              const Spacer(),
              Text('$used / $limit번', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
            ]),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: (used / limit).clamp(0.0, 1.0), minHeight: 6, backgroundColor: kHair, color: used >= limit ? kAccent : kInk),
            ),
            const SizedBox(height: 7),
            Text(
              [
                for (final line in [
                if (full != null && lite != null && full.length > 1 && lite.length > 1)
                  '편의 정보까지 ${full[0]} / ${full[1]}번 · 기본 정보 ${lite[0]} / ${lite[1]}번',
                if (((g['paid'] as num?)?.toInt() ?? 0) > 0)
                  '이번 달은 승인한 유료 ${g['paid']}번 포함 (이번 달만)'
                else
                  '조회 종류마다 무료분 + 조금 넘는 몫까지 (상한으로 막음)',
                d['wait'] == true
                    ? '새 동네를 시작할 만큼 남지 않아 $refillText에 다시 채워지면 이어서 모읍니다'
                    : '남은 조회 ${g['left'] ?? '-'}번 · 유튜버 집은 편의 정보까지, 블로그 후보는 기본 정보부터',
                if (refreshText.isNotEmpty) '이미 받은 가게 다시 받기는 $refreshText부터 (그 전엔 전부 새 동네에)',
                ]) keepWords(line), // 낱말 가운데서 줄이 꺾이지 않게
              ].join('\n'),
              style: const TextStyle(fontSize: 12, color: kSub, height: 1.4),
            ),
            // 카카오 블로그 검색: 하루 무료 3만 번 (11-23 대표님 승인: 하루 사용량 관리)
            if (blog != null) ...[
              const SizedBox(height: 14),
              Row(children: [
                const Text('오늘 블로그 검색', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
                const Spacer(),
                Text('${commas(blogUsed)} / ${commas(blogLimit)}번', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
              ]),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                    value: (blogUsed / blogLimit).clamp(0.0, 1.0), minHeight: 6, backgroundColor: kHair, color: blogUsed >= blogCap ? kAccent : kInk),
              ),
              const SizedBox(height: 7),
              Text(
                keepWords(blogUsed >= blogCap
                    ? '오늘 몫을 다 썼어요 · 한국 시각 자정에 다시 채워지면 새 동네를 이어서 엽니다'
                    : '하루 무료 ${commas(blogLimit)}번 · 새 동네는 남은 양 안에서만 열어요 (하루 2~3곳)'),
                style: const TextStyle(fontSize: 12, color: kSub, height: 1.4),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              for (final (t, n) in [('완료', count('done')), ('모으는 중', count('run')), ('대기', count('queue'))]) ...[
                Text(t, style: const TextStyle(fontSize: 12.5, color: kSub)),
                const SizedBox(width: 4),
                Text('$n곳', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kInk)),
                const SizedBox(width: 14),
              ],
            ]),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: '지금 '),
                TextSpan(text: run == null ? '없음' : '${run['s']} ${run['n']}', style: const TextStyle(fontWeight: FontWeight.w700, color: kInk)),
                const TextSpan(text: '   다음 '),
                TextSpan(text: next == null ? '없음' : '${next['s']} ${next['n']}', style: const TextStyle(fontWeight: FontWeight.w700, color: kInk)),
              ]),
              style: const TextStyle(fontSize: 12.5, color: kSub),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
          child: Text('순서: ${phases.join(' → ')}  ·  같은 시·도 안에서는 앱에서 많이 본 곳 → 유튜버가 많이 다녀간 곳. 자료 ${_md('${d['updated']}')} 기준',
              style: const TextStyle(fontSize: 11.5, color: kSub, height: 1.4)),
        ),
        for (var i = 0; i < phases.length; i++)
          Builder(builder: (_) {
            final list = rows.where((r) => (r['p'] as num?)?.toInt() == i).toList();
            if (list.isEmpty) return const SizedBox();
            final done = list.where((r) => r['st'] == 'done').length;
            final open = opened.contains(i) || list.length <= 14;
            final shown = open ? list : list.take(10).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                color: const Color(0xFFF6F6F8),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${i + 1}. ${phases[i]}', style: const TextStyle(fontWeight: FontWeight.w800, color: kInk)),
                  TextSpan(text: '   완료 $done / ${list.length}곳', style: const TextStyle(color: kSub)),
                ]), style: const TextStyle(fontSize: 13)),
              ),
              for (final r in shown) row(r),
              if (!open)
                InkWell(
                  onTap: () => setState(() => opened.add(i)),
                  child: SizedBox(
                    height: 40,
                    child: Center(child: Text('나머지 ${list.length - shown.length}곳 펼쳐 보기', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kInk))),
                  ),
                ),
            ]);
          }),
      ]),
    );
  }
}
