// 모바일 비주얼 계약 S1: 여행 유형 선택.
// 행 탭은 선택 상태만 갱신(자동 이동 금지). "다음" 은 선택 후에만 활성화되어
// 여행 유형 + 기본 언어를 OnboardingState 에 쓰고 S2 로 이동한다(01-flow §F1.2~§F1.3).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
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
  OnboardingTouristType? _pending;

  // S1 은 언어 선택 이전이므로 앱 SSOT(기본 ko)를 따른다.
  String get _language => OnboardingState.language;

  bool get _canAdvance => _pending != null;

  void _select(OnboardingTouristType type) {
    setState(() => _pending = type);
  }

  void _advance() {
    final type = _pending;
    if (type == null) {
      return;
    }
    // 선택한 유형과 그 기본 언어를 SSOT 에 기록한 뒤 S2 로 이동.
    OnboardingState.selectTouristType(type);
    if (mounted) {
      context.go(LalaRoutePaths.onboardingLanguage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = _language;
    return OnboardingScaffold(
      step: 1,
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 236),
              child: Text(
                lalaCopy(
                  language,
                  ko: '어떤 여행을\n계획 중인가요?',
                  en: 'What kind of trip\nare you planning?',
                ),
                style: TextStyle(
                  fontSize: LalaVisualTokens.onboardingTitleSize,
                  height: LalaVisualTokens.onboardingTitleLineHeight /
                      LalaVisualTokens.onboardingTitleSize,
                  fontWeight: FontWeight.w800,
                  color: LalaVisualColors.ink,
                ),
              ),
            ),
            const SizedBox(height: LalaVisualTokens.contentGap + 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 258),
              child: Text(
                lalaCopy(
                  language,
                  ko: '여행 유형을 선택하면 더 알맞은\n추천을 받을 수 있어요.',
                  en: 'Pick a trip type for more\nrelevant recommendations.',
                ),
                style: TextStyle(
                  fontSize: LalaVisualTokens.bodySize,
                  height: LalaVisualTokens.bodyLineHeight /
                      LalaVisualTokens.bodySize,
                  fontWeight: FontWeight.w500,
                  color: LalaVisualColors.muted,
                ),
              ),
            ),
            const SizedBox(height: 28),
            _TravelTypeRow(
              key: const ValueKey('onboarding-travel-domestic'),
              icon: Icons.cottage_rounded,
              label: lalaCopy(language, ko: '국내 여행', en: 'Domestic trip'),
              selected: _pending == OnboardingTouristType.localTourist,
              onTap: () => _select(OnboardingTouristType.localTourist),
            ),
            const SizedBox(height: LalaVisualTokens.onboardingRowGap),
            _TravelTypeRow(
              key: const ValueKey('onboarding-travel-overseas'),
              icon: Icons.flight_takeoff_rounded,
              label: lalaCopy(language, ko: '해외 방문', en: 'Overseas trip'),
              selected: _pending == OnboardingTouristType.foreignTourist,
              onTap: () => _select(OnboardingTouristType.foreignTourist),
            ),
            const Spacer(),
            _OnboardingPrimaryAction(
              label: lalaCopy(language, ko: '다음', en: 'Next'),
              onPressed: _canAdvance ? _advance : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// S1 여행 유형 행(높이 80, 전체 여백 폭). 선택 시 1px primary 테두리 + 옅은 파랑 채움.
class _TravelTypeRow extends StatelessWidget {
  const _TravelTypeRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
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
            ? LalaVisualColors.primaryBlue.withValues(alpha: 0.08)
            : LalaVisualColors.card,
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
          child: Container(
            constraints: const BoxConstraints(minHeight: 80),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
              border: Border.all(
                color: selected
                    ? LalaVisualColors.primaryBlue
                    : LalaVisualColors.line,
                width: 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, color: LalaVisualColors.primaryBlue, size: 24),
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
                  Icons.chevron_right_rounded,
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

/// 온보딩 주 액션(높이 52). onPressed == null 이면 비활성.
class _OnboardingPrimaryAction extends StatelessWidget {
  const _OnboardingPrimaryAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(LalaVisualTokens.actionHeight),
          backgroundColor: LalaVisualColors.primaryBlue,
          disabledBackgroundColor: LalaVisualColors.primaryBlue.withValues(
            alpha: 0.32,
          ),
          foregroundColor: LalaVisualColors.card,
          disabledForegroundColor: LalaVisualColors.card,
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
        child: Text(label),
      ),
    );
  }
}
