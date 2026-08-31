// P6H truthfulness: map bottom dock 의 data-as-of 신선도 라벨 검증.
// - data_as_of present → "데이터 기준: YYYY-MM-DD" 표시(영어: "Data as of: ...").
// - data_as_of null/불파식 → 라벨 부재(honest absence).
// 실제 snapshot generated_at 의 날짜 부분만 사용하고, 값이 없으면 절대 표시하지 않는다.
//
// V1-RC3: 선택 장소 날씨 요약 · 날씨 출처 1줄 바인딩 검증.
// - weather present → summary · source 1줄 표시(publicWeatherSummary SSOT).
// - weather null/placeholder/fallback → 줄 부재(honest omission).
// - D-Src: source 가 '-'(null/빈) 이면 추천 source 칩 생략, 실측 source 는 표시.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/docent/widgets/dock_docent_preview.dart';
import 'package:lala_next_app/features/map/widgets/map_bottom_dock.dart';

const LalaPlace _place = LalaPlace(
  placeId: 'p1',
  name: '행궁동 카페',
  nameKo: '행궁동 카페',
  nameEn: 'Haenggung Cafe',
  category: 'restaurant',
  lat: 37.28,
  lng: 127.01,
  address: '경기도 수원시 팔달구',
  regionKo: '수원',
  regionEn: 'Suwon',
  distanceM: 210,
  source: 'public_mvp_snapshot',
  upstreamSource: 'snapshot',
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

MapBottomDock _dock({
  bool isWide = false,
  String? dataAsOf,
  String uiLanguage = 'ko',
  // 기본은 기존 fixture 동작 보존; D-Src 테스트가 null(production 의 no-live-places)도 주입 가능.
  String? source = 'public_mvp_snapshot',
  LalaWeather? weather,
  bool expanded = true,
  double height = 240,
  VoidCallback? onToggleExpanded,
}) {
  return MapBottomDock(
    isWide: isWide,
    places: const <LalaPlace>[_place],
    source: source,
    weather: weather,
    dataAsOf: dataAsOf,
    topPlace: _place,
    uiLanguage: uiLanguage,
    height: height,
    expanded: expanded,
    docentScript: null,
    docentAudio: null,
    docentAction: null,
    audioLoading: false,
    audioError: null,
    canFetchAudio: false,
    showEvidence: false,
    error: null,
    placeFailureKind: null,
    recommendationRecoveryPending: false,
    onFetchAudio: () {},
    onAddToPlan: () {},
    onOpenDetail: () {},
    onRefresh: () {},
    onToggleEvidence: () {},
    onToggleExpanded: onToggleExpanded,
  );
}

void main() {
  testWidgets(
    'freshness label shows the snapshot date when dataAsOf is present',
    (tester) async {
      await tester.pumpWidget(
        _wrap(_dock(dataAsOf: '2026-06-19T02:24:44.557686+00:00')),
      );
      await tester.pump();

      // 날짜 부분(YYYY-MM-DD)만 표시.
      expect(find.text('데이터 기준: 2026-06-19'), findsOneWidget);
    },
  );

  testWidgets(
    'freshness label is absent when dataAsOf is null (honest absence)',
    (tester) async {
      await tester.pumpWidget(_wrap(_dock(dataAsOf: null)));
      await tester.pump();

      expect(find.textContaining('데이터 기준'), findsNothing);
    },
  );

  testWidgets(
    'freshness label is absent when dataAsOf is not a parseable date',
    (tester) async {
      await tester.pumpWidget(_wrap(_dock(dataAsOf: 'not-a-date')));
      await tester.pump();

      expect(find.textContaining('데이터 기준'), findsNothing);
    },
  );

  testWidgets('english freshness label is exclusive (no Korean mixed in)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _dock(dataAsOf: '2026-06-19T02:24:44.557686+00:00', uiLanguage: 'en'),
      ),
    );
    await tester.pump();

    expect(find.text('Data as of: 2026-06-19'), findsOneWidget);
    // KO·EN 배타: 한국어 라벨이 섞이지 않는다.
    expect(find.textContaining('데이터 기준'), findsNothing);
  });

  // V1-RC3: 날씨 요약 · 날씨 출처 1줄 바인딩(publicWeatherSummary SSOT).
  group('weather source line (V1-RC3)', () {
    testWidgets('weather present → summary · source 한 줄 표시', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _dock(
            weather: _weather(temp: '23', source: 'kma_ultra_srt_ncst'),
          ),
        ),
      );
      await tester.pump();

      // 요약(outdoor · temp · dust)과 날씨 출처가 같은 1줄 Text 에 함께 있다.
      expect(find.textContaining('23°C'), findsOneWidget);
      expect(find.textContaining('기상청 실황'), findsOneWidget);
      expect(find.textContaining('PM10 30 보통'), findsOneWidget);
    });

    testWidgets('weather null → 날씨 줄 부재(honest omission)', (tester) async {
      await tester.pumpWidget(_wrap(_dock(weather: null)));
      await tester.pump();

      expect(find.textContaining('기상청 실황'), findsNothing);
      expect(find.textContaining('23°C'), findsNothing);
      expect(find.textContaining('PM10'), findsNothing);
    });

    testWidgets('placeholder/fallback source → gate 통과 못함 → 날씨 줄 부재(조작 없음)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _dock(
            weather: _weather(temp: '23', source: 'fallback'),
          ),
        ),
      );
      await tester.pump();

      // publicWeatherOrNull 이 fallback 을 null 처리 → 줄이 렌더되지 않는다.
      expect(find.textContaining('기상청 실황'), findsNothing);
      expect(find.textContaining('23°C'), findsNothing);
    });
  });

  // V1-RC3(D-Src): 추천 source 칩의 '-'(null/빤 source) 가드. 독·상세가 bare '-' 대신
  // 정직한 부재로 일치.
  group('recommendation source chip guard (D-Src, V1-RC3)', () {
    testWidgets('실측 source(db) → 추천 source 칩 표시', (tester) async {
      await tester.pumpWidget(_wrap(_dock(source: 'db')));
      await tester.pump();

      expect(find.text('실시간 추천'), findsOneWidget);
    });

    testWidgets('null source → sourceLabel 이 "-" → 칩 생략(bare "-" 없음)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_dock(source: null)));
      await tester.pump();

      expect(find.text('실시간 추천'), findsNothing);
      expect(find.text('-'), findsNothing);
    });
  });

  group('collapsed place summary (B2 slim map-space option)', () {
    testWidgets('starts at 84dp and keeps only the essential place identity', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 393,
            child: _dock(
              expanded: false,
              height: MapBottomDock.mobileCollapsedHeight,
              weather: _weather(temp: '23', source: 'kma_ultra_srt_ncst'),
              dataAsOf: '2026-06-19T02:24:44.557686+00:00',
              onToggleExpanded: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSize(find.byKey(const ValueKey('map-bottom-dock'))).height,
        MapBottomDock.mobileCollapsedHeight,
      );
      expect(find.text('행궁동 카페'), findsOneWidget);
      expect(find.text('210m'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('map-dock-expand-toggle')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('map-dock-expand-toggle')))
            .height,
        greaterThanOrEqualTo(44),
      );
      expect(find.textContaining('데이터 기준'), findsNothing);
      expect(find.textContaining('PM10'), findsNothing);
      expect(find.byType(DockDocentPreview), findsNothing);
    });

    testWidgets('tap and upward swipe both request expansion', (tester) async {
      var toggleCount = 0;
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 393,
            child: _dock(
              expanded: false,
              height: MapBottomDock.mobileCollapsedHeight,
              onToggleExpanded: () => toggleCount += 1,
            ),
          ),
        ),
      );
      await tester.pump();

      final toggle = find.byKey(const ValueKey('map-dock-expand-toggle'));
      await tester.tap(toggle);
      expect(toggleCount, 1);

      await tester.fling(toggle, const Offset(0, -80), 800);
      await tester.pump();
      expect(toggleCount, 2);
    });

    testWidgets('wide dock stays expanded without a no-op collapse control', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 1024,
            child: _dock(isWide: true, onToggleExpanded: () {}),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('행궁동 카페'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('map-dock-collapse-toggle')),
        findsNothing,
      );
    });
  });
}

LalaWeather _weather({
  required String temp,
  required String source,
  String outdoorStatus = 'normal',
  LalaDust? dust,
}) {
  return LalaWeather(
    lat: 37.2636,
    lng: 127.0286,
    temp: temp,
    icon: 'partly-cloudy',
    dust: dust ?? _dust(),
    forecast: const <LalaForecastItem>[],
    outdoorStatus: outdoorStatus,
    force: false,
    source: source,
    location: 'Suwon',
    recordTime: '2026-07-24T09:00:00+09:00',
    locationMatch: true,
  );
}

LalaDust _dust({
  String pm10 = '30',
  String pm25 = '25',
  String grade = 'normal',
  String gradeKo = '보통',
  String pm10Grade = 'normal',
  String pm10GradeKo = '보통',
  String pm25Grade = 'good',
  String pm25GradeKo = '좋음',
}) {
  return LalaDust(
    pm10: pm10,
    pm25: pm25,
    grade: grade,
    gradeKo: gradeKo,
    pm10Grade: pm10Grade,
    pm10GradeKo: pm10GradeKo,
    pm25Grade: pm25Grade,
    pm25GradeKo: pm25GradeKo,
  );
}
