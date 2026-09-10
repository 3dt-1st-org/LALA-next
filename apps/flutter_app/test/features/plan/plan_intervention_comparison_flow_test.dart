import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/intervention/presentation/pages/intervention_comparison_page.dart';
import 'package:lala_next_app/features/plan/presentation/pages/plan_page.dart';

void main() {
  testWidgets('S-20 applies and undoes the explicit S-21 alternative', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = _InterventionBackend();
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => PlanPage(
            initialConfig: const LalaAppConfig(baseUri: 'https://test.invalid'),
            locationProvider: const _LocationProvider(),
            backendFactory: (_) => backend,
          ),
        ),
        GoRoute(
          path: LalaRoutePaths.interventionComparison,
          builder: (context, state) => InterventionComparisonPage(
            language: 'ko',
            arguments: state.extra as InterventionComparisonArguments?,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('야외 산책'), findsOneWidget);
    // P4: the AQ-only trigger carries its own badge — never '날씨 변화'.
    expect(find.text('미세먼지 나쁨'), findsOneWidget);
    expect(find.text('날씨 변화'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('intervention-toast-swap')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('intervention-comparison-page')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('intervention-apply-alternative')),
    );
    await tester.pumpAndSettle();
    expect(find.text('실내 전시'), findsOneWidget);
    expect(find.text('야외 산책'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('intervention-undo')));
    await tester.pumpAndSettle();
    expect(find.text('야외 산책'), findsOneWidget);
    expect(find.text('실내 전시'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _InterventionBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({String? selectedPlaceId, LalaPlanPreferenceContext? preferenceContext}) async => _envelope(
    LalaDailyPlan(
      language: 'ko',
      center: const LalaCoordinate(lat: 37.55, lng: 127.04),
      radiusM: 1800,
      weather: _weather,
      slots: const <LalaPlanSlot>[
        LalaPlanSlot(period: 'afternoon', title: '야외 산책'),
      ],
      source: 'planner',
      requestHash: 'request-hash',
      cacheKey: 'plan-cache',
    ),
  );

  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() async => _envelope(
    const LalaIntervention(
      center: LalaCoordinate(lat: 37.55, lng: 127.04),
      radiusM: 1800,
      shouldIntervene: true,
      reason: '미세먼지가 나빠졌어요.',
      recommendedAction: '실내 전시를 추천해요.',
      source: 'airkorea+planner',
      triggerType: 'bad_air_quality',
      originalSlot: LalaPlanSlot(period: 'afternoon', title: '야외 산책'),
      alternativeSlot: LalaPlanSlot(period: 'afternoon', title: '실내 전시'),
    ),
  );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _LocationProvider implements LalaLocationProvider {
  const _LocationProvider();

  @override
  Future<LalaLocationResult> requestCurrentLocation() async =>
      const LalaLocationResult.found(LalaLocation(lat: 37.55, lng: 127.04));
}

final LalaWeather _weather = LalaWeather(
  lat: 37.0,
  lng: 127.04,
  temp: '20°C',
  icon: 'cloudy',
  dust: const LalaDust(
    pm10: '82',
    pm25: '36',
    grade: 'bad',
    gradeKo: '나쁨',
    pm10Grade: 'bad',
    pm10GradeKo: '나쁨',
    pm25Grade: 'bad',
    pm25GradeKo: '나쁨',
  ),
  forecast: const <LalaForecastItem>[],
  outdoorStatus: 'bad',
  force: false,
  source: 'airkorea',
  location: 'Seoul',
  recordTime: '2026-09-03T10:00:00+09:00',
  locationMatch: true,
);

LalaEnvelope<T> _envelope<T>(T data) => LalaEnvelope<T>(
  ok: true,
  data: data,
  meta: const <String, dynamic>{},
  error: null,
  statusCode: 200,
  requestId: 'test-request',
);
