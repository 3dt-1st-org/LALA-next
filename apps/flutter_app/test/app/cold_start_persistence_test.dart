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
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/app/bootstrap.dart';
import 'package:lala_next_app/app/lala_main_shell.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/persistence/cross_tab_preferences.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_controller.dart';
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/core/routing/lala_router.dart';
import 'package:lala_next_app/core/state/plan_context_store.dart';
import 'package:lala_next_app/core/state/selected_place_store.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/onboarding/presentation/pages/splash_page.dart';
import 'package:lala_next_app/features/home/home_page.dart';
import 'package:lala_next_app/features/plan/presentation/pages/plan_page.dart';
import 'package:lala_next_app/features/search/presentation/pages/search_page.dart';
import 'package:lala_next_app/manual_location_options.dart';

import '../features/docent/inert_docent_audio_player.dart';

void main() {
  // The onboarding + region + cross-tab holders are process-local singletons.
  // Detach + reset before/after each case so an attached prefs, a completed
  // flag, or a persisted selection can never leak between tests.
  setUp(() {
    // Prevent SharedPreferences.getInstance() (called by createDefault() when
    // a test doesn't inject crossTabPreferences) from hanging on the missing
    // platform channel. Resets the singleton cache between tests.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    OnboardingState.detachPersistence();
    RegionContextStore.detachPersistence();
    OnboardingState.reset();
    RegionContextStore.clear();
    CrossTabPersistence.detach();
    SelectedPlaceStore.clear();
    PlanContextStore.clear();
  });

  tearDown(() {
    OnboardingState.detachPersistence();
    RegionContextStore.detachPersistence();
    OnboardingState.reset();
    RegionContextStore.clear();
    CrossTabPersistence.detach();
    SelectedPlaceStore.clear();
    PlanContextStore.clear();
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

  group('bootstrapAppState factory failure safety', () {
    test(
      'default-preferences factory failure degrades to a clean first run (never throws)',
      () async {
        // Simulates SharedPreferences plugin initialization throwing — something
        // createDefault() itself cannot be made to do, hence the factory seam.
        await bootstrapAppState(
          preferencesFactory: () async =>
              throw StateError('plugin init failed'),
        );
        expect(OnboardingState.isCompleted, isFalse);
        expect(OnboardingState.language, 'ko');
        expect(OnboardingState.touristType, OnboardingTouristType.localTourist);
        expect(RegionContextStore.current, isNull);
      },
    );

    test(
      'default-preferences factory failure leaves the session usable (non-durable)',
      () async {
        await bootstrapAppState(
          preferencesFactory: () async =>
              throw StateError('plugin init failed'),
        );
        // Persistence is detached, so completion holds for this session only.
        await OnboardingState.completeAndFlush();
        expect(OnboardingState.isCompleted, isTrue);
      },
    );
  });

  group('setAndFlush write ordering', () {
    test(
      'setAndFlush awaits a delayed write (contrast with best-effort set)',
      () async {
        final backend = _DelayedBackend();
        await bootstrapAppState(preferences: OnboardingPreferences(backend));
        final key = '${kOnboardingStoragePrefix}manualRegionId';

        // Best-effort set is fire-and-forget: the delayed write has not settled.
        RegionContextStore.set(RegionContext.manual(_busanHaeundae()));
        expect(backend.store[key], isNull);

        await _drainWrites();
        expect(backend.store[key], 'busan-haeundae');
        backend.store.clear();

        // setAndFlush returns only after the delayed write has settled.
        await RegionContextStore.setAndFlush(
          RegionContext.manual(_busanHaeundae()),
        );
        expect(backend.store[key], 'busan-haeundae');
      },
    );

    test(
      'setAndFlush durably writes the manual id before the completion gate flips',
      () async {
        final backend = _DelayedBackend();
        await bootstrapAppState(preferences: OnboardingPreferences(backend));
        final key = '${kOnboardingStoragePrefix}manualRegionId';

        // Same order as onboarding completion: durable region write first, then
        // the completion slice, then the gate flips.
        await RegionContextStore.setAndFlush(
          RegionContext.manual(_busanHaeundae()),
        );
        // The delayed write settled BEFORE setAndFlush returned, so the manual id
        // is already durable here — it cannot race with the completion write or
        // the router redirect that follows completeAndFlush.
        expect(backend.store[key], 'busan-haeundae');

        await OnboardingState.completeAndFlush();
        expect(OnboardingState.isCompleted, isTrue);
        // The completion slice is durable too.
        expect(backend.store['${kOnboardingStoragePrefix}completed'], isTrue);
      },
    );

    test(
      'setAndFlush(current) clears a prior manual id durably before completion',
      () async {
        final key = '${kOnboardingStoragePrefix}manualRegionId';
        final backend = _DelayedBackend({key: 'busan-haeundae'});
        await bootstrapAppState(preferences: OnboardingPreferences(backend));
        // The seed restored into memory; the persisted id still sits in the store.
        expect(RegionContextStore.current?.regionId, 'busan-haeundae');

        // Choosing current must clear the prior manual id (privacy) and the clear
        // must settle before the completion gate can flip / navigation runs.
        await RegionContextStore.setAndFlush(
          RegionContext.current(lat: 37.5665, lng: 126.978),
        );
        expect(backend.store[key], isNull);

        await OnboardingState.completeAndFlush();
        expect(OnboardingState.isCompleted, isTrue);
        expect(RegionContextStore.current?.source, RegionSource.current);
      },
    );

    test(
      'setAndFlush keeps the in-memory context usable when the region write fails',
      () async {
        await bootstrapAppState(
          preferences: OnboardingPreferences(_FailingBackend()),
        );
        // Must not throw to the UI; the in-memory context stays authoritative.
        // The choice is non-durable (write failed) but the session still works.
        await RegionContextStore.setAndFlush(
          RegionContext.manual(_busanHaeundae()),
        );
        expect(RegionContextStore.current?.regionId, 'busan-haeundae');
        expect(RegionContextStore.current?.source, RegionSource.manual);
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
          docentExperienceController: DocentExperienceController(
            backendFactory: (config) => _NoopBackend(),
            baseConfig: const LalaAppConfig(baseUri: 'http://api.test'),
            player: InertDocentAudioPlayer(),
          ),
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

    test(
      'persisted English restores from the language SSOT on cold restart',
      () async {
        final backend = _MemoryBackend();
        await OnboardingPreferences(backend).writeOnboarding(
          completed: true,
          language: 'ko',
          touristTypeCode: kTouristTypeCodeLocal,
        );
        await bootstrapAppState(preferences: OnboardingPreferences(backend));

        OnboardingState.selectLanguage('en');
        await _drainWrites();

        // Simulate a new process without clearing the durable backend.
        OnboardingState.detachPersistence();
        RegionContextStore.detachPersistence();
        OnboardingState.reset();
        RegionContextStore.clear();
        await bootstrapAppState(preferences: OnboardingPreferences(backend));
        expect(OnboardingState.language, 'en');
        expect(OnboardingState.languageListenable.value, 'en');
      },
    );

    testWidgets(
      'restored manual Busan centers an empty Home map without requesting location',
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

        const initialConfig = LalaAppConfig(baseUri: 'http://api.test');
        final manualRegion = _busanHaeundae();
        final configs = <LalaAppConfig>[];
        final locationProvider = _CountingLocationProvider(
          const LalaLocationResult.found(
            LalaLocation(lat: 37.5665, lng: 126.978),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: LalaHomePage(
              backendFactory: (config) {
                configs.add(config);
                return _NoopBackend();
              },
              initialConfig: initialConfig,
              locationProvider: locationProvider,
              recommendationRecoveryDelays: const <Duration>[],
              authControllerFactory: createLalaAuthController,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(locationProvider.requests, 0);
        expect(configs.last.lat, 35.16665);
        expect(configs.last.lng, 129.16792);
        expect(RegionContextStore.current?.regionId, 'busan-haeundae');
        expect(RegionContextStore.current?.source, RegionSource.manual);
        expect(
          find.byKey(
            ValueKey(
              'lala-map-fallback-center-'
              '${manualRegion.lat.toStringAsFixed(4)}-'
              '${manualRegion.lng.toStringAsFixed(4)}',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            ValueKey(
              'lala-map-fallback-center-'
              '${initialConfig.lat.toStringAsFixed(4)}-'
              '${initialConfig.lng.toStringAsFixed(4)}',
            ),
          ),
          findsNothing,
        );

        // Dispose Home/auth/map state explicitly so no controller or timer can
        // keep the focused Flutter test process alive.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
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

  group('cross-tab persistence + cold-start hydration', () {
    test(
      'restores the persisted selected-place id into SelectedPlaceStore',
      () async {
        final key = '${kCrossTabStoragePrefix}selectedPlaceId';
        final backend = _MemoryBackend(<String, Object?>{
          key: 'seed-test-cafe',
        });
        await bootstrapAppState(
          preferences: OnboardingPreferences(backend),
          crossTabPreferences: CrossTabPreferences(backend),
        );
        expect(SelectedPlaceStore.current, 'seed-test-cafe');
      },
    );

    test('persisted plan DTO round-trips on cold restart', () async {
      final backend = _MemoryBackend();
      final plan = _sampleCrossTabPlan();
      // Simulate a prior session's write-through.
      await CrossTabPreferences(backend).writePlan(plan);

      await bootstrapAppState(
        preferences: OnboardingPreferences(backend),
        crossTabPreferences: CrossTabPreferences(backend),
      );

      final restored = PlanContextStore.current;
      expect(restored, isNotNull);
      expect(restored!.language, plan.language);
      expect(restored.center.lat, plan.center.lat);
      expect(restored.center.lng, plan.center.lng);
      expect(restored.radiusM, plan.radiusM);
      expect(restored.source, plan.source);
      expect(restored.requestHash, plan.requestHash);
      expect(restored.cacheKey, plan.cacheKey);
      expect(restored.slots.length, plan.slots.length);
      expect(restored.slots.first.period, plan.slots.first.period);
      expect(restored.slots.first.title, plan.slots.first.title);
      expect(restored.slots.first.place?.placeId, 'seed-test-cafe');
      expect(restored.slots.first.place?.name, '해운대 카페');
      expect(restored.weather.lat, plan.weather.lat);
      expect(restored.weather.temp, plan.weather.temp);
    });

    test(
      'corrupt plan JSON degrades to null (graceful; app still starts; no throw)',
      () async {
        final planKey = '${kCrossTabStoragePrefix}plan';
        final corruptInputs = <String>[
          '{not valid json', // malformed JSON
          '{"v": 1}', // missing 'plan'
          '{"plan": {}}', // missing 'v'
          '{"v": "bad", "plan": {}}', // wrong 'v' type
          '', // empty string
        ];
        for (final corrupt in corruptInputs) {
          CrossTabPersistence.detach();
          SelectedPlaceStore.clear();
          PlanContextStore.clear();
          final backend = _MemoryBackend(<String, Object?>{planKey: corrupt});
          await bootstrapAppState(
            preferences: OnboardingPreferences(backend),
            crossTabPreferences: CrossTabPreferences(backend),
          );
          expect(
            PlanContextStore.current,
            isNull,
            reason: 'should degrade to null for input: "$corrupt"',
          );
        }
      },
    );

    test('version-mismatch plan degrades to null', () async {
      final planKey = '${kCrossTabStoragePrefix}plan';
      final backend = _MemoryBackend(<String, Object>{
        planKey: '{"v": 99, "plan": {"language": "ko"}}',
      });
      await bootstrapAppState(
        preferences: OnboardingPreferences(backend),
        crossTabPreferences: CrossTabPreferences(backend),
      );
      expect(PlanContextStore.current, isNull);
    });

    test(
      'stale hydration is suppressed by the epoch guard (fresh set during load wins)',
      () async {
        final loadStarted = Completer<void>();
        final gate = Completer<void>();
        final key = '${kCrossTabStoragePrefix}selectedPlaceId';
        final backend = _GatedBackend(
          seed: <String, Object?>{key: 'stale-id'},
          loadStarted: loadStarted,
          gate: gate,
        );

        final boot = bootstrapAppState(
          preferences: OnboardingPreferences(backend),
          crossTabPreferences: CrossTabPreferences(backend),
        );

        // Wait until the cross-tab load is in flight (listeners are attached,
        // the persisted-id read is blocked on the gate).
        await loadStarted.future;

        // A fresh selection lands while the stale persisted id is still loading.
        SelectedPlaceStore.set('fresh-id');

        // Release the load; the stale persisted id must NOT clobber the fresh one.
        gate.complete();
        await boot;

        expect(SelectedPlaceStore.current, 'fresh-id');
      },
    );

    test(
      'privacy: writes only lala.crosstab.v1.* keys; no coordinate/PII keys',
      () async {
        final backend = _MemoryBackend();
        await bootstrapAppState(
          preferences: OnboardingPreferences(backend),
          crossTabPreferences: CrossTabPreferences(backend),
        );
        SelectedPlaceStore.set('seed-test-cafe');
        PlanContextStore.set(_sampleCrossTabPlan());
        await _drainWrites();

        final crossTabKeys = backend.store.keys
            .where((k) => k.startsWith(kCrossTabStoragePrefix))
            .toSet();
        // Exactly the two sanctioned cross-tab keys — no coordinate/PII keys.
        expect(crossTabKeys, {
          '${kCrossTabStoragePrefix}selectedPlaceId',
          '${kCrossTabStoragePrefix}plan',
        });

        // No key outside the sanctioned onboarding/crosstab prefixes.
        for (final key in backend.store.keys) {
          final sanctioned =
              key.startsWith(kOnboardingStoragePrefix) ||
              key.startsWith(kCrossTabStoragePrefix);
          expect(
            sanctioned,
            isTrue,
            reason: 'unexpected non-sanctioned key: $key',
          );
        }
      },
    );

    test(
      'clearing selection/plan removes the key; clean store hydrates to null',
      () async {
        final backend = _MemoryBackend();
        await bootstrapAppState(
          preferences: OnboardingPreferences(backend),
          crossTabPreferences: CrossTabPreferences(backend),
        );
        // A clean store hydrates to nothing.
        expect(SelectedPlaceStore.current, isNull);
        expect(PlanContextStore.current, isNull);

        // Selecting persists the id.
        final idKey = '${kCrossTabStoragePrefix}selectedPlaceId';
        SelectedPlaceStore.set('seed-test-cafe');
        await _drainWrites();
        expect(backend.store[idKey], 'seed-test-cafe');

        // Clearing removes the key (null => remove).
        SelectedPlaceStore.clear();
        await _drainWrites();
        expect(backend.store.containsKey(idKey), isFalse);

        // Same contract for the plan.
        final planKey = '${kCrossTabStoragePrefix}plan';
        PlanContextStore.set(_sampleCrossTabPlan());
        await _drainWrites();
        expect(backend.store[planKey], isNotNull);
        PlanContextStore.clear();
        await _drainWrites();
        expect(backend.store.containsKey(planKey), isFalse);
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

/// In-memory backend for deterministic, plugin-free tests. Implements both
/// backends so a single instance backs onboarding + cross-tab in a test.
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

/// OnboardingPreferencesBackend whose store is permanently unavailable.
class _FailingBackend
    implements OnboardingPreferencesBackend, CrossTabPreferencesBackend {
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

/// OnboardingPreferencesBackend whose every call yields to the event loop via a
/// zero-delay timer instead of running inline. That async gap is enough to prove
/// awaited (setAndFlush) vs fire-and-forget (set) ordering deterministically,
/// without flaky wall-clock timing: an awaited write settles before the caller
/// resumes (it is in the store the instant the await returns), while a
/// fire-and-forget write is still pending the instant set() returns.
class _DelayedBackend
    implements OnboardingPreferencesBackend, CrossTabPreferencesBackend {
  _DelayedBackend([Map<String, Object?>? seed])
    : store = Map<String, Object?>.from(seed ?? <String, Object?>{});

  final Map<String, Object?> store;

  @override
  Future<bool?> getBool(String key) async {
    await Future<void>.delayed(Duration.zero);
    return store[key] as bool?;
  }

  @override
  Future<String?> getString(String key) async {
    await Future<void>.delayed(Duration.zero);
    return store[key] as String?;
  }

  @override
  Future<void> setBool(String key, bool value) async {
    await Future<void>.delayed(Duration.zero);
    store[key] = value;
  }

  @override
  Future<void> setString(String key, String value) async {
    await Future<void>.delayed(Duration.zero);
    store[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    await Future<void>.delayed(Duration.zero);
    store.remove(key);
  }
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
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({String? selectedPlaceId}) async => _envelope(
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
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({String? selectedPlaceId}) async => _envelope(
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

/// A plan exercising the nested types the app-owned encoder must round-trip
/// (center, weather with dust/forecast, and a slot carrying a place).
LalaDailyPlan _sampleCrossTabPlan() {
  return LalaDailyPlan(
    language: 'ko',
    center: const LalaCoordinate(lat: 35.16665, lng: 129.16792),
    radiusM: 3000,
    weather: _weather(),
    slots: <LalaPlanSlot>[
      LalaPlanSlot(period: 'morning', title: '해운대 산책 코스', place: _cafe()),
    ],
    source: 'db',
    // 저엔트로피 테스트 값(detect-secrets 허위 양성 회피; 실제 키/해시 아님).
    requestHash: 'test-crosstab-req-hash',
    cacheKey: 'daily_plan:crosstab-test',
  );
}

/// Backend whose cross-tab reads block on a [gate] completer. Used to model the
/// stale-hydration race deterministically: the cross-tab load is held in flight
/// while a fresh set() lands, proving the epoch guard suppresses the stale
/// persisted value. Implements both backends so a single instance backs
/// onboarding + cross-tab.
class _GatedBackend
    implements OnboardingPreferencesBackend, CrossTabPreferencesBackend {
  _GatedBackend({
    Map<String, Object?>? seed,
    required this.loadStarted,
    required this.gate,
  }) : store = Map<String, Object?>.from(seed ?? <String, Object?>{});

  final Map<String, Object?> store;
  final Completer<void> loadStarted;
  final Completer<void> gate;

  @override
  Future<bool?> getBool(String key) async => store[key] as bool?;

  @override
  Future<String?> getString(String key) async {
    if (key.startsWith(kCrossTabStoragePrefix)) {
      // Capture at call time so a listener write during the gate window does
      // not rewrite what the in-flight load returns — the real race the epoch
      // guard protects against.
      final captured = store[key] as String?;
      if (!loadStarted.isCompleted) {
        loadStarted.complete();
      }
      await gate.future;
      return captured;
    }
    return store[key] as String?;
  }

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
