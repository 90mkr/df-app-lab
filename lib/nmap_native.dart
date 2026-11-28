// 휴대폰 앱: 네이버 지도 (flutter_naver_map) — 우동콕과 같은 네이버 클라우드 계정
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:latlong2/latlong.dart';

import 'nmap_common.dart';
export 'nmap_common.dart';

// 네이버 확대값은 우리가 쓰던 값(256px 타일 기준)보다 1 작다 (네이버는 같은 숫자에서 지도가 두 배 넓이)
const _dz = 1.0;

// 네이버 지도를 쓸 수 있는지 — 인증이 안 되면(콘솔에 앱 이름 미등록 등) 기존 지도로 돌아간다
final ValueNotifier<bool> naverMapOk = ValueNotifier(false);
bool get naverMapOn => naverMapOk.value;

Future<void> initNaverMap(String clientId) async {
  if (clientId.isEmpty) return;
  try {
    await FlutterNaverMap().init(
        clientId: clientId,
        onAuthFailed: (e) {
          debugPrint('네이버 지도 인증 실패: $e');
          naverMapOk.value = false;
        });
    naverMapOk.value = true;
  } catch (e) {
    debugPrint('네이버 지도 준비 실패: $e');
  }
}

NLatLng _n(LatLng p) => NLatLng(p.latitude, p.longitude);
LatLng _l(NLatLng p) => LatLng(p.latitude, p.longitude);

Widget naverKok({Key? key, required LatLng center, required double zoom, List<KMark> marks = const [], List<KLine> lines = const [], VoidCallback? onMapTap, KCam? onCam, KMapCtl? ctl, TextStyle? textStyle}) =>
    _NKok(key: key, center: center, zoom: zoom, marks: marks, lines: lines, onMapTap: onMapTap, onCam: onCam, ctl: ctl, textStyle: textStyle);

class _NKok extends StatefulWidget {
  final LatLng center;
  final double zoom;
  final List<KMark> marks;
  final List<KLine> lines;
  final VoidCallback? onMapTap;
  final KCam? onCam;
  final KMapCtl? ctl;
  final TextStyle? textStyle;
  const _NKok({super.key, required this.center, required this.zoom, required this.marks, required this.lines, this.onMapTap, this.onCam, this.ctl, this.textStyle});
  @override
  State<_NKok> createState() => _NKokState();
}

class _NKokState extends State<_NKok> {
  NaverMapController? c;
  bool gesture = false;
  final Map<String, NOverlayImage> _img = {}; // 모양(key)마다 한 번 만든 그림
  final Set<String> _okUrl = {}; // 받아 둔 인터넷 사진
  final Map<String, (KMark, NMarker)> _on = {}; // 지금 지도에 올라가 있는 표시
  Map<String, KMark> _cur = {}; // 가장 최근 표시 (누를 때 이걸로 찾는다)
  int _gen = 0;
  String _lineSig = '';
  bool _again = false, _busy = false;

  @override
  void didUpdateWidget(covariant _NKok old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    widget.ctl?.onMove = null;
    super.dispose();
  }

  Future<bool> _pre(String url) async {
    if (_okUrl.contains(url)) return true;
    var ok = true;
    try {
      await precacheImage(NetworkImage(url), context, onError: (_, __) => ok = false).timeout(const Duration(milliseconds: 2500), onTimeout: () => ok = false);
    } catch (_) {
      ok = false;
    }
    if (ok) _okUrl.add(url);
    return ok;
  }

  Future<NOverlayImage?> _image(KMark m) async {
    final have = _img[m.key];
    if (have != null) return have;
    var whole = true;
    for (final u in m.images) {
      if (!await _pre(u)) whole = false;
      if (!mounted) return null;
    }
    final st = widget.textStyle;
    final child = st == null ? m.child : DefaultTextStyle(style: st, child: m.child);
    final img = await NOverlayImage.fromWidget(widget: SizedBox(width: m.size.width, height: m.size.height, child: child), size: m.size, context: context);
    // 사진을 못 받은 채 그린 그림은 남겨 두지 않는다 (다음에 다시 그림)
    if (whole) {
      if (_img.length > 900) _img.clear();
      _img[m.key] = img;
    }
    return img;
  }

  Future<void> _put(NaverMapController cc, KMark m, int gen) async {
    if (_on.containsKey(m.id)) return;
    final img = await _image(m);
    if (img == null || !mounted || gen != _gen || _on.containsKey(m.id)) return;
    final mk = NMarker(
      id: m.id,
      position: _n(m.pos),
      icon: img,
      size: m.size,
      anchor: NPoint(m.anchor.dx, m.anchor.dy),
      isHideCollidedSymbols: true,
    );
    mk.setGlobalZIndex(200000 + m.z);
    mk.setOnTapListener((_) => _cur[m.id]?.onTap?.call());
    try {
      await cc.addOverlay(mk);
      _on[m.id] = (m, mk);
    } catch (_) {}
  }

  // 바뀐 것만 지우고 새로 올린다 (통째로 지웠다 올리면 깜빡임)
  Future<void> _sync() async {
    if (_busy) {
      _again = true;
      _gen++;
      return;
    }
    final cc = c;
    if (cc == null || !mounted) return;
    _busy = true;
    try {
      final gen = ++_gen;
      final marks = widget.marks;
      _cur = {for (final m in marks) m.id: m};
      // 길(코스 선)
      final ls = [for (final l in widget.lines) '${l.points.length}:${l.points.isEmpty ? '' : l.points.first}:${l.points.isEmpty ? '' : l.points.last}'].join('|');
      if (ls != _lineSig) {
        _lineSig = ls;
        try {
          await cc.clearOverlays(type: NOverlayType.polylineOverlay);
          var i = 0;
          for (final l in widget.lines) {
            if (l.points.length < 2) continue;
            await cc.addOverlay(NPolylineOverlay(id: 'line${i++}', coords: [for (final p in l.points) _n(p)], color: l.color, width: l.width, pattern: l.dashed ? const [10, 7] : const []));
          }
        } catch (_) {}
      }
      // 없어졌거나 모양·자리가 바뀐 표시 지우기
      for (final id in _on.keys.toList()) {
        final w = _cur[id], have = _on[id]!;
        if (w == null || w.key != have.$1.key || w.pos != have.$1.pos || w.size != have.$1.size || w.anchor != have.$1.anchor) {
          _on.remove(id);
          try {
            await cc.deleteOverlay(NOverlayInfo(type: NOverlayType.marker, id: id));
          } catch (_) {}
        } else if (w.z != have.$1.z) {
          have.$2.setGlobalZIndex(200000 + w.z);
          _on[id] = (w, have.$2);
        }
      }
      if (!mounted || gen != _gen) return;
      // 사진이 필요 없거나 이미 받아 둔 표시부터 올리고, 나머지는 사진을 한꺼번에 받은 뒤
      final later = <KMark>[];
      for (final m in marks) {
        if (_on.containsKey(m.id)) continue;
        if (_img.containsKey(m.key) || m.images.every(_okUrl.contains)) {
          await _put(cc, m, gen);
          if (!mounted || gen != _gen) return;
        } else {
          later.add(m);
        }
      }
      if (later.isNotEmpty) {
        await Future.wait({for (final m in later) ...m.images}.map(_pre));
        for (final m in later) {
          if (!mounted || gen != _gen) return;
          await _put(cc, m, gen);
        }
      }
    } finally {
      _busy = false;
      if (_again && mounted) {
        _again = false;
        _sync();
      }
    }
  }

  void _attach(NaverMapController cc) {
    final ctl = widget.ctl;
    if (ctl == null) return;
    ctl.onMove = (p, zoom, animate) async {
      final u = NCameraUpdate.withParams(target: _n(p), zoom: zoom - _dz);
      if (animate) u.setAnimation(animation: NCameraAnimation.easing, duration: const Duration(milliseconds: 320));
      try {
        await cc.updateCamera(u);
      } catch (_) {}
    };
    final w = ctl.want, z = ctl.wantZ;
    if (w != null && z != null) {
      ctl.want = null;
      ctl.wantZ = null;
      ctl.onMove!(w, z, false);
    }
  }

  @override
  Widget build(BuildContext context) => NaverMap(
        options: NaverMapViewOptions(
          initialCameraPosition: NCameraPosition(target: _n(widget.center), zoom: widget.zoom - _dz),
          locale: const Locale('ko'),
          logoClickEnable: false,
          rotationGesturesEnable: false,
          tiltGesturesEnable: false,
          scaleBarEnable: false,
          locationButtonEnable: false,
          indoorEnable: false,
          minZoom: 5,
          maxZoom: 18,
        ),
        onMapReady: (ctl) {
          c = ctl;
          _on.clear();
          _lineSig = '';
          _attach(ctl);
          _sync();
        },
        onMapTapped: (_, __) => widget.onMapTap?.call(),
        onCameraChange: (reason, animated) {
          final g = reason == NCameraUpdateReason.gesture;
          if (g) gesture = true;
          final cc = c;
          if (cc == null) return;
          final p = cc.nowCameraPosition;
          widget.onCam?.call(_l(p.target), p.zoom + _dz, g, false);
        },
        onCameraIdle: () async {
          final cc = c;
          if (cc == null) return;
          final g = gesture;
          gesture = false;
          final cam = await cc.getCameraPosition();
          if (!mounted) return;
          widget.onCam?.call(_l(cam.target), cam.zoom + _dz, g, true);
        },
      );
}
