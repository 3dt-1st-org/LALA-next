// 온보딩 1/3 — 여행 유형 선택.
// "국내 여행"(내국인·한국어 기본) / "해외 방문"(외국인·English 기본) 선택 행.
// 탭하면 선택만 갱신하고 자동 이동하지 않는다 — 명시적 "다음" 액션으로 이동.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/lala_metrics.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

class OnboardingStartPage extends StatefulWidget {
  const OnboardingStartPage({super.key});

  @override
  State<OnboardingStartPage> createState() => _OnboardingStartPageState();
}

class _OnboardingStartPageState extends State<OnboardingStartPage> {
  OnboardingTouristType? _selected;

  void _choose(OnboardingTouristType type) {
    setState(() => _selected = type);
    // 선택 즉시 기본 언어만 반영(이동 없음).
    OnboardingState.selectTouristType(type);
  }

  void _next() {
    if (_selected == null) {
      return;
    }
    context.go(LalaRoutePaths.onboardingLanguage);
  }

  @override
  Widget build(BuildContext context) {
    final language = OnboardingState.language;
    return OnboardingScaffold(
      step: 1,
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
            _ChoiceRow(
              icon: Icons.cottage_rounded,
              title: lalaCopy(language, ko: '국내 여행', en: 'Domestic travel'),
              subtitle: lalaCopy(
                language,
                ko: '기본 언어: 한국어',
                en: 'Default language: Korean',
              ),
              selected: _selected == OnboardingTouristType.localTourist,
              onTap: () => _choose(OnboardingTouristType.localTourist),
            ),
            const SizedBox(height: 12),
            _ChoiceRow(
              icon: Icons.flight_land_rounded,
              title: lalaCopy(
                language,
                ko: '해외 방문',
                en: 'Visiting from abroad',
              ),
              subtitle: lalaCopy(
                language,
                ko: '기본 언어: English',
                en: 'Default language: English',
              ),
              selected: _selected == OnboardingTouristType.foreignTourist,
              onTap: () => _choose(OnboardingTouristType.foreignTourist),
            ),
            const Spacer(),
            _NextButton(
              label: lalaCopy(language, ko: '다음', en: 'Next'),
              onPressed: _selected == null ? null : _next,
            ),
          ],
        ),
      ),
    );
  }
}

/// 컴팩트 선택 행(반경 8, 단일 테두리, 선택 시 체크). 최소 56px 높이.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.primary.withValues(alpha: 0.06)
          : Colors.white,
      borderRadius: BorderRadius.circular(LalaMetrics.choiceRowRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LalaMetrics.choiceRowRadius),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LalaMetrics.choiceRowRadius),
            border: Border.all(
              color: selected ? colorScheme.primary : const Color(0xFFE2E8F0),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(
                    alpha: selected ? 0.12 : 0.08,
                  ),
                  borderRadius: BorderRadius.circular(
                    LalaMetrics.choiceRowRadius,
                  ),
                ),
                child: Icon(icon, color: colorScheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
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
                    const SizedBox(height: 2),
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
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? colorScheme.primary : const Color(0xFF94A3B8),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 하단 고정형 다음(CTA) 버튼 — 최소 44px 타겟.
class _NextButton extends StatelessWidget {
  const _NextButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(LalaMetrics.minTouchTarget),
          backgroundColor: const Color(0xFF2B6CB0),
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LalaMetrics.choiceRowRadius),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
