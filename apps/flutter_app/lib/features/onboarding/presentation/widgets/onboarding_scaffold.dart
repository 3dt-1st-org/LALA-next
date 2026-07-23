// ONMU P2: 온보딩 페이지 공용 레이아웃 — SafeArea + 상단 바(뒤로가기 + 진행 표시).
// 진행 표시는 3 콘텐츠 단계(1/3~3/3). 스플래시는 showProgress=false 로 표시 생략.
import 'package:flutter/material.dart';

import 'onboarding_progress.dart';

/// 온보딩 페이지 공통 상단 바 + 본문 래퍼.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    required this.step,
    required this.child,
    this.total = 3,
    this.showBack = true,
    this.showProgress = true,
    this.onBack,
    super.key,
  });

  /// 1(시작) ~ 3(위치권한) 콘텐츠 단계.
  final int step;

  /// 전체 콘텐츠 단계 수(기본 3).
  final int total;

  /// 본문.
  final Widget child;

  /// 상단 뒤로가기 버튼 노출 여부.
  final bool showBack;

  /// 상단 진행 표시 노출 여부(스플래시는 false).
  final bool showProgress;

  /// 뒤로가기 콜백. null 이면 기본 Navigator.pop 을 사용한다.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = showProgress
        ? OnboardingProgress(step: step, total: total)
        : const SizedBox.shrink();
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
                    Expanded(child: progress),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: progress,
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
