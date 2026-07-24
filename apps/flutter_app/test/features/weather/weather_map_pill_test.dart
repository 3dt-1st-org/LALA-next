// P1: 지도 날씨 Pill 검증.
// - 라이브 날씨 + 빈 온도 + PM 수치 → PM 만(선행/후행 구분자·'-' 없음).
// - 라이브 날씨 + 빈 온도 + 유의미 PM 없음 → 중립 대기 문구.
// - 온도가 있으면 기존대로 '온도 · 먼지' (기존 동작 유지).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/weather/widgets/weather_map_pill.dart';
import 'package:lala_next_app/shared/widgets/small_status_pill.dart';

void main() {
  testWidgets('빈 온도 + PM 수치면 PM 만 노출(구분자/대시 없음)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeatherMapPill(
          weather: _weather(temp: '', withPm: true),
          language: 'ko',
          onPressed: () {},
        ),
      ),
    );
    final label = _pillLabel(tester);
    expect(label, 'PM10 41 보통 · PM2.5 18 보통');
    expect(label.startsWith('-'), isFalse);
    expect(label.startsWith('·'), isFalse);
    expect(label.endsWith('·'), isFalse);
    expect(label.contains('- ·'), isFalse);
  });

  testWidgets('빈 온도 + 유의미 PM 없으면 중립 대기 문구', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeatherMapPill(
          weather: _weather(temp: '', withPm: false),
          language: 'ko',
          onPressed: () {},
        ),
      ),
    );
    expect(_pillLabel(tester), '날씨 데이터 준비 중');
  });

  testWidgets('온도가 있으면 기존대로 온도·먼지 결합(기존 동작 유지)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeatherMapPill(
          weather: _weather(temp: '14°C', withPm: true),
          language: 'ko',
          onPressed: () {},
        ),
      ),
    );
    expect(_pillLabel(tester), '14°C · PM10 41 보통 · PM2.5 18 보통');
  });

  testWidgets('날씨 없음(null)은 대기 문구', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeatherMapPill(
          weather: null,
          language: 'ko',
          onPressed: () {},
        ),
      ),
    );
    expect(_pillLabel(tester), '날씨 데이터 준비 중');
  });
}

String _pillLabel(WidgetTester tester) {
  return tester.widget<SmallStatusPill>(find.byType(SmallStatusPill)).label;
}

LalaWeather _weather({required String temp, required bool withPm}) {
  return LalaWeather(
    lat: 37.2636,
    lng: 127.0286,
    temp: temp,
    icon: 'partly-cloudy',
    dust: LalaDust(
      pm10: withPm ? '41' : '',
      pm25: withPm ? '18' : '',
      grade: 'normal',
      gradeKo: '보통',
      pm10Grade: 'normal',
      pm10GradeKo: '보통',
      pm25Grade: 'normal',
      pm25GradeKo: '보통',
    ),
    forecast: const <LalaForecastItem>[],
    outdoorStatus: 'good',
    force: false,
    source: 'live',
    location: 'Suwon',
    recordTime: '2026-07-24T09:00:00+09:00',
    locationMatch: true,
  );
}
