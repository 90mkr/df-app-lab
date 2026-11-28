// 지도 공용 모양 (네이버 지도 · 미리보기 지도가 같이 씀)
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

// 지도 위 표시 하나: 만든 위젯 그대로 (네이버 지도는 위젯을 그림으로 한 번 바꿔 씀 → 모양이 바뀌면 key 도 바꿔야 함)
class KMark {
  final String id, key;
  final LatLng pos;
  final Widget child;
  final Size size;
  final Offset anchor; // 그림에서 그 위치를 가리키는 점 (0~1)
  final VoidCallback? onTap;
  final int z; // 클수록 위
  final List<String> images; // 그리기 전에 먼저 받아 둘 인터넷 사진
  const KMark({required this.id, required this.key, required this.pos, required this.child, required this.size, this.anchor = const Offset(0.5, 0.5), this.onTap, this.z = 0, this.images = const []});
}

class KLine {
  final List<LatLng> points;
  final Color color;
  final double width;
  final bool dashed;
  const KLine(this.points, {required this.color, this.width = 3, this.dashed = false});
}

// 지도가 움직일 때: 가운데 · 확대값(미리보기 지도와 같은 단위) · 손으로 움직였는지 · 멈췄는지
typedef KCam = void Function(LatLng center, double zoom, bool gesture, bool idle);

// 네이버 지도 조종 손잡이 (지도가 뜨기 전에 온 이동은 기억해 뒀다가 뜨면 옮김)
class KMapCtl {
  Future<void> Function(LatLng p, double zoom, bool animate)? onMove;
  LatLng? want;
  double? wantZ;
  void move(LatLng p, double zoom, {bool animate = true}) {
    final f = onMove;
    if (f == null) {
      want = p;
      wantZ = zoom;
    } else {
      f(p, zoom, animate);
    }
  }
}
