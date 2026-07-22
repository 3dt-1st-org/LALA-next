// ONMU P2: 온보딩 3/4 — 언어 선택(한국어 / English).
// start 단계에서 선택한 기본 언어가 pre-select 된다. 사용자가 변경 가능.
// "다음" 버튼으로 /onboarding/location 으로 이동한다.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

class OnboardingLanguagePage extends StatefulWidget {
  const OnboardingLanguagePage({super.key});

  @override
  State<OnboardingLanguagePage> createState() => _OnboardingLanguagePageState();
}

class _OnboardingLanguagePageState extends State<OnboardingLanguagePage> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    // start 단계에서 정해진 기본 언어로 pre-select.
    _selected = OnboardingState.language;
  }

  void _choose(String language) {
    setState(() => _selected = language);
    OnboardingState.selectLanguage(language);
  }

  @override
  Widget build(BuildContext context) {
    final language = OnboardingState.language;
    return OnboardingScaffold(
      step: 3,
      onBack: () => context.go(LalaRoutePaths.onboardingStart),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: 12),
            Text(
              lalaCopy(language, ko: '언어 선택', en: 'Choose a language'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.16,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              lalaCopy(
                language,
                ko: '앱 화면 언어를 선택하세요.',
                en: 'Pick the app display language.',
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 24),
            _LanguageOption(
              label: lalaCopy(language, ko: '한국어', en: 'Korean'),
              emoji: '🇰🇷',
              selected: _selected == 'ko',
              onTap: () => _choose('ko'),
            ),
            const SizedBox(height: 12),
            _LanguageOption(
              label: lalaCopy(language, ko: '영어', en: 'English'),
              emoji: '🇺🇸',
              selected: _selected == 'en',
              onTap: () => _choose('en'),
            ),
            const Spacer(),
            _NextButton(
              label: lalaCopy(language, ko: '다음', en: 'Next'),
              onPressed: () => context.go(LalaRoutePaths.onboardingLocation),
            ),
          ],
        ),
      ),
    );
  }
}

/// 언어 단일 선택 옵션(라디오 카드, 최소 56px 높이).
class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colorScheme.primary.withValues(alpha: 0.06) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? colorScheme.primary : const Color(0xFFE2E8F0),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? colorScheme.primary
                    : const Color(0xFF94A3B8),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 하단 고정형 다음(CTA) 버튼 — 최소 56px 높이.
class _NextButton extends StatelessWidget {
  const _NextButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: const Color(0xFF2B6CB0),
          foregroundColor: Colors.white,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
