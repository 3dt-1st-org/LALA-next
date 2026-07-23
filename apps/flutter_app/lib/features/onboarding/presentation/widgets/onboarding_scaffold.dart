// 모바일 비주얼 계약 온보딩 공용 레이아웃.
// 상단 좌측에 LalaWordmark + "N / 3" 진행 텍스트(00-ground-truth §3~§5).
// 스플래시는 콘텐츠 단계가 아니므로 showProgress=false 로 진행 텍스트를 숨긴다.
import 'package:flutter/material.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/shared/widgets/lala_wordmark.dart';

import 'onboarding_progress.dart';

/// 온보딩 콘텐츠 페이지(S1~S3) 공통 워드마크 + 진행 헤더 본문 래퍼.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    required this.step,
    required this.child,
    this.showProgress = true,
    super.key,
  }) : assert(step >= 1 && step <= 3);

  /// 1(S1 여행 유형) ~ 3(S3 위치).
  final int step;

  /// 본문.
  final Widget child;

  /// 진행 텍스트 노출 여부(스플래시는 false).
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LalaVisualColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                LalaVisualTokens.pageGutter,
                20,
                LalaVisualTokens.pageGutter,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const LalaWordmark(),
                  if (showProgress) ...<Widget>[
                    const SizedBox(height: 18),
                    OnboardingProgress(step: step),
                  ],
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
