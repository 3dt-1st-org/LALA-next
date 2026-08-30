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
      color: LalaVisualColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      offset: const Offset(0, 8),
      constraints: const BoxConstraints(minWidth: 208, maxWidth: 232),
      menuPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        side: const BorderSide(color: LalaVisualColors.line),
      ),
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        for (final choice in onboardingLanguageChoices)
          PopupMenuItem<String>(
            key: ValueKey('onboarding-quick-language-${choice.code}'),
            value: choice.code,
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _LanguageMenuRow(
              choice: choice,
              selected: choice.code == selected.code,
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

class _LanguageMenuRow extends StatelessWidget {
  const _LanguageMenuRow({required this.choice, required this.selected});

  final OnboardingLanguageChoice choice;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      key: ValueKey(
        selected
            ? 'onboarding-quick-language-selected-${choice.code}'
            : 'onboarding-quick-language-row-${choice.code}',
      ),
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? LalaVisualColors.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              choice.endonym,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                color: selected
                    ? LalaVisualColors.primaryBlue
                    : LalaVisualColors.ink,
              ),
            ),
          ),
          Text(
            choice.badge,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: selected
                  ? LalaVisualColors.primaryBlue
                  : LalaVisualColors.muted,
            ),
          ),
          const SizedBox(width: 10),
          if (selected)
            const Icon(
              Icons.check_circle_rounded,
              size: 20,
              color: LalaVisualColors.primaryBlue,
            )
          else
            const SizedBox(width: 20),
        ],
      ),
    );
  }
}
