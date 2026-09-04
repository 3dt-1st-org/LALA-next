// Lane 1 (§13.4) — cross-tab reactive propagation tests.
//
// These verify the bidirectional sharing contract (D2/D4) end-to-end:
//  - Plan tab ADOPTS a plan published to PlanContextStore by another tab, WITHOUT
//    its own createDailyPlan completing (the dual-fetch is eliminated — the store
//    is the SSOT).   [store → plan tab]
//  - Plan tab PUBLISHES its fetched plan into PlanContextStore.   [plan tab → store]
//  - Map tab PUBLISHES its fetched plan AND its selection into the shared stores
//    (selection driven via the LocalSignalActionController seam).   [map → store]
//
// No persistence / device / live call. Holders are in-memory singletons reset in
// setUp. Region/language SSOTs are untouched (D6).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/navigation/local_signal_action.dart';
import 'package:lala_next_app/core/state/plan_context_store.dart';
import 'package:lala_next_app/core/state/selected_place_store.dart';
import 'package:lala_next_app/features/home/home_page.dart';
import 'package:lala_next_app/features/plan/presentation/pages/plan_page.dart';

LalaEnvelope<T> _envelope<T>(T data) => LalaEnvelope<T>(
  ok: true,
  data: data,
  meta: const <String, dynamic>{'request_id': 'crosstab-test'},
  error: null,
  statusCode: 200,
  requestId: 'crosstab-test',
);

LalaWeather _weather() => LalaWeather(
  lat: 37.2636,
  lng: 127.0286,
  temp: '14°C',
  icon: 'partly-cloudy',
  dust: const LalaDust(
    pm10: '31',
    pm25: '14',
    grade: 'normal',
    gradeKo: '보통',
    pm10Grade: 'normal',
    pm10GradeKo: '보통',
    pm25Grade: 'good',
    pm25GradeKo: '좋음',
  ),
  forecast: const <LalaForecastItem>[],
  outdoorStatus: 'good',
  force: false,
  source: 'db',
  location: 'Suwon',
  recordTime: '2026-06-18T09:00:00+09:00',
  locationMatch: true,
);

LalaDailyPlan _plan({required String cacheKey}) => LalaDailyPlan(
  language: 'ko',
  center: const LalaCoordinate(lat: 37.2636, lng: 127.0286),
  radiusM: 3000,
  weather: _weather(),
  slots: const <LalaPlanSlot>[
    LalaPlanSlot(period: 'morning', title: '화성행궁 산책 코스'),
  ],
  source: 'db',
  // 저엔트로피 테스트 값(detect-secrets 허위 양성 회피; 실제 키/해시 아님).
  requestHash: 'test-plan-request-hash',
  cacheKey: cacheKey,
);

LalaPlace _placeNamed(String id, String name) => LalaPlace(
  placeId: id,
  name: name,
  nameKo: name,
  nameEn: name,
  category: 'attraction',
  lat: 37.28,
  lng: 127.01,
  address: 'addr',
  regionKo: '수원',
  regionEn: 'Suwon',
  distanceM: 100,
  source: 'db',
  upstreamSource: 'tour_api',
  score: const LalaPlaceScore(
    finalScore: 0.8,
    formulaVersion: 'local-value-v2',
    components: LalaPlaceScoreComponents(
      localSpendingScore: 0.8,
      smallMerchantFitScore: 0.7,
      demandDispersionScore: 0.7,
      weatherFitScore: 0.7,
      reviewQualityScore: null,
      cultureRelevanceScore: 0.8,
      accessibilityFitScore: 0.6,
    ),
    dataBasis: 'analytics.place_score_snapshots',
    features: <String, dynamic>{},
  ),
);

LalaPlacesResponse _placesResponse(String id, String name) =>
    LalaPlacesResponse(
      count: 1,
      places: <LalaPlace>[_placeNamed(id, name)],
      query: const LalaPlacesQuery(
        lat: 37.28,
        lng: 127.01,
        radiusM: 3000,
        limit: 60,
        category: 'all',
        language: 'ko',
      ),
      source: 'db',
      locationEngine: 'db',
    );

class _ImmediateLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() => Future.value(
    const LalaLocationResult.found(LalaLocation(lat: 37.28, lng: 127.01)),
  );
}

/// Plan/daily-plan resolver that never completes — keeps the plan tab in its
/// loading state so adoption from PlanContextStore can be observed in isolation
/// (the tab's own fetch must NOT be what supplies the plan).
class _PendingPlanBackend implements LalaBackend {
  final Completer<LalaEnvelope<LalaDailyPlan>> _plan =
      Completer<LalaEnvelope<LalaDailyPlan>>();
  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({String? selectedPlaceId, LalaPlanPreferenceContext? preferenceContext}) => _plan.future;
  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() =>
      Completer<LalaEnvelope<LalaIntervention>>().future;
  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: ${invocation.memberName}');
}

/// Immediate plan/intervention backend — the plan tab fetches and then publishes
/// the result into PlanContextStore.
class _LoadedPlanBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({String? selectedPlaceId, LalaPlanPreferenceContext? preferenceContext}) async =>
      _envelope(_plan(cacheKey: 'daily_plan:plan-tab'));
  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: ${invocation.memberName}');
}

/// Map-tab backend: returns one known place + a daily plan immediately. All other
/// endpoints throw and are absorbed by loadOptional.
class _MapFakeBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async =>
      _envelope(_placesResponse('sig-place', '시그널장소'));
  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({String? selectedPlaceId, LalaPlanPreferenceContext? preferenceContext}) async =>
      _envelope(_plan(cacheKey: 'daily_plan:map-tab'));
  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: ${invocation.memberName}');
}

/// Bounded flush: the home page's recovery/timer machinery can keep the frame
/// loop alive, so pumpAndSettle is unreliable. A bounded sequence drains the
/// microtask chain between each await in _refresh without hanging.
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  // The two new holders + the region holder are process-local singletons: reset
  // before each case so a selection/plan/region from one test cannot leak.
  setUp(() {
    SelectedPlaceStore.clear();
    PlanContextStore.clear();
    RegionContextStore.clear();
  });

  testWidgets(
    'plan tab adopts a plan published to PlanContextStore without its own fetch '
    'completing (store → plan tab)',
    (tester) async {
      // Pending backend: the plan tab's own createDailyPlan never resolves, so any
      // plan shown MUST come from the shared store.
      await tester.pumpWidget(
        MaterialApp(
          home: PlanPage(
            locationProvider: _ImmediateLocationProvider(),
            backendFactory: (config) => _PendingPlanBackend(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      // Loading state is honest (no fabricated plan).
      expect(
        find.byKey(const ValueKey('planner-loading-card')),
        findsOneWidget,
      );
      expect(PlanContextStore.current, isNull);

      // Simulate the MAP tab publishing its plan into the shared store.
      PlanContextStore.set(_plan(cacheKey: 'daily_plan:map-tab'));
      await _flush(tester);

      // The plan tab's listener adopted the shared plan: the real slot title is
      // rendered, and the loading card is gone. The tab did NOT refetch.
      expect(find.text('화성행궁 산책 코스'), findsOneWidget);
      expect(find.byKey(const ValueKey('planner-loading-card')), findsNothing);
    },
  );

  testWidgets(
    'plan tab publishes its fetched plan into PlanContextStore (plan tab → store)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlanPage(
            locationProvider: _ImmediateLocationProvider(),
            backendFactory: (config) => _LoadedPlanBackend(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The plan tab wrote its fetched timeline through to the shared store.
      expect(PlanContextStore.current, isNotNull);
      expect(PlanContextStore.current!.slots.first.title, '화성행궁 산책 코스');
    },
  );

  testWidgets(
    'map tab publishes its plan and selection to the shared stores (map → store)',
    (tester) async {
      final controller = LocalSignalActionController();
      await tester.pumpWidget(
        MaterialApp(
          home: LalaHomePage(
            backendFactory: (config) => _MapFakeBackend(),
            initialConfig: const LalaAppConfig(baseUri: 'http://test'),
            locationProvider: _ImmediateLocationProvider(),
            recommendationRecoveryDelays: const <Duration>[],
            authControllerFactory: createLalaAuthController,
            localSignalActionController: controller,
          ),
        ),
      );

      // Drive initState + postFrame + initial location-driven refresh, then let
      // the places/plan fetches resolve.
      await _flush(tester);

      final context = tester.element(
        find.descendant(
          of: find.byType(LalaHomePage),
          matching: find.byType(Scaffold),
        ),
      );
      // Sanity: the candidate set has loaded before we drive a selection.
      expect(LalaHomePage.placesStateForTesting(context).count, 1);

      // The map published its createDailyPlan result into the shared store.
      expect(PlanContextStore.current, isNotNull);
      expect(PlanContextStore.current!.slots.first.title, '화성행궁 산책 코스');

      // No selection yet (honest empty).
      expect(SelectedPlaceStore.current, isNull);

      // Cross-tab hand-off: a place selection (as dispatched by the Local Signals
      // tab via the shared controller) flows through the map into the shared store.
      controller.dispatch(
        const LocalSignalPlaceActionRequest(
          placeId: 'sig-place',
          action: LocalSignalPlaceAction.viewPlace,
        ),
      );
      await _flush(tester);

      expect(SelectedPlaceStore.current, 'sig-place');

      // Clearing propagates: another tab clears the shared selection and the map
      // reflects the empty selection (no crash; store reverts to honest empty).
      SelectedPlaceStore.clear();
      await _flush(tester);
      expect(SelectedPlaceStore.current, isNull);
    },
  );
}
