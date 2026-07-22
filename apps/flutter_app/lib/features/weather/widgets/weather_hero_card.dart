import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/place_labels.dart';
import '../../../shared/labels/source_label.dart';
import '../../place/widgets/proof_chip.dart';
import '../weather_helpers.dart';

/// 날씨 히어로 카드(C3 추출 — main.dart 의 _WeatherHeroCard).
class WeatherHeroCard extends StatelessWidget {
  const WeatherHeroCard({super.key, required this.weather, required this.language});

  final LalaWeather weather;
  final String language;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wb_cloudy_outlined,
            size: 42,
            color: Color(0xFF2B6CB0),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  locationLabel(weather.location, language),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  temperatureLabel(weather.temp),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          ProofChip(
            key: const ValueKey('weather-source-chip'),
            label: weatherSourceLabel(weather.source, language: language),
          ),
        ],
      ),
    );
  }
}
