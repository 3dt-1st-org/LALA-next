// ONMU P2: 온보딩 1/4 — 스플래시. LALA 로고 + 로딩. 2초 후 자동 start 로 이동.
// 풀스크린, ColorScheme.fromSeed 배경. 상단 진행 표시(1/4).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';
import 'package:lala_next_app/shared/widgets/lala_wordmark.dart';

class OnboardingSplashPage extends StatefulWidget {
  const OnboardingSplashPage({super.key});

  @override
  State<OnboardingSplashPage> createState() => _OnboardingSplashPageState();
}

class _OnboardingSplashPageState extends State<OnboardingSplashPage> {
  static const Duration _displayDuration = Duration(seconds: 2);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_displayDuration, () {
      if (mounted) {
        context.go(LalaRoutePaths.onboardingStart);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // splash 시점 표시 언어는 앱 기본(OnboardingState.language, 기본 ko)을 따른다.
    // 디바이스 로케일이 아닌 앱 SSOT 언어를 써서 흐름을 결정적으로 유지한다.
    final language = OnboardingState.language;
    return OnboardingScaffold(
      step: 1,
      showBack: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const LalaWordmark(),
              const SizedBox(height: 28),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                lalaCopy(
                  language,
                  ko: '당신의 수원을 안내합니다',
                  en: 'Your Suwon, guided',
                ),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF475569),
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
