import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_remote.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('round-trips soft, hard, mobility, and docent preferences', () {
    final original = TravelPreferences(
      pace: TravelPace.relaxed,
      crowdTolerance: CrowdTolerance.quiet,
      walkingBand: WalkingBand.short,
      interests: const {TravelInterest.localFood, TravelInterest.history},
      travelStyles: const {TravelStyle.hiddenLocal},
      indoorOutdoorPreference: IndoorOutdoorPreference.indoor,
      weatherSensitivity: WeatherSensitivity.high,
      cuisines: const {FoodCuisine.korean, FoodCuisine.marketFood},
      foodAdventure: FoodAdventure.adventurous,
      dietaryModes: const {DietaryMode.halal},
      allergens: const {Allergen.shellfish},
      avoidIngredients: '고수',
      companions: const {TravelCompanion.friends},
      transportModes: const {TransportMode.transit, TransportMode.taxi},
      restFrequency: RestFrequency.frequent,
      maxOneWayMinutes: 60,
      maxTransfers: 1,
      avoidStairs: true,
      verifiedAccessibilityOnly: true,
      budgetBand: BudgetBand.special,
      maxWaitMinutes: 40,
      dayRhythm: DayRhythm.night,
      excludeClosingSoon: true,
      docentDepth: DocentDepth.deep,
      docentAutoplay: true,
      placeNameMode: PlaceNameMode.localized,
      narrationSpeed: 1.2,
      continueNarration: false,
      pronunciationHelp: true,
    );

    final decoded = TravelPreferences.fromJson(
      jsonDecode(jsonEncode(original.toJson())),
    );

    expect(decoded, original);
  });

  test('equal preference sets keep the same hash regardless of order', () {
    final first = TravelPreferences(
      interests: <TravelInterest>{
        TravelInterest.localFood,
        TravelInterest.history,
      },
      transportModes: <TransportMode>{
        TransportMode.walk,
        TransportMode.transit,
      },
    );
    final second = TravelPreferences(
      interests: <TravelInterest>{
        TravelInterest.history,
        TravelInterest.localFood,
      },
      transportModes: <TransportMode>{
        TransportMode.transit,
        TransportMode.walk,
      },
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test('rejects unknown schema and safely bounds malformed values', () {
    expect(
      TravelPreferences.fromJson(<String, Object>{'version': 99}),
      const TravelPreferences(),
    );

    final decoded = TravelPreferences.fromJson(<String, Object>{
      'version': TravelPreferences.schemaVersion,
      'soft': <String, Object>{
        'interests': <String>[
          ...TravelInterest.values.map((value) => value.name),
          'unknown',
        ],
        'max_one_way_minutes': 999,
        'max_transfers': 99,
      },
      'hard': <String, Object>{
        'avoid_ingredients': 'a' * 200,
        'max_wait_minutes': 999,
      },
      'locale': <String, Object>{'narration_speed': 8.0},
    });

    expect(decoded.interests, hasLength(TravelPreferences.maxInterests));
    expect(
      decoded.avoidIngredients,
      hasLength(TravelPreferences.maxAvoidIngredientsLength),
    );
    expect(decoded.maxOneWayMinutes, 30);
    expect(decoded.maxTransfers, 2);
    expect(decoded.maxWaitMinutes, 20);
    expect(decoded.narrationSpeed, 1.0);
  });

  test('persists locally and hydrates a fresh store', () async {
    final first = TravelPreferencesStore();
    await first.ensureLoaded();
    final next = first.value.copyWith(
      interests: const {TravelInterest.localFood},
      avoidStairs: true,
    );

    await first.save(next);
    final second = TravelPreferencesStore();
    await second.ensureLoaded();

    expect(second.value, next);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(kTravelPreferencesStorageKey), isNotNull);
  });

  test('falls back to defaults when local JSON is corrupt', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kTravelPreferencesStorageKey: '{bad json',
    });
    final store = TravelPreferencesStore();

    await store.ensureLoaded();

    expect(store.value, const TravelPreferences());
    expect(store.isLoaded, isTrue);
  });

  test(
    'adopts account preferences when the device has no local document',
    () async {
      const account = TravelPreferences(
        interests: {TravelInterest.history},
        pace: TravelPace.relaxed,
      );
      final remote = _MemoryRemote(account: account, revision: 3);
      final store = TravelPreferencesStore();

      await store.connectAccount(remote);

      expect(store.value, account);
      expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
      expect(store.serverRevision, 3);
    },
  );

  test(
    'does not silently overwrite differing device and account values',
    () async {
      final store = TravelPreferencesStore();
      await store.ensureLoaded();
      await store.save(
        const TravelPreferences(interests: {TravelInterest.localFood}),
      );
      final remote = _MemoryRemote(
        account: const TravelPreferences(interests: {TravelInterest.history}),
        revision: 4,
      );

      await store.connectAccount(remote);

      expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);
      expect(store.value.interests, {TravelInterest.localFood});

      await store.useAccountPreferences();
      expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
      expect(store.value.interests, {TravelInterest.history});
    },
  );

  test('uploads the explicit device choice with optimistic revision', () async {
    final store = TravelPreferencesStore();
    await store.ensureLoaded();
    const device = TravelPreferences(interests: {TravelInterest.localFood});
    await store.save(device);
    final remote = _MemoryRemote(
      account: const TravelPreferences(interests: {TravelInterest.history}),
      revision: 5,
    );
    await store.connectAccount(remote);

    await store.saveDevicePreferencesToAccount();

    expect(remote.lastExpectedRevision, 5);
    expect(remote.account, device);
    expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
    expect(store.serverRevision, 6);
  });
}

class _MemoryRemote implements TravelPreferencesRemote {
  _MemoryRemote({this.account, this.revision = 0});

  TravelPreferences? account;
  int revision;
  int? lastExpectedRevision;

  @override
  Future<TravelPreferencesRemoteDocument?> get() async {
    final value = account;
    if (value == null) return null;
    return TravelPreferencesRemoteDocument(
      preferences: value,
      revision: revision,
      updatedAt: '2026-09-02T00:00:00Z',
    );
  }

  @override
  Future<TravelPreferencesRemoteDocument> put({
    required TravelPreferences preferences,
    required int expectedRevision,
  }) async {
    lastExpectedRevision = expectedRevision;
    if (expectedRevision != revision) throw StateError('revision conflict');
    account = preferences;
    revision += 1;
    return TravelPreferencesRemoteDocument(
      preferences: preferences,
      revision: revision,
      updatedAt: '2026-09-02T00:01:00Z',
    );
  }
}
