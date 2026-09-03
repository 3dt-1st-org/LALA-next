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
