import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';

/// CP1: 플랜/플래너 표면 위의 간단한 선호 반영 요약.
///
/// - grounded(실제 반영된) 효과 수만 카운트로 보여준다.
/// - 펼쳐서 각 항목의 서버 안내문(정직한 미반영 사유 포함)을 볼 수 있다.
/// - 데이터 근거가 없는 필드(요리/예산/마감 임박)는 '적용됨'으로 표시하지
///   않는다 — applied=false 로 내려온 그대로 미반영으로 보여준다.
/// - 텍스트가 2배(200%)로 커져도 넘치지 않는다(soft wrap, 고정 높이 없음).
class PlanPreferenceEffectsSummary extends StatelessWidget {
  const PlanPreferenceEffectsSummary({
    super.key,
    required this.effects,
    required this.language,
  });

  final List<LalaPlanPreferenceEffect> effects;
  final String language;

  @override
  Widget build(BuildContext context) {
    if (effects.isEmpty) {
      return const SizedBox.shrink();
    }
    final appliedCount = effects.where((effect) => effect.applied).length;
    final unappliedCount = effects.length - appliedCount;
    final title = lalaCopyMulti(
      language,
      ko: '여행 선호 반영 $appliedCount건',
      en: '$appliedCount preference effects applied',
      ja: '旅行の好みを$appliedCount件反映',
      zhHans: '已应用 $appliedCount 项旅行偏好',
      zhHant: '已套用 $appliedCount 項旅行偏好',
    );
    final appliedLabel = lalaCopyMulti(
      language,
      ko: '반영됨',
      en: 'Applied',
      ja: '反映済み',
      zhHans: '已反映',
      zhHant: '已反映',
    );
    final notAppliedLabel = lalaCopyMulti(
      language,
      ko: '미반영',
      en: 'Not applied',
      ja: '未反映',
      zhHans: '未反映',
      zhHant: '未反映',
    );
    final summarySemantics = lalaCopyMulti(
      language,
      ko: '여행 선호 중 $appliedCount건이 일정에 반영되었고, '
          '$unappliedCount건은 데이터가 없어 반영되지 않았어요. 자세히 보기로 '
          '항목별 설명을 확인할 수 있어요.',
      en: '$appliedCount of your travel preferences were applied to this plan '
          'and $unappliedCount were not applied because the data is missing. '
          'Open details for per-item explanations.',
      ja: '旅行の好みのうち$appliedCount件がプランに反映され、'
          '$unappliedCount件はデータがないため反映されませんでした。詳細で項目別の説明を確認できます。',
      zhHans: '您的旅行偏好中有 $appliedCount 项已应用到行程，'
          '$unappliedCount 项因缺少数据未应用。打开详情可查看逐项说明。',
      zhHant: '您的旅行偏好中有 $appliedCount 項已套用到行程，'
          '$unappliedCount 項因缺少資料未套用。開啟詳細可查看逐項說明。',
    );

    return Semantics(
      container: true,
      label: summarySemantics,
      child: Material(
        key: const ValueKey('plan-preference-effects-summary'),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.45,
            ),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          // 기본 ExpansionTile 의 divider/여백을 제거해 컴팩트하게 유지.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey('plan-preference-effects-expansion'),
            dense: true,
            visualDensity: VisualDensity.compact,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            title: Text(
              title,
              key: const ValueKey('plan-preference-effects-count'),
              maxLines: null,
              overflow: TextOverflow.visible,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            children: [
              for (final effect in effects)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          effect.applied
                              ? Icons.check_circle_outline_rounded
                              : Icons.remove_circle_outline_rounded,
                          size: 16,
                          color: effect.applied
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                          semanticLabel: effect.applied
                              ? appliedLabel
                              : notAppliedLabel,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 200% 텍스트에서도 넘치지 않도록 줄바꿈 허용(고정 높이 없음).
                      Expanded(
                        child: Text(
                          '${effect.applied ? appliedLabel : notAppliedLabel} · '
                          '${effect.explanation}',
                          maxLines: null,
                          overflow: TextOverflow.visible,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
