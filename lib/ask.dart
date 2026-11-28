part of 'main.dart';

// ---------------- 콕플 문의함 (대표님 지시 2026-11-23) ----------------
// 개선 제안 · 제휴·광고 문의 · 문의 · 가게 정보 수정을 메일 대신 앱 안에서 글로 받는다 (게시판 글쓰기처럼).
// 로그인한 회원만 쓴다(답변을 돌려드리려고). 쓴 사람과 관리자만 본다.
// 관리자는 관리자 화면 「문의함」에서 보고 답변하고, 쓴 사람은 내 콕 › 「내 문의」에서 답변을 본다.

const kAskKinds = {'idea': '개선 제안', 'biz': '제휴·광고', 'ask': '문의', 'fix': '정보 수정'};
const kAskWrite = ['idea', 'biz', 'ask']; // 글쓰기에서 고르는 종류 (정보 수정은 가게 화면에서)

class Ask {
  final String id, uid, nick, kind, title, text, contact, pid, pname, st, ans;
  final List<String> items;
  final DateTime at;
  final DateTime? aat;
  Ask(this.id, Map<String, dynamic> j)
      : uid = '${j['uid'] ?? ''}',
        nick = '${j['nick'] ?? ''}'.isEmpty ? '콕플러' : '${j['nick']}',
        kind = kAskKinds.containsKey(j['kind']) ? '${j['kind']}' : 'ask',
        title = '${j['title'] ?? ''}',
        text = '${j['text'] ?? ''}',
        contact = '${j['contact'] ?? ''}',
        pid = '${j['pid'] ?? ''}',
        pname = '${j['pname'] ?? ''}',
        st = '${j['st'] ?? 'new'}',
        ans = '${j['ans'] ?? ''}',
        items = [for (final x in (j['items'] as List?) ?? const []) '$x'],
        at = _askTime(j['at']) ?? DateTime.now(),
        aat = _askTime(j['aat']);
  bool get done => st == 'done' && ans.trim().isNotEmpty;
  String get kindName => kAskKinds[kind] ?? '문의';
}

DateTime? _askTime(Object? v) => v is fs.Timestamp ? v.toDate() : (v is DateTime ? v : null);

String askDate(DateTime t) {
  final k = t.toUtc().add(const Duration(hours: 9));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${k.year}.${two(k.month)}.${two(k.day)} ${two(k.hour)}:${two(k.minute)}';
}

// 한글 낱말이 줄 끝에서 쪼개지지 않게: 글자 사이에 「낱말 잇기」 표시를 넣어 띄어쓰기에서만 줄을 바꿈 (화면에 보이는 글에만)
String keepWords(String s) => s.split(' ').map((w) => w.characters.join('\u2060')).join(' ');

final ValueNotifier<List<Ask>?> myAsks = ValueNotifier(null);
final List<Ask> _demoAsks = [];

// 화면 점검용 (웹 주소 ?demo=1): 답변이 온 글 하나 + 기다리는 글 하나
List<Ask> _askDemoSeed() {
  final now = DateTime.now();
  return [
    Ask('d2', {
      'uid': 'demo', 'nick': '바삭한 콕플러', 'kind': 'biz', 'title': '송도 브런치 카페 광고 문의',
      'text': '송도에서 브런치 카페를 하고 있어요.\n콕플 지도에 가게를 알리고 싶은데 광고 방법과 비용이 궁금합니다.', 'contact': '010-1234-5678',
      'st': 'new', 'at': now.subtract(const Duration(hours: 3)),
    }),
    Ask('d1', {
      'uid': 'demo', 'nick': '바삭한 콕플러', 'kind': 'idea', 'title': '지도에서 가게 이름이 겹쳐 보여요',
      'text': '가게가 많은 동네에서 지도를 작게 보면 이름표가 겹쳐서 잘 안 보여요. 겹치는 건 숫자로 묶어 주시면 좋겠어요.',
      'st': 'done', 'ans': '좋은 의견 고맙습니다. 다음 업데이트에서 가까운 가게는 숫자로 묶어 보이게 바꿀게요.',
      'at': now.subtract(const Duration(days: 2)), 'aat': now.subtract(const Duration(days: 1)),
    }),
  ];
}

Future<List<Ask>> loadMyAsks() async {
  if (reviews.demo) {
    if (_demoAsks.isEmpty) _demoAsks.addAll(_askDemoSeed());
    final l = [..._demoAsks]..sort((a, b) => b.at.compareTo(a.at));
    myAsks.value = l;
    return l;
  }
  final u = fbUser;
  if (u == null) {
    myAsks.value = const [];
    return const [];
  }
  try {
    // 내 글만 (정렬은 휴대폰에서 — 따로 색인을 만들지 않아도 되게)
    final q = await fsdb.collection('asks').where('uid', isEqualTo: u.uid).limit(200).get();
    final l = [for (final d in q.docs) Ask(d.id, d.data())]..sort((a, b) => b.at.compareTo(a.at));
    myAsks.value = l;
    return l;
  } catch (_) {
    myAsks.value ??= const [];
    return myAsks.value!;
  }
}

String _cut(String s, int n) => s.length > n ? s.substring(0, n) : s;

Future<String?> sendAsk({
  required String kind,
  required String title,
  required String text,
  String contact = '',
  String pid = '',
  String pname = '',
  List<String> items = const [],
}) async {
  final nick = reviews.demo ? '바삭한 콕플러' : await reviews.nick();
  final data = <String, dynamic>{
    'nick': _cut(nick, 12), 'kind': kind, 'title': _cut(title.trim(), 40), 'text': _cut(text.trim(), 1000),
    'contact': _cut(contact.trim(), 60), 'pid': _cut(pid, 40), 'pname': _cut(pname, 60), 'items': items.take(6).toList(), 'st': 'new',
  };
  if (reviews.demo) {
    if (_demoAsks.isEmpty) _demoAsks.addAll(_askDemoSeed());
    _demoAsks.insert(0, Ask('d${DateTime.now().millisecondsSinceEpoch}', {...data, 'uid': 'demo', 'at': DateTime.now()}));
    myAsks.value = [..._demoAsks];
    return null;
  }
  final u = fbUser;
  if (u == null) return '로그인한 뒤에 보낼 수 있어요';
  try {
    await fsdb.collection('asks').add({...data, 'uid': u.uid, 'at': fs.FieldValue.serverTimestamp()});
    loadMyAsks();
    return null;
  } catch (_) {
    return '보내지 못했어요. 잠시 뒤 다시 보내 주세요';
  }
}

Future<String?> deleteMyAsk(Ask a) async {
  if (reviews.demo) {
    _demoAsks.removeWhere((x) => x.id == a.id);
    myAsks.value = [..._demoAsks];
    return null;
  }
  try {
    await fsdb.doc('asks/${a.id}').delete();
    myAsks.value = [...?myAsks.value]..removeWhere((x) => x.id == a.id);
    return null;
  } catch (_) {
    return '지우지 못했어요';
  }
}

// 로그인부터 확인하고 글쓰기·내 문의로
Future<bool> _askLogin(BuildContext context) async {
  if (reviews.demo) return true;
  if (!await fbReady()) {
    if (context.mounted) admToast(context, '지금은 보낼 수 없어요. 잠시 뒤 다시 해 주세요');
    return false;
  }
  if (!context.mounted) return false;
  if (fbUser == null) {
    await openLogin(context);
    if (fbUser == null || !context.mounted) return false;
  }
  return true;
}

Future<void> openAsk(BuildContext context, String kind) async {
  if (!await _askLogin(context) || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AskPage(kind: kind)));
}

Future<void> openMyAsks(BuildContext context) async {
  if (!await _askLogin(context) || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyAsksPage()));
}

// 「내 문의」 줄에 붙는 작은 설명: 답변이 온 글 수
String myAskSub(List<Ask>? l) {
  if (l == null || l.isEmpty) return '보낸 글과 답변을 모아 봐요';
  final d = l.where((a) => a.done).length;
  return d == 0 ? '${l.length}건 · 답변을 기다리는 중' : '${l.length}건 · 답변 $d건';
}

// ---- 글쓰기 (게시판 글쓰기처럼: 종류 → 제목 → 내용 → 연락처) ----
class AskPage extends StatefulWidget {
  final String kind;
  const AskPage({super.key, this.kind = 'ask'});
  @override
  State<AskPage> createState() => _AskPageState();
}

class _AskPageState extends State<AskPage> {
  late String kind = kAskWrite.contains(widget.kind) ? widget.kind : 'ask';
  final title = TextEditingController(), body = TextEditingController(), contact = TextEditingController();
  String nick = '';
  String note = '';
  bool busy = false, sent = false;

  static const _guide = {
    'idea': '불편했던 점이나 있었으면 하는 기능을 적어 주세요.',
    'biz': '가게 등록·광고·협업 제안을 적어 주세요. 확인하고 연락드려요.',
    'ask': '궁금한 점을 적어 주세요. 답변은 「내 문의」에서 볼 수 있어요.',
  };
  static const _titleHint = {'idea': '예) 지도에서 가게 이름이 겹쳐 보여요', 'biz': '예) ○○식당 광고 문의', 'ask': '예) 후기 사진이 올라가지 않아요'};
  static const _pageTitle = {'idea': ('개선 ', '제안하기'), 'biz': ('제휴·광고 ', '문의'), 'ask': ('', '문의하기')};

  @override
  void initState() {
    super.initState();
    for (final c in [title, body]) {
      c.addListener(() => setState(() => note = ''));
    }
    (reviews.demo ? Future.value('바삭한 콕플러') : reviews.nick()).then((n) {
      if (mounted) setState(() => nick = n);
    });
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    contact.dispose();
    super.dispose();
  }

  bool get ready => title.text.trim().isNotEmpty && body.text.trim().isNotEmpty && !busy;

  Future<void> send() async {
    if (!ready) return;
    FocusScope.of(context).unfocus();
    setState(() => busy = true);
    final e = await sendAsk(kind: kind, title: title.text, text: body.text, contact: contact.text);
    if (!mounted) return;
    setState(() {
      busy = false;
      if (e == null) {
        sent = true;
      } else {
        note = e;
      }
    });
  }

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

  Widget label(String t, {String? sub}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
          if (sub != null) TextSpan(text: '  $sub', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w400, color: kSub)),
        ])),
      );

  Widget _done() => Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 80),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Center(child: StickerFace('kind', size: 84)),
        const SizedBox(height: 18),
        Center(child: mixTitle(const {'idea': '제안을 ', 'biz': '제휴 문의를 '}[kind] ?? '문의를 ', '접수했어요', size: 20)),
        const SizedBox(height: 8),
        const Text('확인하고 답변을 남길게요.\n답변은 내 콕 › 「내 문의」에서 볼 수 있어요.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: kSub, height: 1.5)),
        const SizedBox(height: 26),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                    foregroundColor: kInk, side: const BorderSide(color: kPillLine), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('닫기', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 48,
              child: TextButton(
                onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MyAsksPage())),
                style: TextButton.styleFrom(backgroundColor: kInk, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('내 문의 보기', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ]),
      ]),
      ),
    );

  Widget _form() => Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 6, 20, 24), children: [
            label('종류'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in kAskWrite) _SegChip(label: kAskKinds[k]!, on: kind == k, onTap: () => setState(() => kind = k)),
            ]),
            const SizedBox(height: 8),
            Text(_guide[kind] ?? '', style: const TextStyle(fontSize: 12, color: kSub, height: 1.4)),
            const SizedBox(height: 22),
            label('제목'),
            TextField(controller: title, maxLength: 40, textInputAction: TextInputAction.next, style: const TextStyle(fontSize: 14.5, color: kInk), decoration: deco(_titleHint[kind] ?? '')),
            const SizedBox(height: 18),
            label('내용', sub: '${body.text.characters.length} / 1000'),
            TextField(
              controller: body,
              maxLength: 1000,
              minLines: 7,
              maxLines: 14,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontSize: 14.5, color: kInk, height: 1.5),
              decoration: deco(kind == 'biz' ? '회사·가게 이름과 제안 내용을 적어 주세요' : '자세히 적어 주실수록 빨리 도와드릴 수 있어요'),
            ),
            const SizedBox(height: 18),
            label('연락처', sub: kind == 'biz' ? '선택 · 담당자 전화나 메일' : '선택 · 전화로 듣고 싶으시면'),
            TextField(controller: contact, maxLength: 60, keyboardType: TextInputType.emailAddress, style: const TextStyle(fontSize: 14.5, color: kInk), decoration: deco('010-0000-0000 또는 메일 주소')),
            const SizedBox(height: 10),
            const Text('보낸 글은 쓰신 분과 콕플 관리자만 볼 수 있어요.', style: TextStyle(fontSize: 11.5, color: kSub)),
          ]),
        ),
        // 아래 고정: 이름 + 보내기
        Container(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 12 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kHair))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (note.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(note, style: const TextStyle(fontSize: 12.5, color: kPointText))),
            Row(children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: nick, style: const TextStyle(fontWeight: FontWeight.w700, color: kInk)),
                    TextSpan(text: nick.isEmpty ? '' : ' 이름으로 접수돼요'),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: kSub),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Semantics(
              button: true,
              enabled: ready,
              label: '보내기',
              onTap: ready ? send : null,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: ready ? send : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: ready ? kAccent : const Color(0xFFEDEDF0), borderRadius: BorderRadius.circular(14)),
                  child: busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(ready ? '보내기' : '제목과 내용을 적어 주세요',
                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: ready ? Colors.white : const Color(0xFF9A9EA8))),
                ),
              ),
            ),
          ]),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final t = _pageTitle[kind] ?? ('', '문의하기');
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: narrow(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 12, 4),
            child: Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), tooltip: '뒤로', icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: kInk)),
              Expanded(child: sent ? const SizedBox() : mixTitle(t.$1, t.$2, size: 20)),
            ]),
          ),
          Expanded(child: sent ? _done() : _form()),
        ])),
      ),
    );
  }
}

// ---- 내 문의 (게시판 목록: 누르면 펼쳐서 내용과 답변) ----
class MyAsksPage extends StatefulWidget {
  const MyAsksPage({super.key});
  @override
  State<MyAsksPage> createState() => _MyAsksPageState();
}

class _MyAsksPageState extends State<MyAsksPage> {
  String open = '';

  @override
  void initState() {
    super.initState();
    loadMyAsks().then((l) {
      if (mounted && open.isEmpty && l.isNotEmpty) setState(() => open = l.first.id); // 맨 위 글은 펼쳐 둠
    });
  }

  Future<void> remove(Ask a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이 글을 지울까요?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: const Text('지운 글과 답변은 되살릴 수 없어요.', style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('그대로 두기')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('지우기', style: TextStyle(color: kPointText, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
    final e = await deleteMyAsk(a);
    if (mounted) admToast(context, e ?? '지웠어요');
  }

  Widget tag(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: const Color(0xFFF2F3F5), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF5A5F69))),
      );

  Widget row(Ask a) {
    final on = open == a.id;
    return InkWell(
      onTap: () => setState(() => open = on ? '' : a.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            tag(a.kindName),
            const SizedBox(width: 8),
            Expanded(child: Text(on ? keepWords(a.title) : a.title, maxLines: on ? 3 : 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: on ? FontWeight.w700 : FontWeight.w600, color: kInk, height: 1.35))),
            Icon(on ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 22, color: kSub),
          ]),
          const SizedBox(height: 5),
          Text.rich(TextSpan(children: [
            TextSpan(text: askDate(a.at)),
            const TextSpan(text: '  ·  '),
            TextSpan(
                text: a.done ? '답변 완료' : '확인 중',
                style: TextStyle(fontWeight: a.done ? FontWeight.w700 : FontWeight.w500, color: a.done ? kPointText : kSub)),
          ]), style: const TextStyle(fontSize: 11.5, color: kSub)),
          if (on) ...[
            const SizedBox(height: 12),
            if (a.kind == 'fix' && a.pname.isNotEmpty) ...[
              Text('${a.pname}${a.items.isEmpty ? '' : ' · ${a.items.join(', ')}'}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kInk)),
              const SizedBox(height: 6),
            ],
            Text(keepWords(a.text), style: const TextStyle(fontSize: 13.5, color: Color(0xFF3A3F48), height: 1.55)),
            if (a.contact.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('연락처 ${a.contact}', style: const TextStyle(fontSize: 12, color: kSub)),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
              decoration: BoxDecoration(color: a.done ? const Color(0xFFF7F7F9) : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kHair)),
              child: a.done
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text.rich(TextSpan(children: [
                        const TextSpan(text: '콕플 답변', style: TextStyle(fontWeight: FontWeight.w700, color: kInk)),
                        if (a.aat != null) TextSpan(text: '   ${askDate(a.aat!)}', style: const TextStyle(fontSize: 11, color: kSub)),
                      ]), style: const TextStyle(fontSize: 12.5)),
                      const SizedBox(height: 6),
                      Text(keepWords(a.ans), style: const TextStyle(fontSize: 13.5, color: kInk, height: 1.55)),
                    ])
                  : const Text('확인하고 있어요. 답변이 달리면 여기에 보여요.', style: TextStyle(fontSize: 12.5, color: kSub)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => remove(a),
                style: TextButton.styleFrom(foregroundColor: kSub, padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 34)),
                child: const Text('글 지우기', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => subPage(
        context,
        '내 문의',
        ValueListenableBuilder<List<Ask>?>(
          valueListenable: myAsks,
          builder: (_, l, __) {
            if (l == null) return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)));
            if (l.isEmpty) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('아직 보낸 글이 없어요.', style: TextStyle(fontSize: 13.5, color: kSub)),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AskPage())),
                    style: TextButton.styleFrom(backgroundColor: kInk, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 22), minimumSize: const Size(0, 42), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text('글쓰기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ]),
              );
            }
            return RefreshIndicator(
              onRefresh: loadMyAsks,
              color: kAccent,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                itemCount: l.length,
                separatorBuilder: (_, __) => const Divider(height: 1, thickness: 1, color: kHair),
                itemBuilder: (_, i) => row(l[i]),
              ),
            );
          },
        ),
        action: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AskPage())),
          style: TextButton.styleFrom(foregroundColor: kInk, padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(0, 36)),
          child: const Text('글쓰기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      );
}

// ---- 관리자 「문의함」: 한 줄에 하나씩 촘촘하게, 누르면 펼쳐서 답변 ----
class AskAdminTab extends StatefulWidget {
  const AskAdminTab({super.key});
  @override
  State<AskAdminTab> createState() => _AskAdminTabState();
}

class _AskAdminTabState extends State<AskAdminTab> {
  int seg = 0; // 0 새 문의 · 1 답변 완료 · 2 전체
  bool loading = true;
  String err = '', open = '';
  List<Ask> all = [];
  final ans = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    ans.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      err = '';
    });
    try {
      if (reviews.demo) {
        all = [
          ..._askDemoSeed(),
          Ask('d3', {
            'uid': 'u3', 'nick': '쫄깃한 콕플러', 'kind': 'fix', 'title': '군봉묵은지김치찜 정보 수정', 'text': '일요일은 쉬어요',
            'pid': '13635514', 'pname': '군봉묵은지김치찜', 'items': ['영업시간'], 'st': 'new', 'at': DateTime.now().subtract(const Duration(minutes: 40)),
          }),
        ]..sort((a, b) => b.at.compareTo(a.at));
      } else {
        final q = await fsdb.collection('asks').orderBy('at', descending: true).limit(300).get();
        all = [for (final d in q.docs) Ask(d.id, d.data())];
      }
    } catch (e) {
      err = '불러오지 못했어요 ($e)';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> save(Ask a) async {
    final t = ans.text.trim();
    if (reviews.demo) {
      admToast(context, '화면 점검용이라 저장하지 않아요');
      return;
    }
    try {
      await fsdb.doc('asks/${a.id}').update({'ans': t, 'st': t.isEmpty ? 'new' : 'done', 'aat': fs.FieldValue.serverTimestamp()});
      if (!mounted) return;
      admToast(context, t.isEmpty ? '답변을 비웠어요' : '답변을 남겼어요');
      open = '';
      load();
    } catch (e) {
      if (mounted) admToast(context, '저장하지 못했어요 ($e)');
    }
  }

  Future<void> remove(Ask a) async {
    if (reviews.demo) return;
    try {
      await fsdb.doc('asks/${a.id}').delete();
      if (!mounted) return;
      admToast(context, '지웠어요');
      open = '';
      load();
    } catch (e) {
      if (mounted) admToast(context, '지우지 못했어요 ($e)');
    }
  }

  String short(DateTime t) {
    final k = t.toUtc().add(const Duration(hours: 9));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(k.month)}.${two(k.day)} ${two(k.hour)}:${two(k.minute)}';
  }

  Widget line(Ask a) {
    final on = open == a.id;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: () => setState(() {
          open = on ? '' : a.id;
          ans.text = a.ans;
        }),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: on ? const Color(0xFFF7F7F9) : null,
          child: Row(children: [
            SizedBox(width: 58, child: Text(a.kindName, maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF5A5F69)))),
            Expanded(child: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: a.done ? FontWeight.w400 : FontWeight.w700, color: kInk))),
            const SizedBox(width: 8),
            Text(short(a.at), style: const TextStyle(fontSize: 11.5, color: kSub, fontFeatures: [ui.FontFeature.tabularFigures()])),
            const SizedBox(width: 8),
            SizedBox(width: 30, child: Text(a.done ? '완료' : '새 글', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: a.done ? kSub : kPointText))),
          ]),
        ),
      ),
      if (on)
        Container(
          width: double.infinity,
          color: const Color(0xFFF7F7F9),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(a.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
            const SizedBox(height: 4),
            Text('${a.nick} · ${askDate(a.at)}${a.contact.isEmpty ? '' : ' · 연락처 ${a.contact}'}', style: const TextStyle(fontSize: 12, color: kSub)),
            if (a.kind == 'fix' && a.pname.isNotEmpty) ...[
              const SizedBox(height: 6),
              SelectableText('가게: ${a.pname} (${a.pid})${a.items.isEmpty ? '' : ' · ${a.items.join(', ')}'}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kInk)),
            ],
            const SizedBox(height: 8),
            SelectableText(a.text, style: const TextStyle(fontSize: 13.5, color: kInk, height: 1.5)),
            const SizedBox(height: 10),
            TextField(controller: ans, minLines: 3, maxLines: 8, decoration: admDeco('답변 (쓴 분의 「내 문의」에 보여요)')),
            const SizedBox(height: 8),
            Row(children: [
              admBtn(a.done ? '답변 고치기' : '답변 남기기', () => save(a), strong: true),
              const SizedBox(width: 8),
              admBtn('지우기', () => remove(a), danger: true),
            ]),
          ]),
        ),
      const Divider(height: 1, thickness: 1, color: kHair),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)));
    if (err.isNotEmpty) return Center(child: TextButton(onPressed: load, child: Text('$err · 다시 받기')));
    final fresh = all.where((a) => !a.done).toList(), done = all.where((a) => a.done).toList();
    final list = switch (seg) { 0 => fresh, 1 => done, _ => all };
    final segs = ['새 문의 ${fresh.length}', '답변 완료 ${done.length}', '전체 ${all.length}'];
    return RefreshIndicator(
      onRefresh: load,
      color: kAccent,
      child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(children: [
            for (var i = 0; i < segs.length; i++)
              GestureDetector(
                onTap: () => setState(() {
                  seg = i;
                  open = '';
                }),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  child: Text(segs[i], style: TextStyle(fontSize: 12.5, fontWeight: seg == i ? FontWeight.w700 : FontWeight.w500, color: seg == i ? Colors.white : kInk)),
                ),
              ),
            const Spacer(),
            IconButton(onPressed: load, tooltip: '새로 받기', icon: const Icon(Icons.refresh_rounded, size: 20, color: kSub)),
          ]),
        ),
        const Divider(height: 1, thickness: 1, color: kHair),
        for (final a in list) line(a),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text(seg == 0 ? '새 문의가 없어요.' : '글이 없어요.', style: const TextStyle(fontSize: 13, color: kSub))),
          ),
      ]),
    );
  }
}

// ---------------- 오류·개선 의견 보내기 (우동콕과 같은 방식, 대표님 지시 11-28) ----------------
// 「오류 신고 / 개선 제안」 둘 중 고르고 글만 적어 보낸다. 문의함(asks)으로 접수 — 답변은 「내 문의」에서.
// 저장 규칙이 받는 종류가 정해져 있어 둘 다 「개선 제안」 칸으로 넣고 제목 머리말로 구분한다.
Future<void> openFeedback(BuildContext context) async {
  if (!reviews.demo && fbUser == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('로그인하면 의견을 보내고 답변도 받을 수 있어요')));
    await openLogin(context);
    if (fbUser == null || !context.mounted) return;
  }
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    barrierColor: Colors.black.withValues(alpha: 0.08),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _FeedbackSheet(),
  );
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet();
  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  String kind = 'bug';
  final text = TextEditingController();
  late final contact = TextEditingController(text: fbUser?.email ?? '');
  bool busy = false;
  String? error;

  @override
  void dispose() {
    text.dispose();
    contact.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = text.text.trim();
    if (t.length < 5) {
      setState(() => error = '내용을 조금 더 적어 주세요 (5자 넘게)');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final head = kind == 'bug' ? '[오류 신고] ' : '[개선 제안] ';
    final first = t.split('\n').first.trim();
    final e = await sendAsk(kind: 'idea', title: head + _cut(first, 40 - head.length), text: t, contact: contact.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (e != null) {
      setState(() => error = e);
      return;
    }
    final nav = Navigator.of(context);
    final bug = kind == 'bug';
    nav.pop();
    await showDialog(
      context: nav.context,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('잘 받았습니다', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
        content: Text(bug ? '알려 주셔서 고맙습니다.\n확인하고 빠르게 고치겠습니다.' : '좋은 의견 고맙습니다.\n적극 반영해 더 좋은 콕플을 만들겠습니다.',
            style: const TextStyle(fontSize: 13.5, height: 1.5, color: kInk)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인', style: TextStyle(color: kAccent, fontWeight: FontWeight.w800)))],
      ),
    );
  }

  Widget _kind(String id, String label, IconData ic) {
    final on = kind == id;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => kind = id),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: on ? kAccentTint : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? kAccent : kPillLine, width: 1),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(ic, size: 18, color: on ? kAccent : kSub),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 14, fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: on ? kAccent : kInk)),
          ]),
        ),
      ),
    );
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFFA5A9B2), height: 1.4),
        isDense: true,
        counterText: '',
        filled: true,
        fillColor: const Color(0xFFF5F5F7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kAccent.withValues(alpha: 0.5), width: 1)),
      );

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(22, 20, 22, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          mixTitle('오류·개선 ', '의견 보내기', size: 19),
          const SizedBox(height: 5),
          const Text('보내 주신 의견은 개발자가 직접 읽고 적극 반영해 드리겠습니다.', style: TextStyle(fontSize: 13, color: kSub)),
          const SizedBox(height: 16),
          Row(children: [
            _kind('bug', '오류 신고', Icons.error_outline_rounded),
            const SizedBox(width: 10),
            _kind('idea', '개선 제안', Icons.lightbulb_outline_rounded),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: text,
            minLines: 5,
            maxLines: 8,
            maxLength: 1000,
            style: const TextStyle(fontSize: 14, color: kInk, height: 1.45),
            decoration: _deco(kind == 'bug' ? '어느 화면에서 무엇이 안 되는지 적어 주세요\n예) 지도에서 가게를 누르면 창이 안 열려요' : '이런 기능이 있으면 좋겠어요, 여기가 불편해요 등\n편하게 적어 주세요'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: contact,
            maxLength: 60,
            style: const TextStyle(fontSize: 14, color: kInk),
            decoration: _deco('답을 받을 이메일·연락처 (적지 않아도 돼요)'),
          ),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(fontSize: 13, color: kAccent, fontWeight: FontWeight.w600))),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: TextButton(
              onPressed: busy ? null : _send,
              style: TextButton.styleFrom(backgroundColor: kAccent, foregroundColor: Colors.white, disabledForegroundColor: Colors.white70, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text(busy ? '보내는 중…' : '보내기', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      );
}

// 내 콕 아래 강조 칸: 오류 신고 · 개선 제안
class FeedbackBanner extends StatelessWidget {
  const FeedbackBanner({super.key});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => openFeedback(context),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF6A3D), kAccent]),
              boxShadow: [BoxShadow(color: kAccent.withValues(alpha: 0.2), blurRadius: 16)],
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '오류 신고 ', style: TextStyle(fontWeight: FontWeight.w800)),
                      TextSpan(text: '· 개선 제안', style: TextStyle(fontWeight: FontWeight.w300)),
                    ]),
                    style: TextStyle(fontSize: 17, color: Colors.white, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 4),
                  Text('보내 주신 의견, 적극 반영해 드리겠습니다', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.92), letterSpacing: -0.3)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: const Text('의견 보내기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kAccent)),
              ),
            ]),
          ),
        ),
      );
}
