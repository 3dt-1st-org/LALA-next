// C3 최종: main.dart 에서 이관. 본문 불변(이동만).
import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/home/home_view_helpers.dart';
import 'package:lala_next_app/features/place/widgets/context_fact_chip.dart';

class PlaceContextCard extends StatelessWidget {
  const PlaceContextCard({super.key,
    required this.place,
    required this.language,
    required this.weather,
    required this.showEvidence,
  });

  final LalaPlace place;
  final String language;
  final LalaWeather? weather;
  final bool showEvidence;

  @override
  Widget build(BuildContext context) {
    final facts = placeContextFacts(
      place: place,
      language: language,
      weather: weather,
      includeEvidence: showEvidence,
    );
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FB),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  placeContextIcon(place.category),
                  color: const Color(0xFF2B6CB0),
                  size: 19,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  placeContextTitle(place.category, language),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: facts
                .map(
                  (fact) =>
                      ContextFactChip(icon: fact.icon, label: fact.label),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}
