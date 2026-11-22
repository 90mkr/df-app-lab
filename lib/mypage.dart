part of 'main.dart';

// ---------------- 내 콕 (마이페이지) 묶음 메뉴 · 공지사항 · 사용법 ----------------
// 위: 계정 → 알약 3개(콕한 집·최근 본 집·내가 쓴 후기) → 고른 목록 최근 5곳
// 아래: 콕플 안내 · 약관·정책 · 계정 · 앱 정보 (서비스가 늘면 묶음에 줄만 더하면 됨)

// 묶음 메뉴 한 줄 (가는 선 아이콘 + 이름 + 작은 설명 + ›)
Widget menuRow(String label, {IconData? icon, String? sub, VoidCallback? onTap, Widget? trail, Color color = kInk}) => Semantics(
      button: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
          child: Row(children: [
            if (icon != null) ...[Icon(icon, size: 21, color: color == kInk ? const Color(0xFF3A3F48) : color), const SizedBox(width: 13)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: color, height: 1.25)),
                if (sub != null && sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w400, color: kSub, height: 1.3)),
                ],
              ]),
            ),
            trail ?? (onTap == null ? const SizedBox() : const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFFB4B8C0))),
          ]),
        ),
      ),
    );

Widget menuGroup(String title, List<Widget> rows) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 9),
        child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.2)),
      ),
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: kokCard().copyWith(borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, color: kHair, indent: 16, endIndent: 16),
            rows[i],
          ],
        ]),
      ),
    ]);

// ---- 공지사항 (관리자 화면에서 올림 · config/notices 한 문서) ----
class Notice {
  final String id, title, body, date;
  Notice(Map<String, dynamic> j)
      : id = '${j['id'] ?? ''}',
        title = '${j['title'] ?? ''}',
        body = '${j['body'] ?? ''}',
        date = '${j['date'] ?? ''}';
  Map<String, dynamic> get json => {'id': id, 'title': title, 'body': body, 'date': date};
}

final ValueNotifier<List<Notice>?> notices = ValueNotifier(null);
Future<List<Notice>> loadNotices({bool force = false}) async {
  if (notices.value != null && !force) return notices.value!;
  try {
    if (!await fbReady()) return const [];
    final d = await fsdb.doc('config/notices').get();
    final l = [for (final x in (d.data()?['items'] as List?) ?? const []) if (x is Map) Notice(Map<String, dynamic>.from(x))]..sort((a, b) => b.date.compareTo(a.date));
    notices.value = l;
    return l;
  } catch (_) {
    return notices.value ?? const [];
  }
}

Future<String?> saveNotices(List<Notice> l) async {
  try {
    await fsdb.doc('config/notices').set({'items': [for (final n in l) n.json], 'at': fs.FieldValue.serverTimestamp()});
    notices.value = [...l]..sort((a, b) => b.date.compareTo(a.date));
    return null;
  } catch (e) {
    return '저장하지 못했어요 ($e)';
  }
}

// 하위 화면 공통 틀: 뒤로 + 제목
Widget subPage(BuildContext context, String title, Widget body, {Widget? action}) => Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: narrow(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 12, 4),
            child: Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), tooltip: '뒤로', icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: kInk)),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.4))),
              if (action != null) action,
            ]),
          ),
          Expanded(child: body),
        ])),
      ),
    );

class NoticePage extends StatefulWidget {
  const NoticePage({super.key});
  @override
  State<NoticePage> createState() => _NoticePageState();
}

class _NoticePageState extends State<NoticePage> {
  String open = '';
  @override
  void initState() {
    super.initState();
    loadNotices(force: true);
  }

  @override
  Widget build(BuildContext context) => subPage(
        context,
        '공지사항',
        ValueListenableBuilder<List<Notice>?>(
          valueListenable: notices,
          builder: (_, l, __) {
            if (l == null) return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)));
            if (l.isEmpty) return const Center(child: Text('아직 올라온 공지가 없어요.', style: TextStyle(fontSize: 13, color: kSub)));
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
              itemCount: l.length,
              separatorBuilder: (_, __) => const Divider(height: 1, thickness: 1, color: kHair),
              itemBuilder: (_, i) {
                final n = l[i];
                final on = open == n.id;
                return InkWell(
                  onTap: () => setState(() => open = on ? '' : n.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(n.title, style: TextStyle(fontSize: 15, fontWeight: on ? FontWeight.w700 : FontWeight.w600, color: kInk, height: 1.35))),
                        Icon(on ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 22, color: kSub),
                      ]),
                      const SizedBox(height: 3),
                      Text(n.date, style: const TextStyle(fontSize: 11.5, color: kSub)),
                      if (on) ...[
                        const SizedBox(height: 10),
                        Text(n.body, style: const TextStyle(fontSize: 13.5, color: Color(0xFF3A3F48), height: 1.55)),
                      ],
                    ]),
                  ),
                );
              },
            );
          },
        ),
      );
}

// ---- 콕플 사용법 ----
class GuidePage extends StatelessWidget {
  const GuidePage({super.key});
  @override
  Widget build(BuildContext context) {
    Widget part(String k, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 58, child: StickerFace(k, size: 58)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.3)),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(fontSize: 13, color: Color(0xFF4A4F59), height: 1.5)),
              ]),
            ),
          ]),
        );
    return subPage(
      context,
      '콕플 사용법',
      ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 30), children: [
        part('yt_ok', '홈', '추천 영상, 유튜버 따라 먹기, 방금 올라온 후기를 한눈에 봐요. 위 지역 단추로 동네를 바꿀 수 있어요.'),
        part('again', '지도', '전국 유튜버 맛집이 처음부터 내 주변으로 보여요. 「지역 검색」으로 다른 동네로 가고, 「순위」로 지금 보는 곳의 순위를 봐요.'),
        part('life', '자세히 보기', '별점·영업시간·화제 순위까지 모은 동네에서는 지도 위 「자세히 보기」를 누르면 그 동네 지도로 바뀌어요.'),
        part('value', '후기', '가게 화면에서 「후기 남기기」를 누르고 스티커를 붙여요. 스티커 하나면 끝이고, 한 줄 평과 사진은 골라서 넣어요.'),
        part('kind', '내 콕', '마음에 드는 집은 가게 화면 오른쪽 위 「콕」으로 저장해요. 로그인하면 휴대폰을 바꿔도 그대로예요.'),
      ]),
    );
  }
}

// ---- 공지사항 관리 (관리자 화면 칸) ----
class NoticeAdminTab extends StatefulWidget {
  const NoticeAdminTab({super.key});
  @override
  State<NoticeAdminTab> createState() => _NoticeAdminTabState();
}

class _NoticeAdminTabState extends State<NoticeAdminTab> {
  final title = TextEditingController(), body = TextEditingController();
  String editing = '';

  @override
  void initState() {
    super.initState();
    loadNotices(force: true);
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final t = title.text.trim(), b = body.text.trim();
    if (t.isEmpty) {
      admToast(context, '제목을 적어 주세요');
      return;
    }
    final l = [...?notices.value];
    final k = nowKst();
    final date = '${k.year}.${k.month.toString().padLeft(2, '0')}.${k.day.toString().padLeft(2, '0')}';
    if (editing.isEmpty) {
      l.add(Notice({'id': '${DateTime.now().millisecondsSinceEpoch}', 'title': t, 'body': b, 'date': date}));
    } else {
      final i = l.indexWhere((n) => n.id == editing);
      if (i >= 0) l[i] = Notice({'id': editing, 'title': t, 'body': b, 'date': l[i].date});
    }
    final e = await saveNotices(l);
    if (!mounted) return;
    admToast(context, e ?? (editing.isEmpty ? '공지를 올렸어요' : '공지를 고쳤어요'));
    if (e == null) {
      setState(() => editing = '');
      title.clear();
      body.clear();
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<Notice>?>(
        valueListenable: notices,
        builder: (_, l, __) => ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 30), children: [
          Text(editing.isEmpty ? '새 공지' : '공지 고치기', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
          const SizedBox(height: 8),
          TextField(controller: title, decoration: admDeco('제목')),
          const SizedBox(height: 8),
          TextField(controller: body, minLines: 4, maxLines: 10, decoration: admDeco('내용')),
          const SizedBox(height: 8),
          Row(children: [
            admBtn(editing.isEmpty ? '올리기' : '고치기', save, strong: true),
            if (editing.isNotEmpty) ...[
              const SizedBox(width: 8),
              admBtn('취소', () {
                setState(() => editing = '');
                title.clear();
                body.clear();
              }),
            ],
          ]),
          const SizedBox(height: 22),
          const Divider(height: 1, color: kHair),
          for (final n in l ?? const <Notice>[])
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kHair))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kInk)),
                    Text(n.date, style: const TextStyle(fontSize: 11.5, color: kSub)),
                  ]),
                ),
                admBtn('고치기', () {
                  setState(() => editing = n.id);
                  title.text = n.title;
                  body.text = n.body;
                }),
                const SizedBox(width: 6),
                admBtn('지우기', () async {
                  final e = await saveNotices([...?notices.value]..removeWhere((x) => x.id == n.id));
                  if (context.mounted) admToast(context, e ?? '지웠어요');
                }, danger: true),
              ]),
            ),
          if ((l ?? const []).isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('올린 공지가 없어요.', style: TextStyle(fontSize: 13, color: kSub))),
        ]),
      );
}

// ---- 차단한 사람 (설정·내 콕) ----
Future<void> openBlocked(BuildContext context) async {
  await reviews.loadLocal();
  if (!context.mounted) return;
  final n = reviews.blocked.length;
  if (n == 0) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('차단한 사람이 없어요. 후기의 「신고·차단」에서 차단할 수 있어요'), duration: Duration(seconds: 3)));
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('차단한 사람 $n명', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: Text('${reviews.blocked.values.take(8).join(', ')}${n > 8 ? ' 외 ${n - 8}명' : ''}\n\n모두 풀면 이분들 후기가 다시 보여요.', style: const TextStyle(fontSize: 14, height: 1.45)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('닫기')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('모두 풀기', style: TextStyle(color: kInk, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  if (ok == true) {
    await reviews.unblockAll();
    if (context.mounted) admToast(context, '차단을 모두 풀었어요');
  }
}

// 내 콕 아래 묶음 메뉴들
List<Widget> myMenus(BuildContext context) {
  final u = fbOn ? fbUser : null;
  return [
    ValueListenableBuilder<List<Notice>?>(
      valueListenable: notices,
      builder: (_, l, __) => menuGroup('콕플 안내', [
        menuRow('공지사항', icon: Icons.campaign_outlined, sub: (l == null || l.isEmpty) ? null : l.first.title, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NoticePage()))),
        menuRow('콕플 사용법', icon: Icons.help_outline_rounded, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuidePage()))),
        // 메일 대신 앱 안에서 글로 접수 (대표님 지시 11-23) — 답변은 「내 문의」에서
        menuRow('개선 제안하기', icon: Icons.lightbulb_outline_rounded, sub: '불편한 점, 있었으면 하는 기능', onTap: () => openAsk(context, 'idea')),
        menuRow('제휴·광고 문의', icon: Icons.handshake_outlined, sub: '가게 등록·협업 제안', onTap: () => openAsk(context, 'biz')),
        menuRow('문의하기', icon: Icons.edit_note_rounded, sub: '앱 안에서 바로 접수돼요', onTap: () => openAsk(context, 'ask')),
        ValueListenableBuilder<List<Ask>?>(
          valueListenable: myAsks,
          builder: (_, a, __) => menuRow('내 문의', icon: Icons.forum_outlined, sub: myAskSub(a), onTap: () => openMyAsks(context)),
        ),
      ]),
    ),
    const SizedBox(height: 24),
    menuGroup('약관·정책', [
      menuRow('서비스 이용약관', icon: Icons.description_outlined, onTap: () => openUrl(kTermsUrl)),
      menuRow('개인정보처리방침', icon: Icons.privacy_tip_outlined, onTap: () => openUrl(kPrivacyUrl)),
      menuRow('위치정보 이용 안내', icon: Icons.location_on_outlined, sub: '위치는 휴대폰 안에서만 써요', onTap: () => openUrl(kLocationUrl)),
      menuRow('YouTube 서비스 약관', icon: Icons.smart_display_outlined, onTap: () => openUrl('https://www.youtube.com/t/terms')),
    ]),
    const SizedBox(height: 24),
    menuGroup('계정', [
      if (u == null)
        menuRow('로그인 · 회원가입', icon: Icons.login_rounded, sub: '카카오 · 구글 · 이메일', onTap: () => openLogin(context))
      else ...[
        if (isAdmin) menuRow('관리자 화면', icon: Icons.admin_panel_settings_outlined, sub: '배너 · 공지 · 후기 신고', onTap: () => openAdmin(context)),
        menuRow('로그아웃', icon: Icons.logout_rounded, onTap: () => fbAuth.signOut()),
      ],
      ValueListenableBuilder<int>(
        valueListenable: reviews.tick,
        builder: (_, __, ___) => menuRow('차단한 사람', icon: Icons.block_rounded, sub: reviews.blocked.isEmpty ? '후기의 「신고·차단」에서 차단할 수 있어요' : '${reviews.blocked.length}명 · 누르면 모두 풀 수 있어요', onTap: () => openBlocked(context)),
      ),
      if (u != null) menuRow('회원 탈퇴', icon: Icons.person_remove_outlined, sub: '계정과 쓴 후기·사진을 지워요', onTap: () => leaveAccount(context)),
      menuRow('회원 탈퇴 안내', icon: Icons.info_outline_rounded, onTap: () => openUrl(kDeleteUrl)),
    ]),
    const SizedBox(height: 24),
    menuGroup('앱 정보', [
      menuRow('버전', icon: Icons.phone_android_rounded, trail: const Text(kAppVersion, style: TextStyle(fontSize: 12.5, color: kSub))),
    ]),
    const SizedBox(height: 14),
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text('영상과 표지 사진의 저작권은 각 유튜버에게 있습니다.\n지도 © OpenStreetMap · 모범음식점 정보 행정안전부(공공데이터포털)',
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w300, color: kSub, height: 1.4)),
    ),
  ];
}

// 내가 쓴 후기 미리 보기 (내 콕 첫 화면: 기록 + 최근 2개)
class MyReviewsPreview extends StatefulWidget {
  final VoidCallback onAll;
  final ValueChanged<Map<String, dynamic>> onOpen;
  const MyReviewsPreview({super.key, required this.onAll, required this.onOpen});
  @override
  State<MyReviewsPreview> createState() => _MyReviewsPreviewState();
}

class _MyReviewsPreviewState extends State<MyReviewsPreview> {
  String? _uid = '-';
  bool _loading = false;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: authTick,
        builder: (context, __, ___) => ValueListenableBuilder<int>(
          valueListenable: reviews.tick,
          builder: (context, __, ___) {
            final uid = reviews.demo ? 'demo' : (fbOn ? fbUser?.uid : null);
            Widget box(Widget child) => Container(width: double.infinity, decoration: kokCard().copyWith(borderRadius: BorderRadius.circular(14)), child: child);
            if (uid == null) {
              return box(const Padding(
                padding: EdgeInsets.symmetric(vertical: 26, horizontal: 16),
                child: Text('로그인하면 내가 쓴 후기를\n여기에 모아 볼 수 있어요.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kSub, height: 1.5)),
              ));
            }
            if (uid != _uid && !_loading) {
              _uid = uid;
              _loading = true;
              WidgetsBinding.instance.addPostFrameCallback((_) => reviews.loadMine(force: true).whenComplete(() {
                    _loading = false;
                    if (mounted) setState(() {});
                  }));
            }
            final l = reviews.mine;
            if (l == null) {
              return box(const Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent))),
              ));
            }
            if (l.isEmpty) {
              return box(const Padding(
                padding: EdgeInsets.symmetric(vertical: 26, horizontal: 16),
                child: Text('아직 쓴 후기가 없어요.\n가게 화면의 「후기 남기기」로 스티커를 붙여 보세요.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kSub, height: 1.5)),
              ));
            }
            final likes = l.fold<int>(0, (a, r) => a + r.lc);
            final top = stickerRank(l).firstOrNull;
            Widget stat(String n, String t) => Expanded(
                  child: Column(children: [
                    Text(n, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: kInk, letterSpacing: -0.4, height: 1.1)),
                    const SizedBox(height: 3),
                    Text(t, style: const TextStyle(fontSize: 11.5, color: kSub)),
                  ]),
                );
            return box(Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
                child: Row(children: [
                  stat('${l.length}', '쓴 후기'),
                  Container(width: 1, height: 32, color: kHair),
                  stat(commas(likes), '받은 공감'),
                  Container(width: 1, height: 32, color: kHair),
                  Expanded(
                    child: Column(children: [
                      if (top != null) StickerFace(top.$1, size: 30) else const SizedBox(height: 22),
                      const SizedBox(height: 2),
                      Text(top == null ? '많이 쓴 스티커' : (top.$1 == 'menu' ? '${top.$2} 꼭' : kStickers[top.$1]!),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: kInk)),
                    ]),
                  ),
                ]),
              ),
              for (final r in l.take(2)) ...[
                const Divider(height: 1, thickness: 1, color: kHair, indent: 14, endIndent: 14),
                InkWell(
                  onTap: () => widget.onOpen(r.rec),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
                    child: Row(children: [
                      SizedBox(width: 108, height: 56, child: Align(alignment: Alignment.centerLeft, child: FittedBox(fit: BoxFit.scaleDown, child: StickerPile(r.st, menu: r.menu, size: 56, step: 0.55)))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.pname, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: kInk)),
                          const SizedBox(height: 2),
                          Text(r.text.isNotEmpty ? r.text : r.stickerText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF4A4F59))),
                          const SizedBox(height: 1),
                          Text('${agoTime(r.at)}${r.lc > 0 ? ' · 공감 ${r.lc}' : ''}', style: const TextStyle(fontSize: 11, color: kSub)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ],
              const Divider(height: 1, thickness: 1, color: kHair),
              InkWell(
                onTap: widget.onAll,
                child: SizedBox(
                  height: 46,
                  child: Center(
                    child: Text('내가 쓴 후기 전체 보기 (${l.length})  ›', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kInk)),
                  ),
                ),
              ),
            ]));
          },
        ),
      );
}
