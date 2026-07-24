// 모바일 비주얼 계약: 스플래시는 짧은 비대화형 부트 전환이며 콘텐츠 단계가 아니다.
// 따라서 "1/3" 진행 텍스트를 노출하지 않는다(01-flow §1, §F1.1). 2초 후 S1 로 이동.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
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
    return Scaffold(
      backgroundColor: LalaVisualColors.surface,
      body: SafeArea(
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
      ),
    );
  }
}
