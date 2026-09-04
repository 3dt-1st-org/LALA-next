import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';

/// CP1: 플랜/플래너 표면 위의 간단한 선호 반영 요약.
///
/// - grounded(실제 반영된) 효과 수만 카운트로 보여준다.
/// - 펼쳐서 각 항목의 안내문(정직한 미반영 사유 포함)을 볼 수 있다.
/// - 데이터 근거가 없는 필드(요리/예산/마감 임박)는 '적용됨'으로 표시하지
///   않는다 — applied=false 로 내려온 그대로 미반영으로 보여준다.
/// - 안내문은 클라이언트 소유 5-locale 카피(알려진 사유 코드별)를 우선하고,
///   알 수 없는 코드만 서버 원문(ko/en)으로 폴백한다.
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
                          '${localizedPreferenceEffectExplanation(effect, language) ?? effect.explanation}',
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

/// 알려진 bounded 사유 코드의 클라이언트 소유 5-locale 안내문.
/// 반경 계열은 bounded details(요청/유효 반경, 유효 분)만 보간하고, 필요한 값이
/// 없으면 null(서버 원문 폴백)을 반환한다. 알 수 없는 코드도 null 폴백.
/// KO/EN 문장은 서버 설명과 의미 동등(정적 문장은 동일 문구).
String? localizedPreferenceEffectExplanation(
  LalaPlanPreferenceEffect effect,
  String language,
) {
  switch (effect.reasonCode) {
    case 'RADIUS_CAPPED_TO_WALKING_TIME':
      final minutes = _detailInt(effect, 'effective_one_way_minutes');
      final requested = _detailInt(effect, 'requested_radius_m');
      final effective = _detailInt(effect, 'effective_radius_m');
      if (minutes == null || requested == null || effective == null) {
        return null;
      }
      return lalaCopyMulti(
        language,
        ko: '이동 시간 선호($minutes분)에 맞춰 탐색 반경을 '
            '${requested}m에서 ${effective}m로 줄였어요.',
        en: 'Capped the search radius from ${requested}m to ${effective}m '
            'to match the $minutes-minute one-way preference.',
        ja: '移動時間の設定（$minutes分）に合わせて、検索範囲を'
            '${requested}mから${effective}mに狭めました。',
        zhHans: '根据单程时间偏好（$minutes 分钟），已将搜索范围从 '
            '$requested 米缩小到 $effective 米。',
        zhHant: '依據單程時間偏好（$minutes 分鐘），已將搜尋範圍從 '
            '$requested 公尺縮小到 $effective 公尺。',
      );
    case 'RADIUS_CAP_NOT_BINDING':
      final minutes = _detailInt(effect, 'effective_one_way_minutes');
      if (minutes == null) {
        return null;
      }
      return lalaCopyMulti(
        language,
        ko: '요청한 반경이 이미 이동 시간 선호($minutes분 이내)에 '
            '들어와 그대로 유지했어요.',
        en: 'The requested radius already fits the $minutes-minute one-way '
            'preference, so it was kept as-is.',
        ja: 'リクエストされた範囲はすでに移動時間の設定（$minutes分以内）に'
            '収まっているため、そのまま維持しました。',
        zhHans: '请求的范围已符合单程时间偏好（$minutes 分钟以内），因此保持不变。',
        zhHant: '請求的範圍已符合單程時間偏好（$minutes 分鐘以內），因此維持不變。',
      );
    case 'INDOOR_ORDERING_APPLIED':
      return lalaCopyMulti(
        language,
        ko: '실내/야외 선호에 따라 후보 순서를 조정했어요.',
        en: 'Candidate order was adjusted to match the indoor/outdoor '
            'preference.',
        ja: '屋内・屋外の設定に合わせて候補の並び順を調整しました。',
        zhHans: '已根据室内/室外偏好调整候选顺序。',
        zhHant: '已依據室內/室外偏好調整候選順序。',
      );
    case 'WEATHER_SAFETY_INDOOR_PRIORITY':
      return lalaCopyMulti(
        language,
        ko: '날씨가 좋지 않아 야외 선호보다 실내 후보를 우선 배치했어요.',
        en: 'Weather is bad, so known indoor candidates were prioritized '
            'over the outdoor preference.',
        ja: '天気が悪いため、屋外の設定より屋内の候補を優先しました。',
        zhHans: '天气不佳，因此优先安排室内候选，而非室外偏好。',
        zhHant: '天氣不佳，因此優先安排室內候選，而非室外偏好。',
      );
    case 'INDOOR_ORDERING_NOT_DIRECTIONAL':
      return lalaCopyMulti(
        language,
        ko: '실내/야외 중립 선호라 순서를 바꾸지 않았어요.',
        en: 'The indoor/outdoor preference is neutral, so no ordering was '
            'applied.',
        ja: '屋内・屋外どちらでもよい設定のため、並び順は変更しませんでした。',
        zhHans: '室内/室外偏好为中性，因此未调整顺序。',
        zhHant: '室內/室外偏好為中立，因此未調整順序。',
      );
    case 'INDOOR_ORDERING_NO_CHANGE':
      return lalaCopyMulti(
        language,
        ko: '후보가 이미 선호에 맞는 순서라 바뀐 항목이 없어요.',
        en: 'Candidates were already ordered per the preference, so nothing '
            'changed.',
        ja: '候補はすでに設定どおりの並び順のため、変更はありませんでした。',
        zhHans: '候选顺序已符合偏好，没有变化。',
        zhHant: '候選順序已符合偏好，沒有變動。',
      );
    case 'INDOOR_STATUS_UNAVAILABLE':
      return lalaCopyMulti(
        language,
        ko: '실내/야외 정보가 있는 장소가 없어 순서를 바꾸지 못했어요.',
        en: 'No place carries indoor/outdoor provenance, so no ordering was '
            'possible.',
        ja: '屋内・屋外の情報がある場所がないため、並び順を変更できませんでした。',
        zhHans: '没有地点带有室内/室外信息，因此无法调整顺序。',
        zhHant: '沒有地點帶有室內/室外資訊，因此無法調整順序。',
      );
    case 'CUISINE_FACET_UNAVAILABLE':
      return lalaCopyMulti(
        language,
        ko: '장소 데이터에 요리 정보가 없어 요리 선호를 반영하지 못했어요.',
        en: 'Place data has no cuisine facet, so the cuisine preference was '
            'not applied.',
        ja: '場所データに料理の情報がないため、料理の設定は反映されませんでした。',
        zhHans: '地点数据没有菜系信息，因此未应用菜系偏好。',
        zhHant: '地點資料沒有菜系資訊，因此未套用菜系偏好。',
      );
    case 'PRICE_FACET_UNAVAILABLE':
      return lalaCopyMulti(
        language,
        ko: '장소 데이터에 가격 정보가 없어 예산 선호를 반영하지 못했어요.',
        en: 'Place data has no price facet, so the budget preference was not '
            'applied.',
        ja: '場所データに価格の情報がないため、予算の設定は反映されませんでした。',
        zhHans: '地点数据没有价格信息，因此未应用预算偏好。',
        zhHant: '地點資料沒有價格資訊，因此未套用預算偏好。',
      );
    case 'CLOSING_SOON_FACET_UNAVAILABLE':
      return lalaCopyMulti(
        language,
        ko: '장소 데이터에 마감 임박 정보가 없어 제외 선호를 반영하지 못했어요.',
        en: 'Place data has no closing-soon facet, so the exclusion '
            'preference was not applied.',
        ja: '場所データにまもなく閉店という情報がないため、除外の設定は反映されませんでした。',
        zhHans: '地点数据没有即将打烊信息，因此未应用排除偏好。',
        zhHant: '地點資料沒有即將打烊資訊，因此未套用排除偏好。',
      );
    default:
      return null;
  }
}

int? _detailInt(LalaPlanPreferenceEffect effect, String key) {
  final value = effect.details[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}
