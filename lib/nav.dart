part of 'main.dart';

// ---------------- 길안내: 고른 앱(카카오맵·네이버·티맵)으로 이 가게를 목적지로 바로 안내 ----------------
// 「네이버 지도」「카카오 지도」처럼 「지도」만 붙은 이름은 쓰지 않는다 (콕플 지도와 헷갈림).
// 가게 화면·내 콕·내 주변 어디서든 같은 단추(startNav)를 쓴다.

class NavApp {
  final String id, name, pkg, label;
  const NavApp(this.id, this.name, this.pkg, this.label);
}

const kNavApps = [
  NavApp('kakao', '카카오맵', 'net.daum.android.map', '카카오맵으로 길안내'),
  NavApp('naver', '네이버', 'com.nhn.android.nmap', '네이버로 길안내'),
  NavApp('tmap', '티맵', 'com.skt.tmap.ku', '티맵으로 길안내'),
];

// 바로 열 앱 ('' = 매번 물어보기) — 설정에서 바꿈
final navPref = ValueNotifier<String>('');

Future<void> loadNavPref() async {
  try {
    navPref.value = (await SharedPreferences.getInstance()).getString('navApp') ?? '';
  } catch (_) {}
}

Future<void> setNavPref(String id) async {
  navPref.value = id;
  try {
    await (await SharedPreferences.getInstance()).setString('navApp', id);
  } catch (_) {}
}

String navPrefName() => kNavApps.where((a) => a.id == navPref.value).firstOrNull?.name ?? '매번 물어보기';

// 휴대폰에 깔린 앱의 아이콘 (안드로이드에서 그 앱의 실제 아이콘을 받아 씀, 한 번 받아 둠)
Map<String, Uint8List>? _navIcons;
Future<Map<String, Uint8List>> navIcons() async {
  final have = _navIcons;
  if (have != null) return have;
  if (kIsWeb) return _navIcons = {};
  try {
    final m = await const MethodChannel('kokple/apps').invokeMethod<Map>('icons', {'pkgs': [for (final a in kNavApps) a.pkg]});
    return _navIcons = {
      for (final e in (m ?? const {}).entries)
        if (e.value is Uint8List) '${e.key}': e.value as Uint8List
    };
  } catch (_) {
    return _navIcons = {};
  }
}

// 길안내 시작: 바로 열 앱을 정해 두었으면 그 앱으로, 아니면 고르는 창
Future<void> startNav(BuildContext context, {required String name, required double lat, required double lng}) async {
  final a = kNavApps.where((x) => x.id == navPref.value).firstOrNull;
  if (a != null) return launchNav(context, a, name, lat, lng);
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.08),
    builder: (_) => NavSheet(name: name, lat: lat, lng: lng),
  );
}

Future<void> launchNav(BuildContext context, NavApp a, String name, double lat, double lng) async {
  final n = Uri.encodeComponent(name);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (kIsWeb) {
    // 미리보기(웹): 앱 대신 웹으로
    openUrl(switch (a.id) {
      'kakao' => 'https://map.kakao.com/link/to/$n,$lat,$lng',
      'naver' => 'https://map.naver.com/p/search/$n',
      _ => 'https://play.google.com/store/apps/details?id=${a.pkg}',
    });
    return;
  }
  // 출발지를 비우면 내 위치에서 출발 (세 앱 모두)
  final app = switch (a.id) {
    'kakao' => 'kakaomap://route?ep=$lat,$lng&by=CAR',
    'naver' => 'nmap://route/car?dlat=$lat&dlng=$lng&dname=$n&appname=kr.designfeel.df_app_lab',
    _ => 'tmap://route?goalname=$n&goalx=$lng&goaly=$lat&rGoName=$n&rGoX=$lng&rGoY=$lat',
  };
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(app), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (ok) return;
  // 앱이 없으면 설치 화면 (안 열리면 웹 스토어)
  try {
    ok = await launchUrl(Uri.parse('market://details?id=${a.pkg}'), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok) openUrl('https://play.google.com/store/apps/details?id=${a.pkg}');
  messenger?.showSnackBar(SnackBar(content: Text('${a.name} 앱이 없어 설치 화면을 열었어요'), duration: const Duration(seconds: 3)));
}

// 앱 아이콘 자리 (아이콘을 못 받으면 연한 칸 + 길안내 화살표)
Widget navAppIcon(Uint8List? icon, {double size = 44}) => ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.26),
      child: SizedBox(
        width: size,
        height: size,
        child: icon != null
            ? Image.memory(icon, fit: BoxFit.cover, gaplessPlayback: true)
            : Container(
                decoration: BoxDecoration(color: const Color(0xFFF4F5F7), border: Border.all(color: kLine, width: 1), borderRadius: BorderRadius.circular(size * 0.26)),
                alignment: Alignment.center,
                child: LineIcon('nav', size: size * 0.5, color: kSub),
              ),
      ),
    );

class NavSheet extends StatefulWidget {
  final String name;
  final double lat, lng;
  final bool pickOnly; // 설정에서 바로 열 앱만 고를 때
  const NavSheet({super.key, required this.name, required this.lat, required this.lng, this.pickOnly = false});
  @override
  State<NavSheet> createState() => _NavSheetState();
}

class _NavSheetState extends State<NavSheet> {
  bool remember = false;
  Map<String, Uint8List> icons = const {};
  bool loaded = kIsWeb;

  @override
  void initState() {
    super.initState();
    navIcons().then((m) {
      if (mounted) {
        setState(() {
          icons = m;
          loaded = true;
        });
      }
    });
  }

  Future<void> go(NavApp a) async {
    if (widget.pickOnly) {
      await setNavPref(a.id);
      if (mounted) Navigator.pop(context);
      return;
    }
    if (remember) await setNavPref(a.id);
    if (!mounted) return;
    final ctx = Navigator.of(context).context;
    Navigator.pop(context);
    if (ctx.mounted) await launchNav(ctx, a, widget.name, widget.lat, widget.lng);
  }

  Widget appRow(NavApp a, {bool last = false}) {
    final icon = icons[a.pkg];
    final missing = loaded && !kIsWeb && icon == null;
    final on = widget.pickOnly && navPref.value == a.id;
    return Semantics(
      button: true,
      label: a.label,
      onTap: () => go(a),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => go(a),
        child: Container(
          height: 66,
          decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: kHair, width: 1))),
          child: Row(children: [
            navAppIcon(icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.pickOnly ? a.name : a.label, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -0.3)),
                if (missing) ...[
                  const SizedBox(height: 2),
                  const Text('휴대폰에 없으면 설치 화면으로 안내해요', style: TextStyle(fontSize: 11.5, color: kSub)),
                ],
              ]),
            ),
            if (widget.pickOnly)
              Icon(on ? Icons.check_circle_rounded : Icons.circle_outlined, size: 22, color: on ? kAccent : kLine)
            else
              const Icon(Icons.chevron_right_rounded, size: 22, color: kSub),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 20)],
      ),
      padding: EdgeInsets.fromLTRB(22, 10, 22, 14 + mq.padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 18),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: '어떤 앱으로 ', style: TextStyle(fontWeight: FontWeight.w300)),
            TextSpan(text: widget.pickOnly ? '바로 열까요?' : '길안내 할까요?', style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          style: const TextStyle(fontSize: 20, color: kInk, letterSpacing: -0.4, height: 1.2),
        ),
        const SizedBox(height: 5),
        Text(widget.pickOnly ? '가게 화면에서 「길안내」를 누르면 고른 앱이 바로 열려요' : '도착지  ${widget.name}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: kSub)),
        const SizedBox(height: 10),
        for (var i = 0; i < kNavApps.length; i++) appRow(kNavApps[i], last: i == kNavApps.length - 1 && !widget.pickOnly),
        if (widget.pickOnly)
          InkWell(
            onTap: () async {
              await setNavPref('');
              if (context.mounted) Navigator.pop(context);
            },
            child: SizedBox(
              height: 56,
              child: Row(children: [
                const SizedBox(width: 58),
                const Expanded(child: Text('매번 물어보기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kInk))),
                Icon(navPref.value.isEmpty ? Icons.check_circle_rounded : Icons.circle_outlined, size: 22, color: navPref.value.isEmpty ? kAccent : kLine),
              ]),
            ),
          )
        else ...[
          const SizedBox(height: 8),
          // 다음부터 이 앱으로 바로 열기 (설정에서 바꿀 수 있음)
          Semantics(
            checked: remember,
            label: '다음부터 이 앱으로 바로 열기',
            onTap: () => setState(() => remember = !remember),
            excludeSemantics: true,
            child: InkWell(
              onTap: () => setState(() => remember = !remember),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 19,
                    height: 19,
                    decoration: BoxDecoration(
                      color: remember ? kAccent : Colors.white,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: remember ? kAccent : kPillLine, width: 1),
                    ),
                    child: remember ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                  ),
                  const SizedBox(width: 8),
                  const Text('다음부터 이 앱으로 바로 열기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kInk)),
                  const Spacer(),
                  const Text('설정에서 바꿀 수 있어요', style: TextStyle(fontSize: 11.5, color: kSub)),
                ]),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

// 설정 → 길안내 앱 바꾸기
Future<void> openNavSetting(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (_) => const NavSheet(name: '', lat: 0, lng: 0, pickOnly: true),
    );

// 목록 줄(내 콕·내 주변)에 붙는 작은 길안내 단추
class NavPill extends StatelessWidget {
  final VoidCallback onTap;
  const NavPill({super.key, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '길안내',
        onTap: onTap,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Container(
              height: 30,
              padding: const EdgeInsets.only(left: 9, right: 11),
              decoration: BoxDecoration(color: kAccentTint, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFFFC9B8), width: 1)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                LineIcon('nav', size: 15, color: kPointText),
                SizedBox(width: 4),
                Text('길안내', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kPointText, height: 1.1)),
              ]),
            ),
          ),
        ),
      );
}

// 가게 화면의 큰 단추 줄: 길안내(가장 크게) · 전화 · 메뉴 · 블로그/홈페이지
class PlaceActions extends StatelessWidget {
  final Place place;
  const PlaceActions({super.key, required this.place});

  Widget small(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: Semantics(
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
                height: 52,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: kLine, width: 1)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 19, color: kInk),
                  const SizedBox(height: 3),
                  Text(label, maxLines: 1, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kInk, height: 1.1)),
                ]),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = place;
    final naver = 'https://map.naver.com/p/search/${Uri.encodeComponent(p.name)}';
    void nav() => startNav(context, name: p.name, lat: p.lat, lng: p.lng);
    return Row(children: [
      Expanded(
        flex: 2,
        child: Semantics(
          button: true,
          label: '길안내',
          onTap: nav,
          excludeSemantics: true,
          child: Material(
            color: kAccent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: nav,
              borderRadius: BorderRadius.circular(12),
              child: const SizedBox(
                height: 52,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  LineIcon('nav', size: 21, color: Colors.white, stroke: 1.9),
                  SizedBox(width: 7),
                  Text('길안내', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3)),
                ]),
              ),
            ),
          ),
        ),
      ),
      if (p.tel.isNotEmpty) ...[const SizedBox(width: 8), small(Icons.call_outlined, '전화', () => openUrl('tel:${p.tel}'))],
      const SizedBox(width: 8),
      small(Icons.photo_library_outlined, '메뉴', () => openUrl(p.kakao.isNotEmpty ? p.kakao : naver)),
      if (p.home.isNotEmpty) ...[const SizedBox(width: 8), small(Icons.public, p.home.contains('blog') ? '블로그' : '홈페이지', () => openUrl(p.home))],
    ]);
  }
}
