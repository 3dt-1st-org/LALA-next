// 위치 권한 화면 등에서 쓰는 비대화형 카카오 지도 미리보기 래퍼.
// 기존 조건부 import 시스템(buildKakaoMapView)을 places 없이 재사용한다.
// 새 가짜 지도 드로잉을 만들지 않고, 앱 키가 없으면 기존 명시적 fallback 이 노출된다.
// IgnorePointer + ClipRRect 로 미리보기 영역 안에서 상호작용을 끊는다.
import 'package:flutter/material.dart';

import '../../kakao_map_view.dart';

class KakaoMapPreview extends StatelessWidget {
  const KakaoMapPreview({
    super.key,
    required this.javascriptKey,
    required this.language,
    required this.centerLat,
    required this.centerLng,
    this.level = 4,
    this.semanticsLabel,
  });

  final String javascriptKey;
  final String language;
  final double centerLat;
  final double centerLng;
  final int level;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel ??
          (language == 'en' ? 'Map preview' : '지도 미리보기'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IgnorePointer(
          child: buildKakaoMapView(
            javascriptKey: javascriptKey,
            language: language,
            centerLat: centerLat,
            centerLng: centerLng,
            level: level,
            places: const <KakaoMapPlace>[],
          ),
        ),
      ),
    );
  }
}
