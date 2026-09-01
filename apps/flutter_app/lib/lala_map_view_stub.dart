import 'package:flutter/material.dart';

import 'package:lala_next_app/shared/l10n/lala_copy.dart';

import 'lala_map_fallback.dart';
import 'lala_map_models.dart';

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
  return LalaMapFallbackView(
    message: liveMapUnavailableLabel(language),
    language: language,
    centerLat: centerLat,
    centerLng: centerLng,
    places: places,
    onPlaceTap: onPlaceTap,
  );
}
