import 'package:flutter/widgets.dart';

import 'lala_map_models.dart';
import 'lala_map_view_stub.dart'
    if (dart.library.html) 'lala_map_view_web.dart'
    if (dart.library.io) 'lala_map_view_native.dart'
    as impl;

export 'lala_map_models.dart';

Widget buildLalaMapView({
  required String clientId,
  required String language,
  required double centerLat,
  required double centerLng,
  required int level,
  required List<LalaMapPlace> places,
  bool interactionEnabled = true,
  ValueChanged<String>? onPlaceTap,
  ValueChanged<LalaMapCamera>? onCameraIdle,
}) {
  return impl.buildLalaMapView(
    clientId: clientId,
    language: language,
    centerLat: centerLat,
    centerLng: centerLng,
    level: level,
    places: places,
    interactionEnabled: interactionEnabled,
    onPlaceTap: onPlaceTap,
    onCameraIdle: onCameraIdle,
  );
}
