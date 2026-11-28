part of 'main.dart';

// ---------------- 지도 한 벌: 휴대폰 앱은 네이버 지도, 크롬 미리보기는 기존 지도 ----------------
// 네이버 지도 Client ID (공개용 — 앱 안에 들어가는 값. 우동콕과 같은 네이버 클라우드 계정, 콘솔에 앱 이름 kr.designfeel.kokple 등록 필요)
const kNaverMapId = String.fromEnvironment('NAVER_MAP_ID', defaultValue: '0g3mx1t2l0');

// 지도 표시 하나: 기존 표시(Marker) + 네이버 지도용 정보 (모양 구분 글자 · 누르면 · 먼저 받을 사진)
class KPin {
  final Marker m;
  final String sig;
  final VoidCallback? onTap;
  final List<String> images;
  const KPin(this.m, {this.sig = '', this.onTap, this.images = const []});
}

// 지도 조종: 어느 지도든 같은 말로 (move · fitCamera · camera)
class KokMapCtl {
  final fm = MapController();
  final n = KMapCtl();
  LatLng _c;
  double _z;
  Size size = const Size(390, 720);
  KokMapCtl(this._c, this._z);

  MapCamera get camera => naverMapOn ? MapCamera(crs: const Epsg3857(), center: _c, zoom: _z, rotation: 0, nonRotatedSize: size) : fm.camera;

  void track(LatLng c, double z) {
    _c = c;
    _z = z;
  }

  void move(LatLng p, double z) {
    if (naverMapOn) {
      _c = p;
      _z = z;
      n.move(p, z);
    } else {
      fm.move(p, z);
    }
  }

  void fitCamera(CameraFit fit) {
    if (naverMapOn) {
      final c = fit.fit(camera);
      move(c.center, c.zoom);
    } else {
      fm.fitCamera(fit);
    }
  }
}

class KokMapView extends StatelessWidget {
  final KokMapCtl ctl;
  final LatLng center;
  final double zoom;
  final List<KPin> pins;
  final List<LatLng> route; // 코스 선 (점선)
  final void Function(MapCamera cam, bool gesture, bool idle)? onCam;
  final VoidCallback? onTap;
  const KokMapView({super.key, required this.ctl, required this.center, required this.zoom, required this.pins, this.route = const [], this.onCam, this.onTap});

  static String _id(Marker m) {
    final k = m.key;
    return k is ValueKey ? '${k.value}' : '${m.point.latitude},${m.point.longitude}';
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: naverMapOk,
        builder: (context, on, _) {
          if (!on) {
            return FlutterMap(
              mapController: ctl.fm,
              options: MapOptions(
                initialCenter: center,
                initialZoom: zoom,
                minZoom: 6,
                maxZoom: 19,
                // 두 손가락에 지도가 돌아가지 않게 (맛집 지도는 늘 북쪽이 위)
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onTap: (_, __) => onTap?.call(),
                onPositionChanged: (camera, hasGesture) => onCam?.call(camera, hasGesture, false),
              ),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'kr.designfeel.kokple'),
                if (route.length > 1)
                  PolylineLayer(polylines: [
                    Polyline(points: route, color: kAccent, strokeWidth: 3, pattern: StrokePattern.dashed(segments: const [10, 7])),
                  ]),
                MarkerLayer(markers: [for (final p in pins) p.m]),
              ],
            );
          }
          return LayoutBuilder(builder: (context, box) {
            if (box.biggest.isFinite && !box.biggest.isEmpty) ctl.size = box.biggest;
            return naverKok(
              center: ctl._c,
              zoom: ctl._z,
              ctl: ctl.n,
              textStyle: const TextStyle(fontFamily: 'Pretendard', color: kInk, fontSize: 14, height: 1.2),
              marks: [
                for (var i = 0; i < pins.length; i++)
                  KMark(
                    id: _id(pins[i].m),
                    key: pins[i].sig.isEmpty ? _id(pins[i].m) : pins[i].sig,
                    pos: pins[i].m.point,
                    child: pins[i].m.child,
                    size: Size(pins[i].m.width, pins[i].m.height),
                    anchor: Offset(0.5 - (pins[i].m.alignment ?? Alignment.center).x / 2, 0.5 - (pins[i].m.alignment ?? Alignment.center).y / 2),
                    onTap: pins[i].onTap,
                    z: i,
                    images: pins[i].images,
                  ),
              ],
              lines: [if (route.length > 1) KLine(route, color: kAccent, width: 3, dashed: true)],
              onMapTap: onTap,
              onCam: (c, z, g, idle) {
                ctl.track(c, z);
                onCam?.call(ctl.camera, g, idle);
              },
            );
          });
        },
      );
}
