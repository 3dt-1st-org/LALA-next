// 모바일 비주얼 계약(Slice E/S6): 일정 생성 '준비 중' 카드 — 정확히 한 장.
// 타이머/퍼센트/서버 단계 완료 주장 없이 중성 상태만 보여준다(01-flow §F4.2~§F4.3).
// - 제목: 일정을 준비하고 있어요
// - method row: 장소 선택 / 동선 정리 / 날씨 반영 (중성 입력, 완료 표시 없음)
import 'package:flutter/material.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

/// 일정 생성 '준비 중' 카드. 진행률(%)이나 완료 단계를 발명하지 않는다.
class PlannerLoadingCard extends StatelessWidget {
  const PlannerLoadingCard({super.key, required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('planner-loading-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        border: Border.all(color: LalaVisualColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  lalaCopy(
                    language,
                    ko: '일정을 준비하고 있어요',
                    en: 'Preparing your plan',
                  ),
                  style: TextStyle(
                    color: LalaVisualColors.ink,
                    fontSize: LalaVisualTokens.controlLabelSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // method row: 중성 입력. 어떤 항목도 '완료' 로 표시하지 않는다.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _NeutralMethodChip(
                label: lalaCopy(language, ko: '장소 선택', en: 'Places'),
              ),
              _NeutralMethodChip(
                label: lalaCopy(language, ko: '동선 정리', en: 'Route'),
              ),
              _NeutralMethodChip(
                label: lalaCopy(language, ko: '날씨 반영', en: 'Weather'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 중성 method 칩. 완료/진행 표시 없이 옅은 테두리의 라벨만.
class _NeutralMethodChip extends StatelessWidget {
  const _NeutralMethodChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: LalaVisualColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: LalaVisualColors.line),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: LalaVisualTokens.chipSize,
          fontWeight: FontWeight.w700,
          color: LalaVisualColors.muted,
        ),
      ),
    );
  }
}
