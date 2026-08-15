import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/multi_language_text.dart';
import '../../../shared/l10n/place_labels.dart';
import '../place_helpers.dart';
import 'category_badge.dart';
import 'place_reason_freshness.dart';
import 'place_thumb.dart';

/// 추천 장소 가로 카드(C3 추출 — main.dart 의 _RecommendedPlaceCard).
class RecommendedPlaceCard extends StatelessWidget {
  const RecommendedPlaceCard({
    super.key,
    required this.place,
    required this.selected,
    this.language = 'ko',
  });

  final LalaPlace place;
  final bool selected;
  final String language;

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(place.category);
    final hasImage = hasOfficialPlaceImage(place);
    final freshness = placeFreshnessText(place);
    return Container(
      key: ValueKey('recommended-place-card-${place.placeId}'),
      width: hasImage ? 270 : 232,
      padding: EdgeInsets.all(hasImage ? 14 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? color : const Color(0xFFE2E8F0),
          width: selected ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 16,
            offset: Offset(0, 8),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    CategoryBadge(category: place.category, language: language),
                    const SizedBox(width: 8),
                    Text(
                      '${place.distanceM}m',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    if (freshness != null) ...[
                      const SizedBox(width: 8),
                      // V1-RC §13.5: freshness 는 가변 폭 후미 세그먼트 — Flexible+ellipsis
                      // 로 메타 Row overflow 를 흡수(카테고리/거리는 고정 폭, 신선도가 먼저 잘린다).
                      Flexible(
                        child: Text(
                          freshness,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  placeDisplayName(place, language),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  // V6 §6: 번역 없는 정적 데이터(주소/지역)는 영문 폴백 + 고지 배지.
                  placeNameUsesEnglishFallback(place, language)
                      ? '${_placeCardSubtitle(place, language)} · '
                            '${englishFallbackDisclosureLabel(language)}'
                      : _placeCardSubtitle(place, language),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475569),
                  ),
                ),
                // V1-RC2: per-place reason(없으면 PlaceReasonLine 이 렌더 생략).
                PlaceReasonLine(place: place, topSpacing: 6),
              ],
            ),
          ),
          if (hasImage) ...[
            const SizedBox(width: 10),
            PlaceThumb(place: place),
          ],
        ],
      ),
    );
  }

  Color _categoryColor(String category) {
    return switch (category) {
      'attraction' => const Color(0xFFC53030),
      'restaurant' => const Color(0xFFF5C842),
      'event' => const Color(0xFF2B6CB0),
      'culture_venue' => const Color(0xFF0F766E),
      _ => const Color(0xFF1A202C),
    };
  }

  String _placeCardSubtitle(LalaPlace place, String language) {
    final address = singleLanguageText(place.address, language);
    if (address != null) {
      return address;
    }
    return placeRegionLabel(place, language);
  }
}
