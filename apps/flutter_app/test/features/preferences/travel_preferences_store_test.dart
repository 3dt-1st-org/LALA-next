import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
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
}
