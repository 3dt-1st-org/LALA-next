// 모바일 비주얼 계약 S3: 읽기 전용 카카오맵 미리보기 래퍼.
// 기존 kakao_map_view 조건부 import 경계(buildKakaoMapView)를 그대로 사용한다.
// - 제스처/콜백 비활성(IgnorePointer + 콜백 null) → 사용자 조작 불가, 키 검증은 우회하지 않는다.
// - 좌표가 없으면 핀을 발명하지 않는다(places = 빈). 키가 없으면 경계가 폴백(blocked) 상태를 낸다.
// - 대체 타일/손그림 지도를 그리지 않는다(00-ground-truth §5, 01-flow §F2.4).
import 'package:flutter/material.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/kakao_map_view.dart';

/// S3 위치 동의 화면의 읽기 전용 지도 미리보기. 라이브 키가 없으면 폴백(blocked) 상태.
class LocationMapPreview extends StatelessWidget {
  const LocationMapPreview({
    required this.kakaoJavascriptKey,
    required this.centerLat,
    required this.centerLng,
    this.level = 4,
    super.key,
  });

  final String kakaoJavascriptKey;
  final double centerLat;
  final double centerLng;
  final int level;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Kakao map preview',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        child: SizedBox(
          height: LalaVisualTokens.locationPreviewHeight,
          width: double.infinity,
          // 읽기 전용: 사용자 제스처 차단. 콜백은 전달하지 않아 상호작용을 끊는다.
          child: IgnorePointer(
            child: buildKakaoMapView(
              javascriptKey: kakaoJavascriptKey,
              language: 'ko',
              centerLat: centerLat,
              centerLng: centerLng,
              level: level,
              places: const <KakaoMapPlace>[],
            ),
          ),
        ),
      ),
    );
  }
}
