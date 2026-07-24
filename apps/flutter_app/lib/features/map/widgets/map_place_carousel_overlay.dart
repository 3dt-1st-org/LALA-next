import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/labels/source_label.dart';
import '../../place/widgets/map_rail_place_card.dart';
import '../map_helpers.dart';

/// 추천 장소 캐러셀 오버레이(펼침/접힘)(C3 추출 — main.dart 의 _MapPlaceCarouselOverlay).
class MapPlaceCarouselOverlay extends StatelessWidget {
  const MapPlaceCarouselOverlay({
    super.key,
    required this.places,
    required this.source,
    required this.language,
    required this.selectedPlaceId,
    required this.explicitSelectedPlaceId,
    required this.expanded,
    required this.compact,
    required this.onSelectPlace,
    required this.onReselectSelectedPlace,
    required this.onToggleExpanded,
  });

  final List<LalaPlace> places;
  final String? source;
  final String language;
  final String? selectedPlaceId;
  final String? explicitSelectedPlaceId;
  final bool expanded;
  final bool compact;
  final ValueChanged<LalaPlace> onSelectPlace;
  final VoidCallback onReselectSelectedPlace;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final items = railPlaces(places);
    final railHeight = compact ? 126.0 : 150.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.center,
          child: Material(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(999),
            elevation: 0,
            shadowColor: const Color(0x18000000),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onToggleExpanded,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 12,
                      offset: Offset(0, 4),
                      color: Color(0x18000000),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 17,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      expanded
                          ? lalaCopy(language, ko: '추천 장소 접기', en: 'Hide places')
                          : lalaCopy(language, ko: '추천 장소 보기', en: 'Show places'),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: const Color(0xFF374151),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      lalaCopy(
                        language,
                        ko: '${items.length}곳 · ${sourceLabel(source, language: language)}',
                        en: '${items.length} places · ${sourceLabel(source, language: language)}',
                      ),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: expanded
              ? Column(
                  key: const ValueKey('recommendation-rail-expanded'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    SizedBox(
                      key: const ValueKey('recommendation-rail-list'),
                      height: railHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              blurRadius: 18,
                              offset: Offset(0, 8),
                              color: Color(0x16000000),
                            ),
                          ],
                        ),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(6),
                          scrollDirection: Axis.horizontal,
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final place = items[index];
                            final selected =
                                (selectedPlaceId == null && index == 0) ||
                                selectedPlaceId == place.placeId;
                            final explicitlySelected =
                                explicitSelectedPlaceId == place.placeId;
                            return MapRailPlaceCard(
                              place: place,
                              language: language,
                              selected: selected,
                              compact: compact,
                              onTap: explicitlySelected
                                  ? onReselectSelectedPlace
                                  : selected
                                  ? null
                                  : () => onSelectPlace(place),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(
                  key: ValueKey('recommendation-rail-collapsed'),
                ),
        ),
      ],
    );
  }
}
