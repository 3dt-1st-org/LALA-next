import 'package:flutter/material.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/features/onboarding/onboarding_language_options.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

/// 첫 온보딩 질문 전에 접근 가능한 5개 언어 빠른 선택 메뉴.
class OnboardingLanguageMenu extends StatelessWidget {
  const OnboardingLanguageMenu({
    required this.language,
    required this.onSelected,
    super.key,
  });

  final String language;
  final ValueChanged<String> onSelected;

  OnboardingLanguageChoice get _selected =>
      onboardingLanguageChoices.firstWhere(
        (choice) => choice.code == language,
        orElse: () => onboardingLanguageChoices.first,
      );

  @override
  Widget build(BuildContext context) {
    final selectorLabel = lalaCopyMulti(
      language,
      ko: '언어 선택',
      en: 'Choose language',
      ja: '言語を選択',
      zhHans: '选择语言',
      zhHant: '選擇語言',
    );
    final selected = _selected;

    return PopupMenuButton<String>(
      key: const ValueKey('onboarding-quick-language-menu'),
      initialValue: selected.code,
      tooltip: selectorLabel,
      onSelected: onSelected,
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        for (final choice in onboardingLanguageChoices)
          PopupMenuItem<String>(
            key: ValueKey('onboarding-quick-language-${choice.code}'),
            value: choice.code,
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 28,
                  child: Text(
                    choice.badge,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: LalaVisualColors.primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    choice.endonym,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: LalaVisualColors.ink,
                    ),
                  ),
                ),
                if (choice.code == selected.code)
                  const Icon(
                    Icons.check_rounded,
                    size: 20,
                    color: LalaVisualColors.primaryBlue,
                  ),
              ],
            ),
          ),
      ],
      child: Semantics(
        button: true,
        label: '$selectorLabel, ${selected.endonym}',
        child: Container(
          constraints: const BoxConstraints(minWidth: 64, minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: LalaVisualColors.card,
            border: Border.all(color: LalaVisualColors.line),
            borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.language_rounded,
                size: 19,
                color: LalaVisualColors.primaryBlue,
              ),
              const SizedBox(width: 6),
              Text(
                selected.badge,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: LalaVisualColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
