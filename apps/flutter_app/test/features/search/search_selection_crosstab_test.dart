// V7 follow-up: search-tab place selection through the shared cross-tab state.
//
// Proves the wiring end-to-end (§13.4):
//  - a search-result tap publishes SelectedPlaceStore (the SAME store the map
//    tab writes to) and hands off to the map branch   [search → store → switch]
//  - the map ADOPTS an external (search-originated) selection through the local
//    tap path — the detail sheet opens exactly as for map-originated selection
//    (parity reference: the Local Signals-driven map selection does the same)
//  - a search-originated selection persists under lala.crosstab.v1.* and
//    hydrates back into SelectedPlaceStore on a simulated cold restart
//
// No live device/network call: locations and backends are injected fakes. The
// holders are process-local singletons reset in setUp/tearDown.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/app/bootstrap.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/navigation/local_signal_action.dart';
import 'package:lala_next_app/core/persistence/cross_tab_preferences.dart';
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/core/state/plan_context_store.dart';
import 'package:lala_next_app/core/state/selected_place_store.dart';
import 'package:lala_next_app/features/home/widgets/map_draggable_sheet.dart';
import 'package:lala_next_app/features/map_route/presentation/pages/map_route_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/search/presentation/pages/search_page.dart';

LalaEnvelope<T> _envelope<T>(T data) => LalaEnvelope<T>(
  ok: true,
  data: data,
  meta: const <String, dynamic>{'request_id': 'search-selection-test'},
  error: null,
  statusCode: 200,
  requestId: 'search-selection-test',
);

LalaPlace _cafe() {
  return const LalaPlace(
    placeId: 'crosstab-cafe',
    name: '검색 카페',
    nameKo: '검색 카페',
    nameEn: 'Search Cafe',
    category: 'restaurant',
    lat: 37.2828,
    lng: 127.0101,
    address: '경기도 수원시 팔달구 행궁동',
    regionKo: '수원',
    regionEn: 'Suwon',
    distanceM: 320,
    source: 'db',
    upstreamSource: 'tour_api',
  );
}

LalaPlacesResponse _placesResponse() => LalaPlacesResponse(
  count: 1,
  places: <LalaPlace>[_cafe()],
  query: const LalaPlacesQuery(
    lat: 37.2828,
    lng: 127.0101,
    radiusM: 2000,
    limit: 60,
    category: 'all',
    language: 'ko',
  ),
  source: 'db',
  locationEngine: 'postgis',
);

class _ImmediateLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() => Future.value(
    const LalaLocationResult.found(LalaLocation(lat: 37.2828, lng: 127.0101)),
  );
}

/// Search-tab fake: one known place the test can tap.
class _SearchFakeBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async =>
      _envelope(_placesResponse());

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'not used in search selection: ${invocation.memberName}',
  );
}

/// Map-tab fake: the same known place so an external selection resolves here.
class _MapFakeBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async =>
      _envelope(_placesResponse());

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() async => _envelope(
    LalaDailyPlan(
      language: 'ko',
      center: const LalaCoordinate(lat: 37.2828, lng: 127.0101),
      radiusM: 3000,
      weather: LalaWeather(
        lat: 37.2828,
        lng: 127.0101,
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
      ),
      slots: const <LalaPlanSlot>[],
      source: 'db',
      // 저엔트로피 테스트 값(detect-secrets 허위 양성 회피; 실제 키/해시 아님).
      requestHash: 'test-search-selection-hash',
      cacheKey: 'daily_plan:search-selection-test',
    ),
  );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'not used in map adoption: ${invocation.memberName}',
  );
}

/// Bounded flush: the home page's recovery/timer machinery can keep the frame
/// loop alive, so pumpAndSettle is unreliable (mirrors crosstab tests).
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Two-branch shell mirroring the production StatefulShellRoute. Like the real
/// router it STARTS ON THE MAP branch — go_router builds inactive branches
/// lazily, so the map (the initial tab) is mounted and its shared-selection
/// listener is live before the user can ever reach the search tab.
GoRouter _shellRouter() {
  return GoRouter(
    initialLocation: LalaRoutePaths.mapRoute,
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => Scaffold(
          key: const ValueKey('shell-scaffold'),
          body: navigationShell,
        ),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: LalaRoutePaths.search,
                builder: (context, state) => SearchPage(
                  locationProvider: _ImmediateLocationProvider(),
                  backendFactory: (config) => _SearchFakeBackend(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: LalaRoutePaths.mapRoute,
                builder: (context, state) => MapRoutePage(
                  backendFactory: (config) => _MapFakeBackend(),
                  initialConfig: const LalaAppConfig(baseUri: 'http://test'),
                  locationProvider: _ImmediateLocationProvider(),
                  recommendationRecoveryDelays: const <Duration>[],
                  authControllerFactory: createLalaAuthController,
                  localSignalActionController: LocalSignalActionController(),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CrossTabPersistence.detach();
    SelectedPlaceStore.clear();
    PlanContextStore.clear();
    RegionContextStore.clear();
    OnboardingState.reset();
    OnboardingState.markCompleted();
  });

  tearDown(() {
    CrossTabPersistence.detach();
    SelectedPlaceStore.clear();
    PlanContextStore.clear();
    RegionContextStore.clear();
    OnboardingState.reset();
  });

  testWidgets(
    'search tap publishes the shared selection and switches to the map branch '
    '(search → store → tab switch)',
    (tester) async {
      final router = _shellRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _flush(tester);

      // Production order: the app starts on the map branch (so its shared
      // selection listener is live), then the user moves to the search tab.
      final shellContext = tester.element(
        find.byKey(const ValueKey('shell-scaffold')),
      );
      shellContext.go(LalaRoutePaths.search);
      await _flush(tester);

      // The search tab loaded a real result tile; nothing is selected and no
      // detail sheet exists yet.
      expect(
        find.byKey(const ValueKey('search-place-tile-crosstab-cafe')),
        findsOneWidget,
      );
      expect(SelectedPlaceStore.current, isNull);
      expect(find.byType(MapDraggableSheet), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('search-place-tile-crosstab-cafe')),
      );
      await _flush(tester);

      // The SAME shared store the map writes to now holds the search choice.
      expect(SelectedPlaceStore.current, 'crosstab-cafe');
      // The shell handed off to the map branch (the Local Signals convention).
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        LalaRoutePaths.mapRoute,
      );
      // The map adopted the selection: the detail sheet is open, driven by the
      // place the user tapped on the search tab.
      expect(find.byType(MapDraggableSheet), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('map adopts a search-originated selection exactly like a map tap '
      '(store → map: detail sheet opens)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MapRoutePage(
          backendFactory: (config) => _MapFakeBackend(),
          initialConfig: const LalaAppConfig(baseUri: 'http://test'),
          locationProvider: _ImmediateLocationProvider(),
          recommendationRecoveryDelays: const <Duration>[],
          authControllerFactory: createLalaAuthController,
          localSignalActionController: LocalSignalActionController(),
        ),
      ),
    );
    await _flush(tester);

    // Loaded candidate set; no selection and no sheet yet.
    expect(SelectedPlaceStore.current, isNull);
    expect(find.byType(MapDraggableSheet), findsNothing);

    // Exactly what SearchPage._selectPlace does: a plain shared-store publish.
    SelectedPlaceStore.set('crosstab-cafe');
    await _flush(tester);

    // The map adopted it through the local tap path: selection held, detail
    // sheet open — the same surface a map-originated tap produces.
    expect(SelectedPlaceStore.current, 'crosstab-cafe');
    expect(find.byType(MapDraggableSheet), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'map-originated selection still opens the same detail sheet (parity; '
    'map behavior unchanged)',
    (tester) async {
      final controller = LocalSignalActionController();
      await tester.pumpWidget(
        MaterialApp(
          home: MapRoutePage(
            backendFactory: (config) => _MapFakeBackend(),
            initialConfig: const LalaAppConfig(baseUri: 'http://test'),
            locationProvider: _ImmediateLocationProvider(),
            recommendationRecoveryDelays: const <Duration>[],
            authControllerFactory: createLalaAuthController,
            localSignalActionController: controller,
          ),
        ),
      );
      await _flush(tester);

      // The pre-existing map-driven flow (Local Signals dispatch → map tab).
      controller.dispatch(
        const LocalSignalPlaceActionRequest(
          placeId: 'crosstab-cafe',
          action: LocalSignalPlaceAction.viewPlace,
        ),
      );
      await _flush(tester);

      expect(SelectedPlaceStore.current, 'crosstab-cafe');
      expect(find.byType(MapDraggableSheet), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  // Plain test (no widget pump) mirroring cold_start_persistence_test: the
  // widget tests above prove tap → store; this proves store → envelope →
  // hydrate. bootstrapAppState's awaits don't settle inside a fake-async
  // testWidgets zone, which is why the cold-start suite is plain tests too.
  test(
    'search-originated selection persists (envelope write) and hydrates on a '
    'simulated cold restart',
    () async {
      final backend = _MemoryBackend();
      await bootstrapAppState(
        preferences: OnboardingPreferences(backend),
        crossTabPreferences: CrossTabPreferences(backend),
      );

      // Exactly what the search tab's tap publishes (wired by the widget tests
      // above): a plain shared-store write.
      SelectedPlaceStore.set('crosstab-cafe');

      // Write-through fired from the search-originated publish.
      await _drainWrites();
      final key = '${kCrossTabStoragePrefix}selectedPlaceId';
      expect(backend.store[key], 'crosstab-cafe');

      // Simulate a cold restart: drop the in-memory holders + listeners, then
      // hydrate from the same durable store the write landed in.
      CrossTabPersistence.detach();
      SelectedPlaceStore.clear();
      PlanContextStore.clear();
      await bootstrapAppState(
        preferences: OnboardingPreferences(backend),
        crossTabPreferences: CrossTabPreferences(backend),
      );
      expect(SelectedPlaceStore.current, 'crosstab-cafe');
    },
  );
}

/// Drain the unawaited persistence microtasks fired by set/clear.
Future<void> _drainWrites() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// In-memory backend for deterministic, plugin-free persistence. Implements
/// both backends so a single instance backs onboarding + cross-tab in a test.
class _MemoryBackend
    implements OnboardingPreferencesBackend, CrossTabPreferencesBackend {
  _MemoryBackend([Map<String, Object?>? seed])
    : store = Map<String, Object?>.from(seed ?? <String, Object?>{});

  final Map<String, Object?> store;

  @override
  Future<bool?> getBool(String key) async => store[key] as bool?;

  @override
  Future<String?> getString(String key) async => store[key] as String?;

  @override
  Future<void> setBool(String key, bool value) async {
    store[key] = value;
  }

  @override
  Future<void> setString(String key, String value) async {
    store[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    store.remove(key);
  }
}
