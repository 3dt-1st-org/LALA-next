import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/labels/source_label.dart';
import '../../../shared/widgets/inline_meta.dart';
import 'empty_place_state.dart';
import 'recommended_place_card.dart';

/// 추천 장소 가로 레일(C3 추출 — main.dart 의 _PlaceRail).
class PlaceRail extends StatelessWidget {
  const PlaceRail({
    super.key,
    required this.places,
    required this.source,
    required this.language,
  });

  final List<LalaPlace> places;
  final String? source;
  final String language;

  @override
  Widget build(BuildContext context) {
    final items = places.isEmpty
        ? const <LalaPlace>[]
        : places.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.expand_less, size: 18),
            const SizedBox(width: 6),
            Text(
              lalaCopyMulti(
                language,
                ko: '추천 장소',
                en: 'Recommended places',
                ja: 'おすすめスポット',
                zhHans: '推荐地点',
                zhHant: '推薦地點',
              ),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const Spacer(),
            InlineMeta(
              lalaCopyMulti(
                language,
                ko: '${items.length}곳 · ${sourceLabel(source, language: language)}',
                en: '${items.length} places · ${sourceLabel(source, language: language)}',
                ja: '${items.length}か所 · ${sourceLabel(source, language: language)}',
                zhHans:
                    '${items.length} 个地点 · ${sourceLabel(source, language: language)}',
                zhHant:
                    '${items.length} 個地點 · ${sourceLabel(source, language: language)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          EmptyPlaceState(language: language)
        else
          SizedBox(
            height: 164,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => RecommendedPlaceCard(
                place: items[index],
                selected: index == 0,
                language: language,
              ),
            ),
          ),
      ],
    );
  }
}
