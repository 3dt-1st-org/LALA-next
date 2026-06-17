import 'package:flutter/material.dart';

import 'kakao_map_fallback.dart';
import 'kakao_map_models.dart';

Widget buildKakaoMapView({
  required String javascriptKey,
  required String language,
  required double centerLat,
  required double centerLng,
  required int level,
  required List<KakaoMapPlace> places,
  ValueChanged<String>? onPlaceTap,
  ValueChanged<KakaoMapCamera>? onCameraIdle,
}) {
  return KakaoMapFallbackView(
    message: language == 'en' ? 'Kakao Map API' : '카카오 지도',
    language: language,
    centerLat: centerLat,
    centerLng: centerLng,
    places: places,
    onPlaceTap: onPlaceTap,
  );
}
