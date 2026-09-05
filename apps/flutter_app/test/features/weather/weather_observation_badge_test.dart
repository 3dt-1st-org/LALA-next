// S-14 날씨 관측 시각 배지 위젯 검증 + WeatherSheetContent 통합 검증.
// - valid fresh / stale(날짜 포함 라벨) / null / malformed / future-skew 렌더링.
// - '방금 전'류 상대 나이 문구를 절대 노출하지 않는다.
// - 5개 로케일(ko/en/ja/zh-Hans/zh-Hant) 렌더링.
// - 스크린 리더 semantics(label 결합) 존재.
// - 320dp 폭 / TextScaler.linear(2) 에서 overflow 없음(배지 단독 + 시트 통합).
// - 기존 unavailable 동작 보존: placeholder 날씨는 여전히 unavailable 카드만.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/weather/widgets/weather_observation_badge.dart';
import 'package:lala_next_app/features/weather/widgets/weather_sheet_content.dart';

void main() {
  // 파싱 성공 케이스는 고정된 'now-상대' 관측 시각을 쓴다(라벨은 record_time
  // 자체에서만 유도되므로 결정적). stale 경계 판정은 헬퍼 단위 테스트가 담당.
  final freshRecordTime = DateTime.now()
      .subtract(const Duration(minutes: 30))
      .toUtc()
      .toIso8601String();

  Future<void> pumpBadge(
    WidgetTester tester, {
    String? recordTime,
    String language = 'ko',
    TextScaler textScaler = TextScaler.noScaling,
    Size size = const Size(402, 874),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: ListView(
              children: [
                WeatherObservationBadge(
                  recordTime: recordTime,
                  language: language,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('valid fresh 관측: 시각 + 최신 관측 칩', (tester) async {
    await pumpBadge(tester, recordTime: freshRecordTime);
    expect(find.byKey(const ValueKey('weather-observed-time')), findsOneWidget);
    expect(find.text('최신 관측'), findsOneWidget);
    // '관측 시각 HH:mm' 패턴 노출(상대 나이 문구 아님).
    expect(find.textContaining(RegExp(r'^관측 시각 \d{2}:\d{2}$')), findsOneWidget);
    expect(find.textContaining('방금'), findsNothing);
  });

  testWidgets('stale 관측(고정 과거일): 날짜 포함 라벨 + 이전 관측값 칩', (tester) async {
    await pumpBadge(tester, recordTime: '2026-09-04T23:00:00+09:00');
    expect(find.text('관측 시각 2026-09-04 23:00'), findsOneWidget);
    expect(find.text('이전 관측값'), findsOneWidget);
    expect(find.text('최신 관측'), findsNothing);
  });

  testWidgets('dataTime 비-타임존 형식(KST 해석)도 시트에 그대로 반영', (tester) async {
    await pumpBadge(tester, recordTime: '2026-09-04 23:00');
    expect(find.text('관측 시각 2026-09-04 23:00'), findsOneWidget);
    expect(find.text('이전 관측값'), findsOneWidget);
  });

  testWidgets('null 관측 시각: 정직한 미확인 문구, 상태 칩 없음, 방금 전 금지', (tester) async {
    await pumpBadge(tester, recordTime: null);
    expect(find.text('관측 시각 확인 중'), findsOneWidget);
    expect(find.text('최신 관측'), findsNothing);
    expect(find.text('이전 관측값'), findsNothing);
    expect(find.textContaining('방금'), findsNothing);
  });

  testWidgets('망가진 관측 시각: 예외 없이 정직한 미확인 문구', (tester) async {
    await pumpBadge(tester, recordTime: 'not-a-timestamp');
    expect(tester.takeException(), isNull);
    expect(find.text('관측 시각 확인 중'), findsOneWidget);
  });

  testWidgets('미래 skew 관측: 나이를 발명하지 않고 미확인 문구', (tester) async {
    final future = DateTime.now()
        .add(const Duration(minutes: 30))
        .toIso8601String();
    await pumpBadge(tester, recordTime: future);
    expect(find.text('관측 시각 확인 중'), findsOneWidget);
    expect(find.textContaining('방금'), findsNothing);
    expect(find.textContaining('후'), findsNothing);
  });

  testWidgets('5개 로케일 모두 관측 라벨 + 상태를 렌더링(한국어 누출 없음)', (tester) async {
    final expectations = <String, (String, String)>{
      'ko': ('관측 시각 2026-09-04 23:00', '이전 관측값'),
      'en': ('Observed 2026-09-04 23:00', 'Earlier observation'),
      'ja': ('観測時刻 2026-09-04 23:00', '以前の観測'),
      'zh-Hans': ('观测时间 2026-09-04 23:00', '较早观测'),
      'zh-Hant': ('觀測時間 2026-09-04 23:00', '較早觀測'),
    };
    for (final entry in expectations.entries) {
      await pumpBadge(
        tester,
        recordTime: '2026-09-04T23:00:00+09:00',
        language: entry.key,
      );
      expect(find.text(entry.value.$1), findsOneWidget, reason: entry.key);
      expect(find.text(entry.value.$2), findsOneWidget, reason: entry.key);
    }
  });

  testWidgets('미확인 상태도 5개 로케일 정직 문구', (tester) async {
    const expectations = <String, String>{
      'ko': '관측 시각 확인 중',
      'en': 'Observed time unavailable',
      'ja': '観測時刻を確認中',
      'zh-Hans': '观测时间确认中',
      'zh-Hant': '觀測時間確認中',
    };
    for (final entry in expectations.entries) {
      await pumpBadge(tester, recordTime: null, language: entry.key);
      expect(find.text(entry.value), findsOneWidget, reason: entry.key);
    }
  });

  testWidgets('스크린 리더: 결합 semantics label 로 한 노드에 전달', (tester) async {
    await pumpBadge(tester, recordTime: '2026-09-04T23:00:00+09:00');
    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel('관측 시각 2026-09-04 23:00, 이전 관측값'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('320dp 폭에서 긴 stale 라벨이 overflow 없이 감싸진다', (tester) async {
    await pumpBadge(
      tester,
      recordTime: '2026-09-04T23:00:00+09:00',
      language: 'en',
      size: const Size(320, 640),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Observed 2026-09-04 23:00'), findsOneWidget);
    expect(find.text('Earlier observation'), findsOneWidget);
  });

  testWidgets('TextScaler.linear(2)에서 overflow 없음(좁은 폭 결합)', (tester) async {
    await pumpBadge(
      tester,
      recordTime: '2026-09-04T23:00:00+09:00',
      language: 'en',
      textScaler: const TextScaler.linear(2),
      size: const Size(320, 800),
    );
    expect(tester.takeException(), isNull);
  });

  group('WeatherSheetContent 통합', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      required LalaWeather? weather,
      String language = 'ko',
      TextScaler textScaler = TextScaler.noScaling,
      Size size = const Size(402, 874),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: ListView(
                children: [
                  WeatherSheetContent(language: language, weather: weather),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('실측 날씨 시트: 히어로 카드 아래 관측 배지가 함께 렌더링', (tester) async {
      await pumpSheet(tester, weather: _weather(recordTime: freshRecordTime));
      expect(
        find.byKey(const ValueKey('weather-observed-time')),
        findsOneWidget,
      );
      expect(find.text('최신 관측'), findsOneWidget);
      expect(find.byKey(const ValueKey('weather-source-chip')), findsOneWidget);
    });

    testWidgets('관측 시각 없는 실측 날씨 시트: 미확인 문구가 값과 함께 표시', (tester) async {
      await pumpSheet(tester, weather: _weather(recordTime: null));
      expect(find.text('관측 시각 확인 중'), findsOneWidget);
      expect(find.text('최신 관측'), findsNothing);
    });

    testWidgets('unavailable 날씨(placeholder source)는 기존대로 unavailable 카드만', (
      tester,
    ) async {
      await pumpSheet(tester, weather: _weather(recordTime: null, source: ''));
      expect(
        find.byKey(const ValueKey('weather-unavailable-card')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('weather-observed-time')), findsNothing);
    });

    testWidgets('null 날씨도 기존 unavailable 카드 유지', (tester) async {
      await pumpSheet(tester, weather: null);
      expect(
        find.byKey(const ValueKey('weather-unavailable-card')),
        findsOneWidget,
      );
    });

    testWidgets('320dp + TextScaler.linear(2) 전체 시트 overflow 없음', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        weather: _weather(recordTime: '2026-09-04T23:00:00+09:00'),
        textScaler: const TextScaler.linear(2),
        size: const Size(320, 800),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('관측 시각 2026-09-04 23:00'), findsOneWidget);
      expect(find.text('이전 관측값'), findsOneWidget);
    });
  });
}

LalaWeather _weather({
  String? recordTime,
  String source = 'kma_ultra_srt_ncst',
}) {
  return LalaWeather(
    lat: 37.2636,
    lng: 127.0286,
    temp: '23',
    icon: 'partly-cloudy',
    dust: const LalaDust(
      pm10: '30',
      pm25: '25',
      grade: 'normal',
      gradeKo: '보통',
      pm10Grade: 'normal',
      pm10GradeKo: '보통',
      pm25Grade: 'good',
      pm25GradeKo: '좋음',
    ),
    forecast: const <LalaForecastItem>[],
    outdoorStatus: 'normal',
    force: false,
    source: source,
    location: 'Suwon',
    recordTime: recordTime,
    locationMatch: true,
  );
}
