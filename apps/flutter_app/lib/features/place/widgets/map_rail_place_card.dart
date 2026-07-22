import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/place_labels.dart';
import '../../../shared/widgets/tiny_meta.dart';
import '../place_helpers.dart';
import 'rail_category_badge.dart';
import 'rail_place_thumb.dart';

/// 지도 레일용 장소 카드(C3 추출 — main.dart 의 _MapRailPlaceCard).
class MapRailPlaceCard extends StatelessWidget {
  const MapRailPlaceCard({
    super.key,
    required this.place,
    required this.language,
    required this.selected,
    required this.compact,
    this.onTap,
  });

  final LalaPlace place;
  final String language;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(place.category);
    final hasImage = hasOfficialPlaceImage(place);
    final cardWidth = compact
        ? (hasImage ? 226.0 : 198.0)
        : (hasImage ? 252.0 : 222.0);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: ValueKey('tour-stop-action-${place.placeId}'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          key: ValueKey('map-rail-place-card-${place.placeId}'),
          width: cardWidth,
          padding: selected ? const EdgeInsets.all(3) : EdgeInsets.zero,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: selected ? color : Colors.white.withValues(alpha: 0.93),
            border: Border.all(
              color: selected ? color : const Color(0xFFE2E8F0),
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      blurRadius: 16,
                      offset: Offset(0, 7),
                      color: Color(0x240F172A),
                    ),
                  ]
                : null,
          ),
          child: Container(
            key: selected ? ValueKey('category-border-${place.placeId}') : null,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 7 : 8,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: selected ? 0.98 : 0.93),
              borderRadius: BorderRadius.circular(selected ? 15 : 18),
              border: selected
                  ? Border.all(color: color.withValues(alpha: 0.18))
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        placeDisplayName(place, language),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: selected ? color : const Color(0xFF111827),
                          fontWeight: FontWeight.w900,
                          height: 1.12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      RailCategoryBadge(place: place, language: language),
                      const SizedBox(height: 5),
                      Row(
                        key: ValueKey('rail-place-region-${place.placeId}'),
                        children: [
                          const Icon(
                            Icons.place_outlined,
                            size: 13,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              placeRegionLabel(place, language),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: const Color(0xFF64748B),
                                    fontWeight: FontWeight.w700,
                                    height: 1.05,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (place.distanceM > 0)
                            TinyMeta('${place.distanceM}m'),
                        ],
                      ),
                    ],
                  ),
                ),
                if (hasImage) ...[
                  SizedBox(width: compact ? 8 : 10),
                  RailPlaceThumb(place: place, compact: compact),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
