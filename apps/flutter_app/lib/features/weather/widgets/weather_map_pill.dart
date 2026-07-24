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
        lalaCopy(language, ko: '날씨 데이터 준비 중', en: 'Weather pending');
    final String label;
    if (data == null) {
      label = pending;
    } else {
      final temp = temperatureLabelOrNull(data.temp);
      if (temp == null) {
        // P1: 온도가 비어있으면 의미 있는 먼지 수치(PM)로만 구성.
        // PM 마저 없으면 선행/후행 구분자·'-' 없이 중립 대기 문구로.
        final hasPm = data.dust.pm10.trim().isNotEmpty ||
            data.dust.pm25.trim().isNotEmpty;
        final dust = hasPm
            ? weatherPillDustLabel(data.dust, language).trim()
            : '';
        label = dust.isEmpty ? pending : dust;
      } else {
        label = '$temp · ${weatherPillDustLabel(data.dust, language)}';
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
