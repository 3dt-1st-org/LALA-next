// ONMU P2: 온보딩 2/4 — 관광객 유형 선택.
// 외국인 관광객(기본 English) / 내국인 관광객(기본 한국어). 큰 버튼, 명확 CTA.
// 선택 시 OnboardingState 에 유형+기본언어를 저장하고 /onboarding/language 로 이동한다.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

class OnboardingStartPage extends StatelessWidget {
  const OnboardingStartPage({super.key});

  @override
  Widget build(BuildContext context) {
    // start 단계 표시 언어는 앱 기본(OnboardingState.language, 기본 ko)을 따른다.
    final language = OnboardingState.language;
    return OnboardingScaffold(
      step: 2,
      onBack: () => context.go(LalaRoutePaths.onboardingSplash),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: 12),
            Text(
              lalaCopy(
                language,
                ko: '어떤 관광객이신가요?',
                en: 'Which best describes you?',
              ),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.16,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              lalaCopy(
                language,
                ko: '맞춤 추천을 위해 선택해 주세요. 언어는 다음에서 바꿀 수 있어요.',
                en: 'Pick one for tailored tips. You can change the language next.',
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 24),
            _TouristTypeCard(
              icon: Icons.flight_land_rounded,
              title: lalaCopy(language, ko: '외국인 관광객', en: 'Foreign Tourist'),
              subtitle: lalaCopy(
                language,
                ko: '기본 언어: English',
                en: 'Default language: English',
              ),
              onTap: () => _select(context, OnboardingTouristType.foreignTourist),
            ),
            const SizedBox(height: 14),
            _TouristTypeCard(
              icon: Icons.cottage_rounded,
              title: lalaCopy(language, ko: '내국인 관광객', en: 'Local Tourist'),
              subtitle: lalaCopy(
                language,
                ko: '기본 언어: 한국어',
                en: 'Default language: Korean',
              ),
              onTap: () => _select(context, OnboardingTouristType.localTourist),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  void _select(BuildContext context, OnboardingTouristType type) {
    OnboardingState.selectTouristType(type);
    context.go(LalaRoutePaths.onboardingLanguage);
  }
}

/// 큰 터치 타겟(최소 56px 높이)의 관광객 유형 선택 카드.
class _TouristTypeCard extends StatelessWidget {
  const _TouristTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                blurRadius: 14,
                offset: Offset(0, 6),
                color: Color(0x10000000),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            height: 1.2,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.primary,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
