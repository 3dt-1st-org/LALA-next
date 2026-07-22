// ONMU P2: 온보딩 페이지 공용 레이아웃 — SafeArea + 상단 바(뒤로가기 + 진행 표시).
// 배경은 ColorScheme.fromSeed(surface) 를 따르고 풀스크린으로 동작한다.
import 'package:flutter/material.dart';

import 'onboarding_progress.dart';

/// 온보딩 4페이지의 공통 상단 바 + 본문 래퍼.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    required this.step,
    required this.child,
    this.showBack = true,
    this.onBack,
    super.key,
  }) : assert(step >= 1 && step <= 4);

  /// 1(스플래시) ~ 4(위치권한).
  final int step;

  /// 본문.
  final Widget child;

  /// 상단 뒤로가기 버튼 노출 여부(스플래시는 false).
  final bool showBack;

  /// 뒤로가기 콜백. null 이면 기본 Navigator.pop 을 사용한다.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (showBack)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 20, 0),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      onPressed: onBack ?? () => _defaultBack(context),
                      icon: const Icon(Icons.arrow_back_ios_new),
                      color: colorScheme.primary,
                    ),
                    Expanded(child: OnboardingProgress(step: step)),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: OnboardingProgress(step: step),
              ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  void _defaultBack(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).maybePop();
    }
  }
}
