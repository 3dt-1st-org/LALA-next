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
    message: language == 'en'
        ? 'The live map is not available right now.'
        : '현재 지도를 표시할 수 없습니다.',
    language: language,
    centerLat: centerLat,
    centerLng: centerLng,
    places: places,
    onPlaceTap: onPlaceTap,
  );
}
