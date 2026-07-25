// Wave-1 cold-start persistence: hydration + restart-routing integration tests.
//
// Proves the behavioral contract end-to-end through the static holders + router:
//  - bootstrapAppState restores completed + language + tourist type + manual region
//  - empty store / storage failure / invalid region id degrade to a clean first run
//  - a cold-start completed user routes straight to the map shell (no onboarding flash)
//  - a restored manual region seeds Search/Plan coordinates with NO device request
//  - RegionSource.current is never persisted; manual persists and supersedes cleanly
//  - reset/clear wipe persisted onboarding + region state (re-onboarding)
//  - completeAndFlush is durable before navigation and still completes on storage failure
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/app/bootstrap.dart';
import 'package:lala_next_app/app/lala_main_shell.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/core/routing/lala_router.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/onboarding/presentation/pages/splash_page.dart';
import 'package:lala_next_app/features/plan/presentation/pages/plan_page.dart';
import 'package:lala_next_app/features/search/presentation/pages/search_page.dart';
import 'package:lala_next_app/manual_location_options.dart';

void main() {
  // The onboarding + region holders are process-local singletons. Detach + reset
  // before/after each case so an attached prefs or a completed flag can never leak
  // between tests.
  setUp(() {
    OnboardingState.detachPersistence();
    RegionContextStore.detachPersistence();
    OnboardingState.reset();
    RegionContextStore.clear();
  });

  tearDown(() {
    OnboardingState.detachPersistence();
    RegionContextStore.detachPersistence();
    OnboardingState.reset();
    RegionContextStore.clear();
  });

  group('bootstrapAppState hydration', () {
    test(
      'restores completed onboarding + chosen language/tourist type + manual region',
      () async {
        final backend = _MemoryBackend();
        // Prior session completed as a foreign (English) tourist who picked Busan.
        await OnboardingPreferences(backend).writeOnboarding(
          completed: true,
          language: 'en',
          touristTypeCode: kTouristTypeCodeForeign,
        );
        await OnboardingPreferences(
          backend,
        ).writeManualRegionId('busan-haeundae');

        await bootstrapAppState(preferences: OnboardingPreferences(backend));

        expect(OnboardingState.isCompleted, isTrue);
        expect(OnboardingState.language, 'en');
        expect(
          OnboardingState.touristType,
          OnboardingTouristType.foreignTourist,
        );
        expect(RegionContextStore.current?.regionId, 'busan-haeundae');
        expect(RegionContextStore.current?.source, RegionSource.manual);
      },
    );

    test('empty store is a clean first run', () async {
      await bootstrapAppState(
        preferences: OnboardingPreferences(_MemoryBackend()),
      );
      expect(OnboardingState.isCompleted, isFalse);
      expect(OnboardingState.language, 'ko');
      expect(OnboardingState.touristType, OnboardingTouristType.localTourist);
      expect(RegionContextStore.current, isNull);
    });

    test(
      'tolerates an invalid persisted manual region id (no crash, no fake region)',
      () async {
        final key = '${kOnboardingStoragePrefix}manualRegionId';
        final backend = _MemoryBackend({key: 'this-region-was-removed'});
        await bootstrapAppState(preferences: OnboardingPreferences(backend));
        expect(RegionContextStore.current, isNull);
        // The bad value was cleaned up.
        expect(backend.store[key], isNull);
      },
    );

    test(
      'degrades to a clean first run on storage failure (never throws)',
      () async {
        await bootstrapAppState(
          preferences: OnboardingPreferences(_FailingBackend()),
        );
        expect(OnboardingState.isCompleted, isFalse);
        expect(RegionContextStore.current, isNull);
      },
    );
  });

  group('persistence through the static holders', () {
    test(
      'RegionSource.current is never persisted; manual persists and supersedes',
      () async {
        final backend = _MemoryBackend();
        await bootstrapAppState(preferences: OnboardingPreferences(backend));

        // A manual selection persists its stable region id.
        RegionContextStore.set(RegionContext.manual(_busanHaeundae()));
        expect(await _loadManualRegionId(backend), 'busan-haeundae');

        // Switching to current clears the persisted manual id. Precise coordinates
        // are never written, so a cold start yields no real region.
        RegionContextStore.set(
          RegionContext.current(lat: 37.5665, lng: 126.978),
        );
        expect(await _loadManualRegionId(backend), isNull);
      },
    );

    test(
      'reset/clear wipe persisted onboarding + region state (re-onboarding)',
      () async {
        final backend = _MemoryBackend();
        await bootstrapAppState(preferences: OnboardingPreferences(backend));
        OnboardingState.selectTouristType(OnboardingTouristType.foreignTourist);
        await OnboardingState.completeAndFlush();
        RegionContextStore.set(RegionContext.manual(_busanHaeundae()));
        await _drainWrites();

        // Re-onboarding reset path clears both the in-memory state and the
        // persisted slices it owns.
        OnboardingState.reset();
        RegionContextStore.clear();
        await _drainWrites();

        final snapshot = await OnboardingPreferences(backend).load();
        expect(snapshot.completed, isFalse);
        expect(snapshot.language, 'ko');
        expect(snapshot.touristTypeCode, kTouristTypeCodeLocal);
        expect(snapshot.manualRegionId, isNull);
        expect(OnboardingState.isCompleted, isFalse);
        expect(RegionContextStore.current, isNull);
      },
    );

    test(
      'completeAndFlush persists completion + choices before flipping the gate',
      () async {
        final backend = _MemoryBackend();
        await bootstrapAppState(preferences: OnboardingPreferences(backend));
        OnboardingState.selectTouristType(OnboardingTouristType.foreignTourist);

        await OnboardingState.completeAndFlush();

        expect(OnboardingState.isCompleted, isTrue);
        final snapshot = await OnboardingPreferences(backend).load();
        expect(snapshot.completed, isTrue);
        expect(snapshot.language, 'en');
        expect(snapshot.touristTypeCode, kTouristTypeCodeForeign);
      },
    );

    test(
      'completeAndFlush still completes in-memory when storage fails',
      () async {
        await bootstrapAppState(
          preferences: OnboardingPreferences(_FailingBackend()),
        );
        await OnboardingState.completeAndFlush();
        // Never strand the user on onboarding: completion holds for this session.
        expect(OnboardingState.isCompleted, isTrue);
      },
    );
  });

  group('cold-start routing + region seed', () {
    testWidgets(
      'a completed cold-start user routes to the map shell with no onboarding flash',
      (tester) async {
        final backend = _MemoryBackend();
        await OnboardingPreferences(backend).writeOnboarding(
          completed: true,
          language: 'ko',
          touristTypeCode: kTouristTypeCodeLocal,
        );
        await bootstrapAppState(preferences: OnboardingPreferences(backend));

        final router = createLalaRouter(
          backendFactory: (config) => _NoopBackend(),
          initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
          locationProvider: _CountingLocationProvider(
            const LalaLocationResult.denied(),
          ),
          recommendationRecoveryDelays: const <Duration>[Duration(seconds: 1)],
          authControllerFactory: createLalaAuthController,
        );
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        // No transient redirect to onboarding for a known-completed user: the
        // shell is the very first frame.
        expect(find.byType(OnboardingSplashPage), findsNothing);
        expect(find.byType(LalaMainShell), findsOneWidget);
        expect(OnboardingState.isCompleted, isTrue);
        // Drain the map tab's first-refresh retry timers so no timer is pending
        // at teardown.
        await tester.pumpAndSettle(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'restored manual Busan seeds SearchPage coordinates with no device request',
      (tester) async {
        final backend = _MemoryBackend();
        await OnboardingPreferences(backend).writeOnboarding(
          completed: true,
          language: 'ko',
          touristTypeCode: kTouristTypeCodeLocal,
        );
        await OnboardingPreferences(
          backend,
        ).writeManualRegionId('busan-haeundae');
        await bootstrapAppState(preferences: OnboardingPreferences(backend));

        // Restored BEFORE the tab mounts.
        expect(RegionContextStore.current?.regionId, 'busan-haeundae');

        final configs = <LalaAppConfig>[];
        final locationProvider = _CountingLocationProvider(
          const LalaLocationResult.found(
            LalaLocation(lat: 37.5665, lng: 126.978),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: SearchPage(
              locationProvider: locationProvider,
              backendFactory: (config) {
                configs.add(config);
                return _LoadedPlacesBackend();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Never asked the device, and the backend was built from Busan's coords.
        expect(locationProvider.requests, 0);
        expect(configs.last.lat, 35.16665);
        expect(configs.last.lng, 129.16792);
        // A real manual context means the default-region badge stays hidden.
        expect(find.text('현재 위치 대신 기본 지역(수원) 추천을 보여드려요'), findsNothing);
      },
    );

    testWidgets(
      'restored manual Busan seeds PlanPage coordinates with no device request',
      (tester) async {
        final backend = _MemoryBackend();
        await OnboardingPreferences(backend).writeOnboarding(
          completed: true,
          language: 'ko',
          touristTypeCode: kTouristTypeCodeLocal,
        );
        await OnboardingPreferences(
          backend,
        ).writeManualRegionId('busan-haeundae');
        await bootstrapAppState(preferences: OnboardingPreferences(backend));

        final configs = <LalaAppConfig>[];
        final locationProvider = _CountingLocationProvider(
          const LalaLocationResult.found(
            LalaLocation(lat: 37.5665, lng: 126.978),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: PlanPage(
              locationProvider: locationProvider,
              backendFactory: (config) {
                configs.add(config);
                return _LoadedPlanBackend();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(locationProvider.requests, 0);
        expect(configs.last.lat, 35.16665);
        expect(configs.last.lng, 129.16792);
      },
    );
  });
}

/// Drain the unawaited persistence microtasks fired by set/clear/reset/markCompleted.
Future<void> _drainWrites() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<String?> _loadManualRegionId(_MemoryBackend backend) async {
  await _drainWrites();
  return (await OnboardingPreferences(backend).load()).manualRegionId;
}

ManualLocationOption _busanHaeundae() {
  // Use the real entry from manual_location_options so the restored coordinates
  // match what the tabs will actually seed.
  return manualLocationOptions.firstWhere((o) => o.id == 'busan-haeundae');
}

/// In-memory OnboardingPreferencesBackend for deterministic, plugin-free tests.
class _MemoryBackend implements OnboardingPreferencesBackend {
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

/// OnboardingPreferencesBackend whose store is permanently unavailable.
class _FailingBackend implements OnboardingPreferencesBackend {
  Future<Never> _fail() async => throw StateError('storage unavailable');

  @override
  Future<bool?> getBool(String key) => _fail();

  @override
  Future<String?> getString(String key) => _fail();

  @override
  Future<void> setBool(String key, bool value) => _fail();

  @override
  Future<void> setString(String key, String value) => _fail();

  @override
  Future<void> remove(String key) => _fail();
}

/// Counts device-location requests. Proves a restored region skips the request.
class _CountingLocationProvider implements LalaLocationProvider {
  _CountingLocationProvider(this._result);

  final LalaLocationResult _result;
  int requests = 0;

  @override
  Future<LalaLocationResult> requestCurrentLocation() async {
    requests += 1;
    return _result;
  }
}

/// Backend for the cold-start router test. It returns successful (empty/minimal)
/// read results so the map tab's first refresh settles without scheduling retry
/// or recovery timers — the routing assertion is about the first frame, not data.
class _NoopBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getHealth() async =>
      _rawEnvelope(<String, dynamic>{'status': 'ok'});

  @override
  Future<LalaEnvelope<LalaReadiness>> getReadiness() async => _envelope(
    LalaReadiness(
      status: 'ok',
      checks: const <String, String>{'db': 'configured'},
      mode: const LalaRuntimeMode(
        overall: 'ok',
        data: 'db-backed',
        ai: 'disabled',
        speech: 'disabled',
        worker: 'dry-run',
      ),
    ),
  );

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async => _envelope(
    LalaPlacesResponse(
      count: 0,
      places: const <LalaPlace>[],
      query: const LalaPlacesQuery(
        lat: 37.2636,
        lng: 127.0286,
        radiusM: 3000,
        limit: 60,
        category: 'all',
        language: 'ko',
      ),
      source: 'db',
      locationEngine: 'postgis',
    ),
  );

  @override
  Future<LalaEnvelope<LalaWeather>> getWeather() async => _envelope(_weather());

  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() async => _envelope(
    const LalaIntervention(
      center: LalaCoordinate(lat: 37.2636, lng: 127.0286),
      radiusM: 3000,
      shouldIntervene: false,
      reason: 'ok',
      recommendedAction: '',
      source: 'db',
    ),
  );

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() async => _envelope(
    LalaDailyPlan(
      language: 'ko',
      center: const LalaCoordinate(lat: 37.2636, lng: 127.0286),
      radiusM: 3000,
      weather: _weather(),
      slots: const <LalaPlanSlot>[],
      source: 'db',
      // 저엔트로피 테스트 값(detect-secrets 허위 양성 회피; 실제 키/해시 아님).
      requestHash: 'test-routing-plan-hash',
      cacheKey: 'daily_plan:test-routing',
    ),
  );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used in cold-start routing');
}

class _LoadedPlacesBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async => _envelope(
    LalaPlacesResponse(
      count: 1,
      places: <LalaPlace>[_cafe()],
      query: const LalaPlacesQuery(
        lat: 35.16665,
        lng: 129.16792,
        radiusM: 2000,
        limit: 60,
        category: 'all',
        language: 'ko',
      ),
      source: 'db',
      locationEngine: 'postgis',
    ),
  );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'not used in search seed: ${invocation.memberName}',
  );
}

class _LoadedPlanBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() async => _envelope(
    LalaDailyPlan(
      language: 'ko',
      center: const LalaCoordinate(lat: 35.16665, lng: 129.16792),
      radiusM: 3000,
      weather: _weather(),
      slots: const <LalaPlanSlot>[
        LalaPlanSlot(period: 'morning', title: '해운대 산책 코스'),
      ],
      source: 'db',
      // 저엔트로피 테스트 값(detect-secrets 허위 양성 회피; 실제 키/해시 아님).
      requestHash: 'test-plan-request-hash',
      cacheKey: 'daily_plan:test-plan',
    ),
  );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'not used in plan seed: ${invocation.memberName}',
  );
}

LalaPlace _cafe() {
  return const LalaPlace(
    placeId: 'seed-test-cafe',
    name: '해운대 카페',
    nameKo: '해운대 카페',
    nameEn: 'Haeundae Cafe',
    category: 'restaurant',
    lat: 35.16,
    lng: 129.16,
    address: '부산광역시 해운대구',
    regionKo: '부산',
    regionEn: 'Busan',
    imageUrl: 'https://tong.visitkorea.or.kr/cms/resource/photo.jpg',
    distanceM: 320,
    source: 'db',
    upstreamSource: 'tour_api',
  );
}

LalaWeather _weather() {
  return LalaWeather(
    lat: 35.16665,
    lng: 129.16792,
    temp: '18°C',
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
    forecast: const <LalaForecastItem>[
      LalaForecastItem(time: '15:00', temp: '22C', icon: 'partly-cloudy'),
    ],
    outdoorStatus: 'good',
    force: false,
    source: 'db',
    location: 'Busan',
    recordTime: '2026-07-26T09:00:00+09:00',
    locationMatch: true,
  );
}

LalaEnvelope<T> _envelope<T>(T data) {
  return LalaEnvelope<T>(
    ok: true,
    data: data,
    meta: const <String, dynamic>{'request_id': 'test-request-id'},
    error: null,
    statusCode: 200,
    requestId: 'test-request-id',
  );
}

LalaEnvelope<Map<String, dynamic>> _rawEnvelope(Map<String, dynamic> data) {
  return _envelope<Map<String, dynamic>>(data);
}
