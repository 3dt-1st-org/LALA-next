import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lala_next_app/app/lala_app.dart';
import 'package:lala_next_app/app/migrate_local_preferences.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/state/saved_place_store.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_controller.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/home_screen.dart';
import 'package:lala_next_app/onboarding_screen.dart';
import 'package:lala_next_app/manual_location_options.dart';
import 'package:lala_next_app/features/home/discovery_page.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/features/settings/data/privacy_settings_store.dart';
import 'features/docent/inert_docent_audio_player.dart';

class _NoNetworkBackend implements LalaBackend {
  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected backend call: ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OnboardingState.detachPersistence();
    OnboardingState.reset();
    RegionContextStore.detachPersistence();
    RegionContextStore.clear();
    SavedPlaceStore.clear();
  });

  test(
    'legacy preferences migrate once and keep the original document',
    () async {
      final old = jsonEncode({
        'completed': true,
        'country': 'JP',
        'locale': 'ja',
        'styles': ['history', 'food'],
        'region': manualLocationOptions.first.id,
        'speed': 1.2,
        'auto': true,
        'location': false,
      });
      SharedPreferences.setMockInitialValues({'lala.preferences.v1': old});
      await migrateLocalPreferences();
      expect(OnboardingState.isCompleted, isTrue);
      expect(OnboardingState.language, 'ja');
      expect(
        RegionContextStore.current!.regionId,
        manualLocationOptions.first.id,
      );
      expect(TravelPreferencesStore.instance.value.interests, {
        TravelInterest.history,
        TravelInterest.localFood,
      });
      expect(TravelPreferencesStore.instance.value.narrationSpeed, 1.2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('lala.preferences.v1'), old);
      expect(prefs.containsKey(kTravelPreferencesStorageKey), isTrue);
      await migrateLocalPreferences();
      expect(prefs.getString('lala.preferences.v1'), old);
    },
  );

  testWidgets(
    'local welcome invokes injected sign-in and advances only on success',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            onComplete: (_) {},
            initialLanguage: 'en',
            onSignIn: () async => ++attempts > 1,
          ),
        ),
      );
      final button = find.widgetWithText(OutlinedButton, 'Sign in');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(find.byKey(const ValueKey('country-JP')), findsNothing);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('country-JP')), findsOneWidget);
    },
  );

  testWidgets('home respects location opt-out before issuing place requests', (
    tester,
  ) async {
    await PrivacySettingsStore.instance.setLocationRecommendationsEnabled(
      false,
    );
    RegionContextStore.set(RegionContext.current(lat: 1, lng: 2));
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryPage(
          initialConfig: const LalaAppConfig(
            baseUri: 'https://example.invalid',
          ),
          locationProvider: const GeolocatorLalaLocationProvider(),
          backendFactory: (_) {
            calls++;
            return _NoNetworkBackend();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(RegionContextStore.current, isNull);
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ko', 'en', 'ja', 'zh-Hans', 'zh-Hant']) {
    for (final width in [340.0, 768.0, 1440.0]) {
      testWidgets('local shell layout $language at $width', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        OnboardingState.markCompleted();
        OnboardingState.selectLanguage(language);
        const config = LalaAppConfig(baseUri: 'https://example.invalid');
        final controller = DocentExperienceController(
          backendFactory: (_) => _NoNetworkBackend(),
          baseConfig: config,
          player: InertDocentAudioPlayer(),
        );
        await tester.pumpWidget(
          LalaApp(
            useLocalDesign: true,
            initialConfig: config,
            backendFactory: (_) => _NoNetworkBackend(),
            docentExperienceController: controller,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'home $language $width');
        for (final tab in ['map', 'plan', 'profile']) {
          await tester.tap(find.byKey(ValueKey('nav-$tab')));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$tab $language $width',
          );
        }
        await tester.tap(find.byKey(const ValueKey('profile-settings-entry')));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'settings $language $width',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.dispose();
      });
    }
  }

  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'production local home routes to server-backed settings at width $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        OnboardingState.markCompleted();
        const config = LalaAppConfig(baseUri: 'https://example.invalid');
        final controller = DocentExperienceController(
          backendFactory: (_) => _NoNetworkBackend(),
          baseConfig: config,
          player: InertDocentAudioPlayer(),
        );
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: LalaApp(
              useLocalDesign: true,
              initialConfig: config,
              backendFactory: (_) => _NoNetworkBackend(),
              docentExperienceController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DiscoveryHome), findsOneWidget);
        expect(find.byIcon(Icons.info_outline), findsOneWidget);
        expect(find.text('둘러보기 →'), findsNothing);
        expect(find.text('여행 계획 중'), findsNothing);
        expect(find.text('오늘의 여행'), findsNothing);

        expect(find.byKey(const ValueKey('nav-local-signals')), findsNothing);
        expect(find.byType(NavigationDestination), findsNWidgets(4));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('nav-profile')));
        await tester.pumpAndSettle();
        expect(find.byType(DiscoveryHome).hitTestable(), findsNothing);
        expect(find.text('나의 여행 설정'), findsNothing);
        expect(
          find.byKey(const ValueKey('profile-settings-entry')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('profile-community-entry')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('profile-community-chat-entry')),
          findsNothing,
        );
        final router = GoRouter.of(
          tester.element(find.byKey(const ValueKey('profile-page'))),
        );
        await tester.tap(find.byKey(const ValueKey('profile-settings-entry')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('settings-page')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('profile-saved-places-entry')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('profile-past-trips-entry')),
          findsNothing,
        );
        router.pop();
        await tester.pumpAndSettle();
        expect(find.text('나의 여행 설정'), findsNothing);
        for (final deferred in [
          '/local-signals',
          '/local-signals/contribute',
          '/community',
          '/community/chat',
        ]) {
          router.go(deferred);
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/home');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.dispose();
      },
    );
  }
}
