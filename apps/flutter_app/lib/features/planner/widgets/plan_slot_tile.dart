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
  });

  final LalaPlanSlot slot;
  final String language;
  final ValueChanged<LalaPlace> onSelectPlace;

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
