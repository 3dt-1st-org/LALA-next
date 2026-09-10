// 모바일 비주얼 계약 S3: 읽기 전용 네이버 지도 미리보기 래퍼.
// provider-neutral lala_map_view 조건부 import 경계를 사용한다.
// - 제스처/콜백 비활성(IgnorePointer + 콜백 null) → 사용자 조작 불가, 키 검증은 우회하지 않는다.
// - 좌표가 없으면 핀을 발명하지 않는다(places = 빈). 키가 없으면 경계가 폴백(blocked) 상태를 낸다.
// - 대체 타일/손그림 지도를 그리지 않는다(00-ground-truth §5, 01-flow §F2.4).
import 'package:flutter/material.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/lala_map_provider.dart';
import 'package:lala_next_app/lala_map_view.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

/// S3 위치 동의 화면의 읽기 전용 지도 미리보기. 클라이언트 ID가
/// 없으면 폴백(blocked) 상태다.
class LocationMapPreview extends StatelessWidget {
  const LocationMapPreview({
    required this.naverMapClientId,
    required this.language,
    required this.centerLat,
    required this.centerLng,
    this.level = 4,
    super.key,
  });

  final String naverMapClientId;
  final String language;
  final double centerLat;
  final double centerLng;
  final int level;

  @override
  Widget build(BuildContext context) {
    // 비한국어 로케일은 오픈 벡터 지도가 렌더되므로 접근성 이름도 실제
    // provider를 따른다(한국어는 기존 네이버 라벨 유지).
    final usesOpenVectorMap =
        selectLalaMapProvider(language) == LalaMapProviderKind.openVector;
    return Semantics(
      label: usesOpenVectorMap
          ? openVectorMapLabel(language, preview: true)
          : naverMapLabel(language, preview: true),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        child: SizedBox(
          height: LalaVisualTokens.locationPreviewHeight,
          width: double.infinity,
          // 읽기 전용: 사용자 제스처 차단. 콜백은 전달하지 않아 상호작용을 끊는다.
          child: IgnorePointer(
            child: buildLalaMapView(
              clientId: naverMapClientId,
              language: language,
              centerLat: centerLat,
              centerLng: centerLng,
              level: level,
              places: const <LalaMapPlace>[],
              interactionEnabled: false,
            ),
          ),
        ),
      ),
    );
  }
}
