// C3 최종: main.dart 에서 이관. 본문 불변(이동만).
import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/home/home_view_helpers.dart';
import 'package:lala_next_app/features/place/widgets/proof_chip.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

class PublicDataProofRow extends StatelessWidget {
  const PublicDataProofRow({super.key,
    required this.place,
    required this.language,
    required this.source,
    required this.weather,
    required this.score,
  });

  final LalaPlace place;
  final String language;
  final String? source;
  final LalaWeather? weather;
  final LalaPlaceScore? score;

  @override
  Widget build(BuildContext context) {
    final labels = proofSourceLabels(
      place: place,
      language: language,
      source: source,
      weather: weather,
      score: score,
    );
    final title =
        hasFallbackProofSource(
          place: place,
          source: source,
          weather: weather,
          score: score,
        )
        ? lalaCopy(language, ko: '제한적 데이터 근거', en: 'Limited data evidence')
        : lalaCopy(language, ko: '공식 데이터 근거', en: 'Official data evidence');
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w900,
            ),
          ),
          ...labels.map((label) => ProofChip(label: label)),
        ],
      ),
    );
  }
}
