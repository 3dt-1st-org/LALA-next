import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/core/state/saved_place_store.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/settings/data/privacy_settings_store.dart';
import 'package:lala_next_app/features/settings/presentation/pages/privacy_location_page.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    OnboardingState.applySnapshot(
      const OnboardingSnapshot(completed: true, language: 'ko'),
    );
    SavedPlaceStore.clear();
  });

  tearDown(() {
    OnboardingState.reset();
    SavedPlaceStore.clear();
  });

  testWidgets('S-58 persists the app location recommendation choice', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final privacyStore = PrivacySettingsStore();
    await privacyStore.ensureLoaded();

    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyLocationPage(
          privacyStore: privacyStore,
          preferencesStore: TravelPreferencesStore(),
          tripLibraryStore: TripLibraryStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('privacy-location-page')), findsOneWidget);
    expect(find.text('개인정보와 위치'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('privacy-location-toggle')));
    await tester.pumpAndSettle();

    expect(privacyStore.locationRecommendationsEnabled, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool(kLocationRecommendationsEnabledKey), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('S-58 clears only confirmed guest device personalization', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final privacyStore = PrivacySettingsStore();
    final preferencesStore = TravelPreferencesStore();
    final tripLibraryStore = TripLibraryStore();
    await Future.wait(<Future<void>>[
      privacyStore.ensureLoaded(),
      preferencesStore.ensureLoaded(),
      tripLibraryStore.ensureLoaded(),
    ]);
    SavedPlaceStore.add('saved-place');

    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyLocationPage(
          privacyStore: privacyStore,
          preferencesStore: preferencesStore,
          tripLibraryStore: tripLibraryStore,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('privacy-clear-guest-data')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('privacy-clear-guest-data')));
    await tester.pumpAndSettle();

    expect(find.text('이 기기의 여행 설정을 지울까요?'), findsOneWidget);
    await tester.tap(find.text('기기 데이터 지우기'));
    await tester.pumpAndSettle();

    expect(SavedPlaceStore.current, isEmpty);
    expect(OnboardingState.isCompleted, isFalse);
    expect(privacyStore.locationRecommendationsEnabled, isFalse);
    expect(tester.takeException(), isNull);
  });
}
