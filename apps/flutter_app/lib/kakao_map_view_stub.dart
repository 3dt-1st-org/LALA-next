import 'package:flutter/material.dart';

import 'package:lala_next_app/shared/l10n/lala_copy.dart';

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
    // V6: ko 만 KO 안내문(방문객 로케일 EN 폴백).
    message: normalizeLalaLanguage(language) != 'ko'
        ? 'The live map is not available right now.'
        : '현재 지도를 표시할 수 없습니다.',
    language: language,
    centerLat: centerLat,
    centerLng: centerLng,
    places: places,
    onPlaceTap: onPlaceTap,
  );
}
