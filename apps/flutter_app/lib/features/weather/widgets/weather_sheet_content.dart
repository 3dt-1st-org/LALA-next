import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/l10n/place_labels.dart';
import '../../../shared/labels/dust_label.dart';
import '../weather_helpers.dart';
import 'forecast_chip.dart';
import 'weather_fact.dart';
import 'weather_forecast_chart_card.dart';
import 'weather_hero_card.dart';
import 'weather_unavailable_card.dart';

/// 날씨 시트 본문(C3 추출 — main.dart 의 _WeatherSheetContent).
class WeatherSheetContent extends StatelessWidget {
  const WeatherSheetContent({super.key, required this.language, required this.weather});

  final String language;
  final LalaWeather? weather;

  @override
  Widget build(BuildContext context) {
    final data = publicWeatherOrNull(weather);
    if (data == null) {
      return WeatherUnavailableCard(language: language);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WeatherHeroCard(weather: data, language: language),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            WeatherFact(
              label: lalaCopy(language, ko: '통합 대기', en: 'Air quality'),
              value: dustLabel(data.dust, language),
            ),
            WeatherFact(
              label: lalaCopy(language, ko: '미세먼지(PM10)', en: 'PM10'),
              value: dustPollutantValueLabel(
                value: data.dust.pm10,
                grade: dustPollutantGradeLabel(data.dust, 'pm10', language),
                language: language,
              ),
            ),
            WeatherFact(
              label: lalaCopy(language, ko: '초미세먼지(PM2.5)', en: 'PM2.5'),
              value: dustPollutantValueLabel(
                value: data.dust.pm25,
                grade: dustPollutantGradeLabel(data.dust, 'pm25', language),
                language: language,
              ),
            ),
            WeatherFact(
              label: lalaCopy(language, ko: '야외 상태', en: 'Outdoor'),
              value: outdoorLabel(data.outdoorStatus, language: language),
            ),
          ],
        ),
        if (data.forecast.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            lalaCopy(language, ko: '날씨 추이', en: 'Forecast trend'),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          WeatherForecastChartCard(items: data.forecast, language: language),
          const SizedBox(height: 10),
          SizedBox(
            height: 82,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: data.forecast.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = data.forecast[index];
                return ForecastChip(item: item, language: language);
              },
            ),
          ),
        ],
      ],
    );
  }
}
