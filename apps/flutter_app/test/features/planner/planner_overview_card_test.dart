// P1: 일정 개요 카드 검증(loaded plan 과 동일 입력).
// - 빈 온도: 독립 '-' 칩이 없고, PM 칩·야외·일정 수는 유지.
// - 온도가 있으면 기존대로 온도 칩 노출(기존 동작 유지).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/planner/widgets/planner_overview_card.dart';

void main() {
  testWidgets('빈 온도는 "-" 칩 없이 PM·야외·일정 수 유지', (tester) async {
    await tester.pumpWidget(
      _host(
        PlannerOverviewCard(
          language: 'ko',
          weather: _weather(temp: ''),
          dailyPlan: null,
          visibleSlotCount: 1,
          loading: false,
          onRegenerate: () {},
        ),
      ),
    );
    // 독립 '-' 칩이 없어야 한다.
    expect(find.text('-'), findsNothing);
    // PM 칩은 그대로.
    expect(find.text('PM10 41 보통'), findsOneWidget);
    expect(find.text('PM2.5 18 보통'), findsOneWidget);
    // 야외 상태 + 일정 수.
    expect(find.text('좋음'), findsOneWidget);
    expect(find.text('1개 일정'), findsOneWidget);
  });

  testWidgets('온도가 있으면 온도 칩 노출(기존 동작 유지)', (tester) async {
    await tester.pumpWidget(
      _host(
        PlannerOverviewCard(
          language: 'ko',
          weather: _weather(temp: '14°C'),
          dailyPlan: null,
          visibleSlotCount: 1,
          loading: false,
          onRegenerate: () {},
        ),
      ),
    );
    expect(find.text('14°C'), findsOneWidget);
    expect(find.text('-'), findsNothing);
  });
}

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SafeArea(child: child)));

LalaWeather _weather({required String temp}) {
  return LalaWeather(
    lat: 37.2636,
    lng: 127.0286,
    temp: temp,
    icon: 'partly-cloudy',
    dust: const LalaDust(
      pm10: '41',
      pm25: '18',
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
