import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/labels/dust_label.dart';
import '../../../shared/widgets/small_status_pill.dart';
import '../weather_helpers.dart';

/// 지도 위 날씨 알림 Pill(C3 추출 — main.dart 의 _WeatherMapPill).
class WeatherMapPill extends StatelessWidget {
  const WeatherMapPill({
    super.key,
    required this.weather,
    required this.language,
    required this.onPressed,
  });

  final LalaWeather? weather;
  final String language;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final data = publicWeatherOrNull(weather);
    final pending =
        lalaCopyMulti(
      language,
      ko: '날씨 데이터 준비 중',
      en: 'Weather pending',
      ja: '気象データ準備中',
      zhHans: '天气数据准备中',
      zhHant: '天氣資料準備中',
    );
    final String label;
    if (data == null) {
      label = pending;
    } else {
      final temp = temperatureLabelOrNull(data.temp);
      final hasPm = data.dust.pm10.trim().isNotEmpty ||
          data.dust.pm25.trim().isNotEmpty;
      final airQuality = hasPm ? dustLabel(data.dust, language).trim() : '';
      final airLabel = airQuality.isEmpty
          ? ''
          : lalaCopyMulti(
              language,
              ko: '공기 $airQuality',
              en: 'Air $airQuality',
              ja: '大気 $airQuality',
              zhHans: '空气 $airQuality',
              zhHant: '空氣 $airQuality',
            );
      if (temp == null) {
        label = airLabel.isEmpty ? pending : airLabel;
      } else {
        // This is a constrained map control. Keep the full PM10/PM2.5 values
        // in the weather sheet instead of ellipsizing them in the quick status.
        label = airLabel.isEmpty ? temp : '$temp · $airLabel';
      }
    }
    return SmallStatusPill(
      key: const ValueKey('weather-pill-hit-target'),
      icon: Icons.thermostat,
      label: label,
      active: true,
      maxWidth: 202,
      maxLines: 2,
      onPressed: onPressed,
    );
  }
}
