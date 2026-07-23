// 모바일 비주얼 계약 S2: 언어 선택.
// KO/EN 텍스트 배지(국기 이모지 아님). 행 라벨은 각 언어의 고유명(한국어/English)으로
// 이 선택 화면에서만 의도적 이중 노출. 선택 즉시 OnboardingState 언어를 갱신(01-flow §F1.4).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
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
    // S1 에서 정해진 기본 언어로 pre-select(국내→ko, 해외→en).
    _selected = OnboardingState.language;
  }

  void _choose(String language) {
    setState(() => _selected = language);
    // 선택 즉시 앱 copy 소스(SSOT)를 갱신한다.
    OnboardingState.selectLanguage(language);
  }

  void _advance() {
    if (mounted) {
      context.go(LalaRoutePaths.onboardingLocation);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = OnboardingState.language;
    return OnboardingScaffold(
      step: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LalaVisualTokens.pageGutter,
          24,
          LalaVisualTokens.pageGutter,
          LalaVisualTokens.sectionGap + 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              lalaCopy(language, ko: '언어 선택', en: 'Language'),
              style: TextStyle(
                fontSize: LalaVisualTokens.onboardingTitleSize,
                height: LalaVisualTokens.onboardingTitleLineHeight /
                    LalaVisualTokens.onboardingTitleSize,
                fontWeight: FontWeight.w800,
                color: LalaVisualColors.ink,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              lalaCopy(
                language,
                ko: '앱에서 사용할 언어를 선택하세요.',
                en: 'Choose the language for the app.',
              ),
              style: TextStyle(
                fontSize: LalaVisualTokens.bodySize,
                height: LalaVisualTokens.bodyLineHeight /
                    LalaVisualTokens.bodySize,
                fontWeight: FontWeight.w500,
                color: LalaVisualColors.muted,
              ),
            ),
            const SizedBox(height: 28),
            _LanguageRow(
              key: const ValueKey('onboarding-language-ko'),
              badge: 'KO',
              label: '한국어',
              selected: _selected == 'ko',
              onTap: () => _choose('ko'),
            ),
            const SizedBox(height: LalaVisualTokens.contentGap),
            _LanguageRow(
              key: const ValueKey('onboarding-language-en'),
              badge: 'EN',
              label: 'English',
              selected: _selected == 'en',
              onTap: () => _choose('en'),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _advance,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(
                    LalaVisualTokens.actionHeight,
                  ),
                  backgroundColor: LalaVisualColors.primaryBlue,
                  foregroundColor: LalaVisualColors.card,
                  textStyle: TextStyle(
                    fontSize: LalaVisualTokens.controlLabelSize,
                    height: LalaVisualTokens.controlLabelLineHeight /
                        LalaVisualTokens.controlLabelSize,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      LalaVisualTokens.controlRadius,
                    ),
                  ),
                ),
                child: Text(lalaCopy(language, ko: '다음', en: 'Next')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// S2 언어 행(높이 72). KO/EN 텍스트 배지 + 고유명 + 우측 check/radio 표시.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.badge,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String badge;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected
            ? LalaVisualColors.primaryBlue.withValues(alpha: 0.06)
            : LalaVisualColors.card,
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                LalaVisualTokens.controlRadius,
              ),
              border: Border.all(
                color: selected
                    ? LalaVisualColors.primaryBlue
                    : LalaVisualColors.line,
                width: 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                _LanguageBadge(code: badge, selected: selected),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: LalaVisualTokens.controlLabelSize,
                      height: LalaVisualTokens.controlLabelLineHeight /
                          LalaVisualTokens.controlLabelSize,
                      fontWeight: FontWeight.w700,
                      color: LalaVisualColors.ink,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: selected
                      ? LalaVisualColors.primaryBlue
                      : LalaVisualColors.muted,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// KO/EN 텍스트 배지(국기 이모지 대체). 00-ground-truth §4: 텍스트 배지.
class _LanguageBadge extends StatelessWidget {
  const _LanguageBadge({required this.code, required this.selected});

  final String code;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? LalaVisualColors.primaryBlue
            : LalaVisualColors.line,
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: selected ? LalaVisualColors.card : LalaVisualColors.ink,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
