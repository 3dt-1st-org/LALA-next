import 'package:flutter/widgets.dart';

import 'kakao_map_models.dart';
import 'kakao_map_view_stub.dart'
    if (dart.library.html) 'kakao_map_view_web.dart'
    as impl;

export 'kakao_map_models.dart';

Widget buildKakaoMapView({
  required String javascriptKey,
  required double centerLat,
  required double centerLng,
  required int level,
  required List<KakaoMapPlace> places,
  ValueChanged<String>? onPlaceTap,
}) {
  return impl.buildKakaoMapView(
    javascriptKey: javascriptKey,
    centerLat: centerLat,
    centerLng: centerLng,
    level: level,
    places: places,
    onPlaceTap: onPlaceTap,
  );
}
