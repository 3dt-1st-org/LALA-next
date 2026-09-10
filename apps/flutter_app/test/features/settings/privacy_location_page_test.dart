import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/core/state/saved_place_store.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/settings/data/privacy_settings_store.dart';
import 'package:lala_next_app/features/settings/presentation/pages/privacy_location_page.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';

const String _platformDocKey = 'flutter.$kTravelPreferencesStorageKey';

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

  testWidgets(
    'a thrown travel-preferences remove also skips later destructive steps; retry completes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final platform = _AckFalseStore();
      SharedPreferencesStorePlatform.instance = platform;
      final privacyStore = PrivacySettingsStore();
      final preferencesStore = TravelPreferencesStore();
      final tripLibraryStore = TripLibraryStore();
      await preferencesStore.ensureLoaded();
      await preferencesStore.save(
        const TravelPreferences(interests: {TravelInterest.localFood}),
      );
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

      // The real platform THROWS on the document removal (not a false ack).
      platform.failNextRemove(_platformDocKey);
      await tester.tap(find.byKey(const ValueKey('privacy-clear-guest-data')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('기기 데이터 지우기'));
      await tester.pumpAndSettle();

      expect(find.text('기기 데이터를 모두 지우지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      expect(find.text('이 기기의 여행 데이터가 삭제됐어요.'), findsNothing);
      expect(SavedPlaceStore.current, isNotEmpty);
      expect(OnboardingState.isCompleted, isTrue);
      expect((await platform.getAll()).containsKey(_platformDocKey), isTrue);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('privacy-clear-guest-data')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('기기 데이터 지우기'));
      await tester.pumpAndSettle();

      expect(find.text('이 기기의 여행 데이터가 삭제됐어요.'), findsOneWidget);
      expect(SavedPlaceStore.current, isEmpty);
      expect((await platform.getAll()).containsKey(_platformDocKey), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a failed travel-preferences clear surfaces the error and skips later steps; retry completes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final platform = _AckFalseStore();
      SharedPreferencesStorePlatform.instance = platform;
      final privacyStore = PrivacySettingsStore();
      final preferencesStore = TravelPreferencesStore();
      final tripLibraryStore = TripLibraryStore();
      await preferencesStore.ensureLoaded();
      await preferencesStore.save(
        const TravelPreferences(interests: {TravelInterest.localFood}),
      );
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

      // The real platform acknowledges the document removal as failed.
      platform.ackFalseNextRemove(_platformDocKey);
      await tester.tap(find.byKey(const ValueKey('privacy-clear-guest-data')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('기기 데이터 지우기'));
      await tester.pumpAndSettle();

      expect(find.text('기기 데이터를 모두 지우지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      expect(find.text('이 기기의 여행 데이터가 삭제됐어요.'), findsNothing);
      // Later destructive clear steps never ran: saved places and the
      // onboarding completion are retained alongside the un-deleted document.
      expect(SavedPlaceStore.current, isNotEmpty);
      expect(OnboardingState.isCompleted, isTrue);
      expect((await platform.getAll()).containsKey(_platformDocKey), isTrue);

      // Retry on a healthy platform completes the whole clear.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('privacy-clear-guest-data')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('기기 데이터 지우기'));
      await tester.pumpAndSettle();

      expect(find.text('이 기기의 여행 데이터가 삭제됐어요.'), findsOneWidget);
      expect(SavedPlaceStore.current, isEmpty);
      expect(OnboardingState.isCompleted, isFalse);
      expect((await platform.getAll()).containsKey(_platformDocKey), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

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

/// In-memory platform store whose next removal for an armed key can
/// acknowledge failure (`false`, no throw), mirroring the documented plugin
/// failure mode at the real persistence seam.
class _AckFalseStore extends InMemorySharedPreferencesStore {
  _AckFalseStore() : super.empty();

  String? _ackFalseRemoveKey;
  String? _failRemoveKey;

  void ackFalseNextRemove(String key) => _ackFalseRemoveKey = key;

  /// One-shot THROWN failure on the next removal of [key].
  void failNextRemove(String key) => _failRemoveKey = key;

  @override
  Future<bool> remove(String key) async {
    if (_failRemoveKey == key) {
      _failRemoveKey = null;
      throw StateError('storage remove failed for $key');
    }
    if (_ackFalseRemoveKey == key) {
      _ackFalseRemoveKey = null;
      return false;
    }
    return super.remove(key);
  }
}
