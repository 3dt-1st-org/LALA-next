import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../shared/l10n/lala_copy.dart';
import '../../shared/labels/source_label.dart';
import 'widgets/weather_forecast_chart_painter.dart';

/// 표시 가능한(placeholder 아닌) 날씨만 통과(C3 추출 — main.dart 의 _publicWeatherOrNull).
/// source 가 skeleton/fallback/unavailable 등이면 null 취급한다.
LalaWeather? publicWeatherOrNull(LalaWeather? weather) {
  if (weather == null || isPlaceholderWeatherSource(weather.source)) {
    return null;
  }
  return weather;
}

/// 온도 문자열 표시 포맷터(C3 추출 — main.dart 의 _temperatureLabel).
String temperatureLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '-';
  }
  if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(trimmed)) {
    return '$trimmed°C';
  }
  if (RegExp(r'^-?\d+(\.\d+)?C$').hasMatch(trimmed)) {
    return trimmed.replaceFirst('C', '°C');
  }
  return trimmed;
}

double? _temperatureValue(String value) {
  final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  return double.tryParse(match.group(0)!);
}

/// 예보 아이템으로 차트 점 리스트를 빌드(C3 추출 — main.dart 의 _weatherChartPoints).
List<WeatherChartPoint> buildWeatherChartPoints({
  required List<LalaForecastItem> items,
  required double columnWidth,
  required double chartHeight,
}) {
  final values = items.map((item) => _temperatureValue(item.temp)).toList();
  final validValues = values.whereType<double>().toList(growable: false);
  final maxValue = validValues.isEmpty ? 1.0 : validValues.reduce(math.max);
  final minValue = validValues.isEmpty ? 0.0 : validValues.reduce(math.min);
  final range = math.max(0.1, maxValue - minValue);
  const topPadding = 28.0;
  const bottomPadding = 18.0;
  final drawHeight = math.max(1.0, chartHeight - topPadding - bottomPadding);

  return [
    for (var index = 0; index < items.length; index += 1)
      WeatherChartPoint(
        x: index * columnWidth + columnWidth / 2,
        y:
            topPadding +
            (((maxValue - (values[index] ?? minValue)) / range) * drawHeight),
        label: values[index] == null ? '--' : '${values[index]!.round()}°',
      ),
  ];
}

/// 예보 시각 라벨(C3 추출 — main.dart 의 _weatherChartTimeLabel).
String weatherChartTimeLabel(String raw, {String language = 'ko'}) {
  if (isLalaEnglish(language)) {
    return raw.trim();
  }
  final trimmed = raw.trim();
  final match = RegExp(r'(\d{1,2})(?=:\d{2})').firstMatch(trimmed);
  if (match == null) {
    return trimmed;
  }
  return '${match.group(1)!.padLeft(2, '0')}시';
}

/// 예보 아이콘 매핑(C3 추출 — main.dart 의 _weatherForecastIcon).
IconData weatherForecastIcon(String icon) {
  final normalized = icon.toLowerCase();
  if (normalized.contains('rain') || normalized.contains('shower')) {
    return Icons.water_drop_outlined;
  }
  if (normalized.contains('snow') || normalized.contains('sleet')) {
    return Icons.ac_unit;
  }
  if (normalized.contains('fog') || normalized.contains('dust')) {
    return Icons.blur_on;
  }
  if (normalized.contains('clear') || normalized.contains('sun')) {
    return Icons.wb_sunny_outlined;
  }
  return Icons.wb_cloudy_outlined;
}
