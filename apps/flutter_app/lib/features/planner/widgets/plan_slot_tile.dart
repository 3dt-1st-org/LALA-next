import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/multi_language_text.dart';
import '../../../shared/l10n/place_labels.dart';
import '../planner_helpers.dart';

/// 일정 슬롯 타일(C3 추출 — main.dart 의 _PlanSlotTile).
class PlanSlotTile extends StatelessWidget {
  const PlanSlotTile({
    super.key,
    required this.slot,
    required this.language,
    required this.onSelectPlace,
    this.swapReason,
  });

  final LalaPlanSlot slot;
  final String language;
  final ValueChanged<LalaPlace> onSelectPlace;

  /// 날씨 교체 사유(P6A §04 Screen 04 swapped 상태). null 이면 일반 표시.
  final String? swapReason;

  @override
  Widget build(BuildContext context) {
    final place = slot.place;
    final periodLabelText = periodLabel(slot.period, language: language);
    final title = place == null
        ? planSlotTitle(slot, language)
        : placeDisplayName(place, language);
    final subtitle = place == null ? null : placeRegionLabel(place, language);
    final weatherHint = singleLanguageText(slot.weatherHint ?? '', language);
    final detail = planSlotDetail(slot, language);
    final travelTimeLabel = planSlotTravelTimeLabel(slot, language);
    final estimatedHoursLabel = planSlotEstimatedHoursLabel(slot, language);
    final indoorOutdoorLabel = slot.indoorOutdoor == null
        ? null
        : (slot.indoorOutdoor == 'indoor'
              ? (language == 'ko' ? '실내' : 'Indoor')
              : (language == 'ko' ? '야외' : 'Outdoor'));
    final metaEntries = <String>[
      ?travelTimeLabel,
      ?estimatedHoursLabel,
    ];
    // 접근성(§13.5): 슬롯 메타(시간대/실내·야외/이동시간/추정시간)를 하나의
    // 시맨틱 라벨로 합쳐 화면 읽기 사용자에게 전달. 색상 단독 신호를 피하기 위해
    // 실내·야외는 아이콘+텍스트+라벨 삼중으로 표현한다.
    final semanticsParts = <String>[
      periodLabelText,
      title,
      ?subtitle,
      ?indoorOutdoorLabel,
      ?weatherHint,
      ...metaEntries,
    ];
    return Semantics(
      container: true,
      button: place != null,
      label: semanticsParts.join(', '),
      child: Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('planner-slot-${place?.placeId ?? slot.period}'),
          borderRadius: BorderRadius.circular(12),
          onTap: place == null ? null : () => onSelectPlace(place),
          // 최소 44dp 터치 타겟 보장(내용이 짧아도 타일 전체 높이 하한선).
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        periodIcon(slot.period),
                        size: 17,
                        color: const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        periodLabelText,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      if (weatherHint != null) ...[
                        const Spacer(),
                        Text(
                          weatherHint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: const Color(0xFF94A3B8),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                      if (slot.indoorOutdoor != null) ...[
                        if (weatherHint == null) const Spacer(),
                        Icon(
                          slot.indoorOutdoor == 'indoor'
                              ? Icons.home_work_outlined
                              : Icons.park_outlined,
                          size: 13,
                          color: slot.indoorOutdoor == 'indoor'
                              ? const Color(0xFF0F766E)
                              : const Color(0xFFC53030),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          indoorOutdoorLabel!,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: slot.indoorOutdoor == 'indoor'
                                    ? const Color(0xFF0F766E)
                                    : const Color(0xFFC53030),
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ],
                  ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF1E293B),
                  fontWeight: FontWeight.w900,
                  height: 1.18,
                ),
              ),
              if (swapReason != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBF4FE),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.swap_horiz,
                        size: 12,
                        color: const Color(0xFF2B6CB0),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          swapReason!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: const Color(0xFF2B6CB0),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (detail != null) ...[
                const SizedBox(height: 6),
                Text(
                  detail,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
              if (metaEntries.isNotEmpty) ...[
                const SizedBox(height: 6),
                Semantics(
                  container: true,
                  label: metaEntries.join(', '),
                  child: Padding(
                    // Keep the meta row clear of the 44dp tap target below/above.
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final entry in metaEntries)
                          _PlanSlotMetaChip(text: entry),
                      ],
                    ),
                  ),
                ),
              ],
              if (place != null) ...[
                const SizedBox(height: 7),
                Align(
                  alignment: Alignment.centerRight,
                  child: Icon(
                    Icons.chevron_right,
                    color: const Color(0xFF94A3B8),
                    size: 20,
                  ),
                ),
              ],
            ],
          ),
        ),
          ),
        ),
      ),
    );
  }
}

/// 일정 슬롯 부가 메타(도보 이동시간 / 추정 운영시간)용 컴팩트 칩.
/// 기존 타일의 slate 토큰(배경/보더/텍스트 색)만 재사용하고 새 토큰을 만들지 않는다.
/// §12.3: 추정 운영시간은 authority 가 아니므로 항상 (추정)/(est.) 마커와 함께 표시.
class _PlanSlotMetaChip extends StatelessWidget {
  const _PlanSlotMetaChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFF475569),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
