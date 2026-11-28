// 크롬 미리보기: 네이버 지도 없음 (기존 지도를 쓴다)
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import 'nmap_common.dart';
export 'nmap_common.dart';

final ValueNotifier<bool> naverMapOk = ValueNotifier(false);
bool get naverMapOn => false;
Future<void> initNaverMap(String clientId) async {}

Widget naverKok({Key? key, required LatLng center, required double zoom, List<KMark> marks = const [], List<KLine> lines = const [], VoidCallback? onMapTap, KCam? onCam, KMapCtl? ctl, TextStyle? textStyle}) =>
    const SizedBox();
