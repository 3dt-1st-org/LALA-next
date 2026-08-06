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
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('planner-slot-${place?.placeId ?? slot.period}'),
        borderRadius: BorderRadius.circular(12),
        onTap: place == null ? null : () => onSelectPlace(place),
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
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
                      slot.indoorOutdoor == 'indoor'
                          ? (language == 'ko' ? '실내' : 'Indoor')
                          : (language == 'ko' ? '야외' : 'Outdoor'),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
    );
  }
}
