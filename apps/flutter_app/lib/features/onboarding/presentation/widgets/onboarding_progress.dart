// 모바일 비주얼 계약: 온보딩 진행은 3개 콘텐츠 단계(S1/S2/S3) 텍스트 "N / 3".
// 스플래시는 콘텐츠 단계가 아니므로 이 표시를 노출하지 않는다(01-flow §1, §F1.1).
import 'package:flutter/material.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';

/// 3개 콘텐츠 단계 중 [step] 번째를 "N / 3" 텍스트로 알린다. [step] 은 1..3.
class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({required this.step, super.key})
    : assert(step >= 1 && step <= 3);

  final int step;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$step / 3',
      child: Text(
        '$step / 3',
        style: TextStyle(
          color: LalaVisualColors.muted,
          fontSize: LalaVisualTokens.chipSize,
          height: LalaVisualTokens.chipLineHeight /
              LalaVisualTokens.chipSize,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
