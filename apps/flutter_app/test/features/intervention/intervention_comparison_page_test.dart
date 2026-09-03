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
}

LalaIntervention _intervention() => LalaIntervention(
  center: const LalaCoordinate(lat: 37.55, lng: 127.04),
  radiusM: 1800,
  shouldIntervene: true,
  reason: '미세먼지가 나빠져 실내 대안을 추천해요.',
  recommendedAction: '실내 전시로 바꾸면 야외 체류를 줄일 수 있어요.',
  source: 'airkorea+planner',
  triggerType: 'bad_air_quality',
  originalSlot: const LalaPlanSlot(
    period: 'afternoon',
    title: '야외 산책',
    indoorOutdoor: 'outdoor',
    startTime: '14:00',
  ),
  alternativeSlot: const LalaPlanSlot(
    period: 'afternoon',
    title: '실내 전시',
    indoorOutdoor: 'indoor',
    startTime: '14:00',
  ),
  triggerFactors: const <Map<String, dynamic>>[
    <String, dynamic>{'type': 'air_quality', 'label': '미세먼지', 'observed': '나쁨'},
  ],
  distanceComparison: const <String, dynamic>{
    'original_m': 900,
    'alternative_m': 650,
  },
);
