import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/intervention/presentation/pages/intervention_comparison_page.dart';

void main() {
  testWidgets('S-21 compares API slots and returns the explicit decision', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    InterventionComparisonDecision? decision;
    final intervention = _intervention();
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open-comparison'),
                onPressed: () async {
                  decision = await context.push<InterventionComparisonDecision>(
                    '/compare',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/compare',
          builder: (context, state) => InterventionComparisonPage(
            language: 'ko',
            arguments: InterventionComparisonArguments(
              intervention: intervention,
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.byKey(const ValueKey('open-comparison')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('intervention-comparison-page')),
      findsOneWidget,
    );
    expect(find.text('야외 산책'), findsOneWidget);
    expect(find.text('실내 전시'), findsOneWidget);
    expect(find.textContaining('미세먼지'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('intervention-apply-alternative')),
    );
    await tester.pumpAndSettle();
    expect(decision, InterventionComparisonDecision.applyAlternative);
  });

  testWidgets(
    'S-21 keeps an honest unavailable state without an intervention',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: InterventionComparisonPage(language: 'ko')),
      );
      await tester.pumpAndSettle();

      expect(find.text('지금 비교할 상황 변화가 없어요.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('intervention-apply-alternative')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'S-21 shows closure and weather factor chips and evidence (F-051 why)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final intervention = _intervention(
        triggerType: 'bad_weather_and_closure',
        triggerFactors: const <Map<String, dynamic>>[
          <String, dynamic>{'factor': 'weather_outdoor_status', 'value': 'bad'},
          <String, dynamic>{
            'factor': 'slot_closure_state',
            'value': 'closed',
            'period': 'afternoon',
          },
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InterventionComparisonPage(
            language: 'ko',
            arguments: InterventionComparisonArguments(
              intervention: intervention,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Hierarchy chips: one per observable factor, scannable before the prose.
      expect(find.text('날씨 악화'), findsOneWidget);
      expect(find.text('운영 상태 변화'), findsOneWidget);
      // The closure factor previously never rendered because only the legacy
      // closure_state/opening_hours kinds were mapped.
      expect(find.text('추정 운영시간 기준으로 영업 종료 가능성이 관측됐어요.'), findsOneWidget);
      expect(find.text('현재 야외 활동 조건이 좋지 않아요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'P4/S-21 AQ-only trigger shows the AQ title, chip and evidence — never weather',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final intervention = _intervention(
        triggerType: 'bad_air_quality',
        triggerFactors: const <Map<String, dynamic>>[
          <String, dynamic>{'factor': 'air_quality_dust_grade', 'value': 'bad'},
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InterventionComparisonPage(
            language: 'ko',
            arguments: InterventionComparisonArguments(
              intervention: intervention,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // AQ cause is disclosed as itself: AQ title, AQ chip, AQ evidence line.
      expect(find.text('미세먼지가 일정에 영향을 줘요'), findsOneWidget);
      expect(find.text('미세먼지 나쁨'), findsOneWidget);
      expect(find.text('관측된 미세먼지 등급이 나빠요.'), findsOneWidget);
      // …and never mislabeled as weather.
      expect(find.text('날씨 변화가 일정에 영향을 줘요'), findsNothing);
      expect(find.text('날씨 악화'), findsNothing);
      expect(find.text('현재 야외 활동 조건이 좋지 않아요.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'P4/S-21 weather+AQ factors render both cause chips together',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final intervention = _intervention(
        triggerType: 'bad_weather_and_air_quality',
        triggerFactors: const <Map<String, dynamic>>[
          <String, dynamic>{'factor': 'weather_outdoor_status', 'value': 'bad'},
          <String, dynamic>{'factor': 'air_quality_dust_grade', 'value': 'very_bad'},
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InterventionComparisonPage(
            language: 'ko',
            arguments: InterventionComparisonArguments(
              intervention: intervention,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('날씨와 미세먼지가 함께 영향을 줘요'), findsOneWidget);
      expect(find.text('날씨 악화'), findsOneWidget);
      expect(find.text('미세먼지 나쁨'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'P4/S-21 AQ trigger localizes in en/ja/zh-Hans/zh-Hant (single-language)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const expectedByLanguage = <String, String>{
        'en': 'Air quality may affect this plan',
        'ja': '大気が予定に影響します',
        'zh-Hans': '空气质量可能影响行程',
        'zh-Hant': '空氣品質可能影響行程',
      };
      for (final entry in expectedByLanguage.entries) {
        final language = entry.key;
        final expectedTitle = entry.value;
        final intervention = _intervention(
          triggerType: 'bad_air_quality',
          triggerFactors: const <Map<String, dynamic>>[
            <String, dynamic>{'factor': 'air_quality_dust_grade', 'value': 'bad'},
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: InterventionComparisonPage(
              language: language,
              arguments: InterventionComparisonArguments(
                intervention: intervention,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(expectedTitle), findsOneWidget, reason: language);
        // Single-language: no Korean leaks onto visitor locales.
        expect(find.text('미세먼지가 일정에 영향을 줘요'), findsNothing, reason: language);
        expect(find.text('날씨 변화가 일정에 영향을 줘요'), findsNothing, reason: language);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'P4/S-21 AQ comparison page: 320dp + TextScaler.linear(2), no overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final intervention = _intervention(
        triggerType: 'bad_weather_and_air_quality_and_closure',
        triggerFactors: const <Map<String, dynamic>>[
          <String, dynamic>{'factor': 'weather_outdoor_status', 'value': 'bad'},
          <String, dynamic>{'factor': 'air_quality_dust_grade', 'value': 'very_bad'},
          <String, dynamic>{
            'factor': 'slot_closure_state',
            'value': 'closed',
            'period': 'afternoon',
          },
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: InterventionComparisonPage(
            language: 'ko',
            arguments: InterventionComparisonArguments(
              intervention: intervention,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('날씨·미세먼지·운영 상태를 모두 확인해야 해요'), findsOneWidget);
      // Triple-cause chips all wrap within the narrow, doubled-text viewport.
      expect(find.text('날씨 악화'), findsOneWidget);
      expect(find.text('미세먼지 나쁨'), findsOneWidget);
      expect(find.text('운영 상태 변화'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'S-21 cards carry real per-slot constraint badges (closure/AQ/indoor)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final intervention = _intervention(
        originalSlot: const LalaPlanSlot(
          period: 'afternoon',
          title: '야외 산책',
          indoorOutdoor: 'outdoor',
          closureState: 'closed',
          airQualityBad: true,
        ),
        alternativeSlot: const LalaPlanSlot(
          period: 'afternoon',
          title: '실내 전시',
          indoorOutdoor: 'indoor',
          closureState: 'open',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InterventionComparisonPage(
            language: 'ko',
            arguments: InterventionComparisonArguments(
              intervention: intervention,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The original card visibly carries the reported problem states…
      expect(find.text('영업종료'), findsOneWidget);
      expect(find.text('외부 대기질 나쁨'), findsOneWidget);
      expect(find.text('야외'), findsOneWidget);
      // …and the alternative shows the improving states.
      expect(find.text('영업중'), findsOneWidget);
      expect(find.text('실내'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'S-21 renders a balanced slot as a neutral mix badge, not outdoor',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final intervention = _intervention(
        originalSlot: const LalaPlanSlot(
          period: 'afternoon',
          title: '복합 문화 공간',
          indoorOutdoor: 'balanced',
          closureState: 'open',
        ),
        alternativeSlot: const LalaPlanSlot(
          period: 'afternoon',
          title: '실내 전시',
          indoorOutdoor: 'indoor',
          closureState: 'open',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InterventionComparisonPage(
            language: 'ko',
            arguments: InterventionComparisonArguments(
              intervention: intervention,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // balanced 는 중립 혼합 라벨 + 저울 아이콘 — 야외 주장 금지.
      expect(find.text('실내·야외 혼합'), findsOneWidget);
      expect(find.text('야외'), findsNothing);
      expect(find.byIcon(Icons.balance_outlined), findsOneWidget);
      expect(find.byIcon(Icons.park_outlined), findsNothing);
      // 대안 카드의 실내 배지는 그대로.
      expect(find.text('실내'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('S-21 hides the indoor-outdoor badge for a made-up wire value', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final intervention = _intervention(
      originalSlot: const LalaPlanSlot(
        period: 'afternoon',
        title: '복합 유리온실',
        indoorOutdoor: 'glasshouse-arcade',
        closureState: 'open',
      ),
      alternativeSlot: const LalaPlanSlot(
        period: 'afternoon',
        title: '실내 도서관',
        indoorOutdoor: 'bio-dome',
        closureState: 'open',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InterventionComparisonPage(
          language: 'ko',
          arguments: InterventionComparisonArguments(
            intervention: intervention,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Both cards render… (closure chips are unaffected by the wire value)
    expect(find.text('복합 유리온실'), findsOneWidget);
    expect(find.text('실내 도서관'), findsOneWidget);
    expect(find.text('영업중'), findsNWidgets(2));
    // …but an unknown indoor_outdoor value claims neither mix nor indoor
    // nor outdoor, with no icon implying any of them (honest-empty badge).
    expect(find.text('실내·야외 혼합'), findsNothing);
    expect(find.text('야외'), findsNothing);
    expect(find.text('실내'), findsNothing);
    expect(find.byIcon(Icons.balance_outlined), findsNothing);
    expect(find.byIcon(Icons.park_outlined), findsNothing);
    expect(find.byIcon(Icons.home_work_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('S-21 explains a disabled apply when no alternative exists', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final intervention = _intervention(includeAlternative: false);
    InterventionComparisonDecision? decision;
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open-comparison'),
                onPressed: () async {
                  decision = await context.push<InterventionComparisonDecision>(
                    '/compare',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/compare',
          builder: (context, state) => InterventionComparisonPage(
            language: 'ko',
            arguments: InterventionComparisonArguments(
              intervention: intervention,
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.byKey(const ValueKey('open-comparison')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('intervention-apply-alternative')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('intervention-apply-alternative')),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('대체 장소를 찾지 못했어요'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('intervention-keep-current')));
    await tester.pumpAndSettle();
    expect(decision, InterventionComparisonDecision.keepCurrent);
  });
}

LalaIntervention _intervention({
  String? triggerType,
  List<Map<String, dynamic>>? triggerFactors,
  LalaPlanSlot? originalSlot,
  LalaPlanSlot? alternativeSlot,
  bool includeAlternative = true,
}) => LalaIntervention(
  center: const LalaCoordinate(lat: 37.55, lng: 127.04),
  radiusM: 1800,
  shouldIntervene: true,
  reason: '미세먼지가 나빠져 실내 대안을 추천해요.',
  recommendedAction: '실내 전시로 바꾸면 야외 체류를 줄일 수 있어요.',
  source: 'airkorea+planner',
  triggerType: triggerType ?? 'bad_weather',
  originalSlot:
      originalSlot ??
      const LalaPlanSlot(
        period: 'afternoon',
        title: '야외 산책',
        indoorOutdoor: 'outdoor',
        startTime: '14:00',
      ),
  alternativeSlot: includeAlternative
      ? alternativeSlot ??
            const LalaPlanSlot(
              period: 'afternoon',
              title: '실내 전시',
              indoorOutdoor: 'indoor',
              startTime: '14:00',
            )
      : null,
  triggerFactors:
      triggerFactors ??
      const <Map<String, dynamic>>[
        <String, dynamic>{'factor': 'weather_outdoor_status', 'value': 'bad'},
      ],
  distanceComparison: const <String, dynamic>{
    'original_m': 900,
    'alternative_m': 650,
  },
);
