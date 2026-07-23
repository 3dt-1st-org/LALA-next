// 모바일 비주얼 계약(Slice D): 중성 스켈레톤 프리미티브.
// 로딩 플레이스홀더 전용 — 가짜 매장명/이미지 없이 중성 블록만 그린다(03-acceptance S1).
// 무한 애니메이션은 pumpAndSettle 을 멈추게 하고 reduced-motion 규칙에 위배되므로
// 정적 블록으로 제공(00-ground-truth §7 skeleton row: 중성 블록).
import 'package:flutter/material.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';

/// 중성 스켈레톤 박스. 라벨/이미지 위장 없이 고정된 회색 블록.
class LalaSkeleton extends StatelessWidget {
  const LalaSkeleton({
    this.width,
    this.height = 12,
    this.radius = 6,
    super.key,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: LalaVisualColors.line,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// 텍스트 한 줄 모양의 스켈레톤 레일.
class LalaSkeletonLine extends StatelessWidget {
  const LalaSkeletonLine({
    required this.width,
    this.height = 12,
    super.key,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LalaSkeleton(width: width, height: height, radius: height / 2);
  }
}
