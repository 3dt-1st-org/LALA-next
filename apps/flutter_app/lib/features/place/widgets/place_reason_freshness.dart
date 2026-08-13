import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../place_helpers.dart';

/// V1-RC2: 장소 추천 reason 단일 라인(1줄 ellipsis). 모든 표면이 동일 스타일/게이트
/// 규칙을 공유하도록 SSOT 위젯. [place.reason] 이 null/빈이면 렌더하지 않는다(honest).
///
/// [style] 로 배경에 맞춰 색/크기를 덮는다(예: 이미지 오버레이 카드의 흰색 텍스트).
/// [topSpacing] > 0 일 때 reason 이 있으면 상단 간격도 같이 렌더하고, 없으면 0(빈 공간
/// 없음) — 호출측의 조건부 간격 분기를 대체한다.
class PlaceReasonLine extends StatelessWidget {
  const PlaceReasonLine({
    super.key,
    required this.place,
    this.style,
    this.topSpacing = 0,
  });

  final LalaPlace place;

  /// 기본 스타일(밝은 배면: bodySmall/slate-500/w600/h1.2)을 덮어쓸 배경 맞춤 스타일.
  final TextStyle? style;
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    final reason = placeReasonText(place);
    if (reason == null) {
      return const SizedBox.shrink();
    }
    final effective =
        style ??
        Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF64748B),
          fontWeight: FontWeight.w600,
          height: 1.2,
        );
    final row = Row(
      children: [
        Expanded(
          child: Text(
            reason,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: effective,
          ),
        ),
      ],
    );
    if (topSpacing <= 0) {
      return row;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: topSpacing),
        row,
      ],
    );
  }
}

/// V1-RC2: 장소 데이터 신선도 텍스트(labelSmall/slate). reason 과 동일 게이트 규칙.
/// [style] 로 배경에 맞춘 스타일 덮기 가능.
class PlaceFreshnessText extends StatelessWidget {
  const PlaceFreshnessText({super.key, required this.place, this.style});

  final LalaPlace place;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final freshness = placeFreshnessText(place);
    if (freshness == null) {
      return const SizedBox.shrink();
    }
    return Text(
      freshness,
      style:
          style ??
          Theme.of(context).textTheme.labelSmall?.copyWith(
            color: const Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
    );
  }
}
