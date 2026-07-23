import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../app/lala_metrics.dart';
import '../../../shared/l10n/place_labels.dart';
import '../../../shared/widgets/tiny_meta.dart';
import '../place_helpers.dart';
import 'rail_category_badge.dart';
import 'rail_place_thumb.dart';

/// 지도 레일용 장소 카드.
/// 사진 비중을 높이고, 선택 시 카테고리색 단일 테두리 1개만(이중 테두리 ❌).
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
      borderRadius: BorderRadius.circular(LalaMetrics.cardRadius),
      child: InkWell(
        key: ValueKey('tour-stop-action-${place.placeId}'),
        borderRadius: BorderRadius.circular(LalaMetrics.cardRadius),
        onTap: onTap,
        child: Container(
          key: ValueKey('map-rail-place-card-${place.placeId}'),
          width: cardWidth,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 7 : 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LalaMetrics.cardRadius),
            color: Colors.white.withValues(alpha: 0.96),
            border: Border.all(
              color: selected ? color : const Color(0xFFE2E8F0),
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? <BoxShadow>[
                    BoxShadow(
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                      color: color.withValues(alpha: 0.18),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
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
                      children: <Widget>[
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
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
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
                      children: <Widget>[
                        if (place.distanceM > 0)
                          TinyMeta('${place.distanceM}m'),
                      ],
                    ),
                  ],
                ),
              ),
              if (hasImage) ...<Widget>[
                SizedBox(width: compact ? 8 : 10),
                RailPlaceThumb(place: place, compact: compact),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
