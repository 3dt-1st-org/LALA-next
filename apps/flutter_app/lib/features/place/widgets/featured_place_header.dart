import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/l10n/multi_language_text.dart';
import '../../../shared/l10n/place_labels.dart';
import '../../../shared/widgets/inline_icon_text.dart';
import '../place_helpers.dart';
import 'category_badge.dart';
import 'place_image.dart';

/// 추천 장소 상세 헤더(C3 추출 — main.dart 의 _FeaturedPlaceHeader).
class FeaturedPlaceHeader extends StatelessWidget {
  const FeaturedPlaceHeader({
    super.key,
    required this.place,
    required this.language,
    required this.showEvidence,
    required this.saved,
    required this.onToggleSaved,
  });

  final LalaPlace place;
  final String language;
  final bool showEvidence;
  final bool saved;
  final VoidCallback onToggleSaved;

  @override
  Widget build(BuildContext context) {
    final score = place.score?.percent ?? 86;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasOfficialPlaceImage(place)) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              key: const ValueKey('detail-place-hero-image'),
              height: 170,
              child: PlaceImage(
                place: place,
                width: double.infinity,
                height: 170,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CategoryBadge(category: place.category, language: language),
                  const SizedBox(height: 7),
                  Text(
                    placeDisplayName(place, language),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF111827),
                      height: 1.08,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: saved
                  ? lalaCopy(language, ko: '저장됨', en: 'Saved')
                  : lalaCopy(language, ko: '저장', en: 'Save'),
              onPressed: onToggleSaved,
              color: saved ? const Color(0xFFC53030) : const Color(0xFF64748B),
              icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
            ),
          ],
        ),
        const SizedBox(height: 8),
        InlineIconText(
          icon: Icons.place_outlined,
          label: placeRegionLabel(place, language),
        ),
        if (place.address.trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          InlineIconText(
            icon: Icons.map_outlined,
            label:
                singleLanguageText(place.address, language) ??
                placeRegionLabel(place, language),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            InlineIconText(
              icon: Icons.directions_walk,
              label: '${place.distanceM}m',
            ),
            if (!showEvidence)
              InlineIconText(
                icon: Icons.explore_outlined,
                label: lalaCopy(language, ko: '로컬 추천', en: 'Local pick'),
              ),
            if (showEvidence) ...[
              Text(
                lalaCopy(language, ko: '로컬 점수', en: 'Local score'),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF1A202C),
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '$score',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFFC53030),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                '/100',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
