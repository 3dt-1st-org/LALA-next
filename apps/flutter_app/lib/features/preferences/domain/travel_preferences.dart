import 'package:flutter/foundation.dart';

enum TravelPace { relaxed, balanced, packed }

enum CrowdTolerance { quiet, balanced, popular }

enum WalkingBand { short, medium, long }

enum TravelInterest {
  localFood,
  cafe,
  history,
  arts,
  nature,
  walk,
  night,
  shopping,
  market,
  festival,
  handsOn,
  photography,
}

enum TravelStyle {
  famous,
  hiddenLocal,
  residentFavorite,
  newPlaces,
  revisit,
  spontaneous,
}

enum IndoorOutdoorPreference { indoor, balanced, outdoor }

enum WeatherSensitivity { low, medium, high }

enum FoodCuisine { korean, streetFood, cafeDessert, marketFood, worldCuisine }

enum FoodAdventure { familiar, balanced, adventurous }

enum DietaryMode { vegetarian, vegan, halal, kosher }

enum Allergen { nuts, shellfish, dairy, eggs, gluten, soy }

enum TravelCompanion { solo, partner, friends, family, children, senior, pet }

enum TransportMode { walk, transit, taxi, car, bicycle }

enum RestFrequency { low, balanced, frequent }

enum BudgetBand { value, balanced, special }

enum DayRhythm { morning, daytime, night }

enum DocentDepth { short, standard, deep }

enum PlaceNameMode { localized, localizedWithKorean, korean }

/// Versioned, user-declared recommendation preferences.
///
/// Logto owns authentication only. This model deliberately contains no Logto
/// claims and does not infer sensitive constraints from activity. Hard constraints
/// are stored only when the user explicitly selects them.
@immutable
class TravelPreferences {
  const TravelPreferences({
    this.pace = TravelPace.balanced,
    this.crowdTolerance = CrowdTolerance.balanced,
    this.walkingBand = WalkingBand.medium,
    this.interests = const <TravelInterest>{},
    this.travelStyles = const <TravelStyle>{},
    this.indoorOutdoorPreference = IndoorOutdoorPreference.balanced,
    this.weatherSensitivity = WeatherSensitivity.medium,
    this.cuisines = const <FoodCuisine>{},
    this.foodAdventure = FoodAdventure.balanced,
    this.dietaryModes = const <DietaryMode>{},
    this.allergens = const <Allergen>{},
    this.avoidIngredients = '',
    this.companions = const <TravelCompanion>{TravelCompanion.solo},
    this.transportModes = const <TransportMode>{
      TransportMode.walk,
      TransportMode.transit,
    },
    this.restFrequency = RestFrequency.balanced,
    this.maxOneWayMinutes = 30,
    this.maxTransfers = 2,
    this.avoidStairs = false,
    this.wheelchairAccess = false,
    this.strollerAccess = false,
    this.verifiedAccessibilityOnly = false,
    this.budgetBand = BudgetBand.balanced,
    this.maxWaitMinutes = 20,
    this.dayRhythm = DayRhythm.daytime,
    this.excludeClosingSoon = true,
    this.docentDepth = DocentDepth.standard,
    this.docentAutoplay = false,
    this.placeNameMode = PlaceNameMode.localizedWithKorean,
    this.narrationSpeed = 1.0,
    this.continueNarration = true,
    this.pronunciationHelp = false,
  });

  static const int schemaVersion = 1;
  static const int maxInterests = 5;
  static const int maxTravelStyles = 3;
  static const int maxCuisines = 4;
  static const int maxAvoidIngredientsLength = 120;

  final TravelPace pace;
  final CrowdTolerance crowdTolerance;
  final WalkingBand walkingBand;
  final Set<TravelInterest> interests;
  final Set<TravelStyle> travelStyles;
  final IndoorOutdoorPreference indoorOutdoorPreference;
  final WeatherSensitivity weatherSensitivity;
  final Set<FoodCuisine> cuisines;
  final FoodAdventure foodAdventure;
  final Set<DietaryMode> dietaryModes;
  final Set<Allergen> allergens;
  final String avoidIngredients;
  final Set<TravelCompanion> companions;
  final Set<TransportMode> transportModes;
  final RestFrequency restFrequency;
  final int maxOneWayMinutes;
  final int maxTransfers;
  final bool avoidStairs;
  final bool wheelchairAccess;
  final bool strollerAccess;
  final bool verifiedAccessibilityOnly;
  final BudgetBand budgetBand;
  final int maxWaitMinutes;
  final DayRhythm dayRhythm;
  final bool excludeClosingSoon;
  final DocentDepth docentDepth;
  final bool docentAutoplay;
  final PlaceNameMode placeNameMode;
  final double narrationSpeed;
  final bool continueNarration;
  final bool pronunciationHelp;

  TravelPreferences copyWith({
    TravelPace? pace,
    CrowdTolerance? crowdTolerance,
    WalkingBand? walkingBand,
    Set<TravelInterest>? interests,
    Set<TravelStyle>? travelStyles,
    IndoorOutdoorPreference? indoorOutdoorPreference,
    WeatherSensitivity? weatherSensitivity,
    Set<FoodCuisine>? cuisines,
    FoodAdventure? foodAdventure,
    Set<DietaryMode>? dietaryModes,
    Set<Allergen>? allergens,
    String? avoidIngredients,
    Set<TravelCompanion>? companions,
    Set<TransportMode>? transportModes,
    RestFrequency? restFrequency,
    int? maxOneWayMinutes,
    int? maxTransfers,
    bool? avoidStairs,
    bool? wheelchairAccess,
    bool? strollerAccess,
    bool? verifiedAccessibilityOnly,
    BudgetBand? budgetBand,
    int? maxWaitMinutes,
    DayRhythm? dayRhythm,
    bool? excludeClosingSoon,
    DocentDepth? docentDepth,
    bool? docentAutoplay,
    PlaceNameMode? placeNameMode,
    double? narrationSpeed,
    bool? continueNarration,
    bool? pronunciationHelp,
  }) {
    return TravelPreferences(
      pace: pace ?? this.pace,
      crowdTolerance: crowdTolerance ?? this.crowdTolerance,
      walkingBand: walkingBand ?? this.walkingBand,
      interests: Set<TravelInterest>.unmodifiable(interests ?? this.interests),
      travelStyles: Set<TravelStyle>.unmodifiable(
        travelStyles ?? this.travelStyles,
      ),
      indoorOutdoorPreference:
          indoorOutdoorPreference ?? this.indoorOutdoorPreference,
      weatherSensitivity: weatherSensitivity ?? this.weatherSensitivity,
      cuisines: Set<FoodCuisine>.unmodifiable(cuisines ?? this.cuisines),
      foodAdventure: foodAdventure ?? this.foodAdventure,
      dietaryModes: Set<DietaryMode>.unmodifiable(
        dietaryModes ?? this.dietaryModes,
      ),
      allergens: Set<Allergen>.unmodifiable(allergens ?? this.allergens),
      avoidIngredients: _boundedText(
        avoidIngredients ?? this.avoidIngredients,
        maxAvoidIngredientsLength,
      ),
      companions: Set<TravelCompanion>.unmodifiable(
        companions ?? this.companions,
      ),
      transportModes: Set<TransportMode>.unmodifiable(
        transportModes ?? this.transportModes,
      ),
      restFrequency: restFrequency ?? this.restFrequency,
      maxOneWayMinutes: _allowedOneWayMinutes.contains(maxOneWayMinutes)
          ? maxOneWayMinutes!
          : this.maxOneWayMinutes,
      maxTransfers: _allowedTransfers.contains(maxTransfers)
          ? maxTransfers!
          : this.maxTransfers,
      avoidStairs: avoidStairs ?? this.avoidStairs,
      wheelchairAccess: wheelchairAccess ?? this.wheelchairAccess,
      strollerAccess: strollerAccess ?? this.strollerAccess,
      verifiedAccessibilityOnly:
          verifiedAccessibilityOnly ?? this.verifiedAccessibilityOnly,
      budgetBand: budgetBand ?? this.budgetBand,
      maxWaitMinutes: _allowedWaitMinutes.contains(maxWaitMinutes)
          ? maxWaitMinutes!
          : this.maxWaitMinutes,
      dayRhythm: dayRhythm ?? this.dayRhythm,
      excludeClosingSoon: excludeClosingSoon ?? this.excludeClosingSoon,
      docentDepth: docentDepth ?? this.docentDepth,
      docentAutoplay: docentAutoplay ?? this.docentAutoplay,
      placeNameMode: placeNameMode ?? this.placeNameMode,
      narrationSpeed: _allowedNarrationSpeeds.contains(narrationSpeed)
          ? narrationSpeed!
          : this.narrationSpeed,
      continueNarration: continueNarration ?? this.continueNarration,
      pronunciationHelp: pronunciationHelp ?? this.pronunciationHelp,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'version': schemaVersion,
    'soft': <String, Object>{
      'pace': pace.name,
      'crowd_tolerance': crowdTolerance.name,
      'walking_band': walkingBand.name,
      'interests': interests.map((value) => value.name).toList()..sort(),
      'travel_styles': travelStyles.map((value) => value.name).toList()..sort(),
      'indoor_outdoor': indoorOutdoorPreference.name,
      'weather_sensitivity': weatherSensitivity.name,
      'food_cuisines': cuisines.map((value) => value.name).toList()..sort(),
      'food_adventure': foodAdventure.name,
      'companions': companions.map((value) => value.name).toList()..sort(),
      'transport_modes': transportModes.map((value) => value.name).toList()
        ..sort(),
      'rest_frequency': restFrequency.name,
      'max_one_way_minutes': maxOneWayMinutes,
      'max_transfers': maxTransfers,
      'budget_band': budgetBand.name,
      'day_rhythm': dayRhythm.name,
      'exclude_closing_soon': excludeClosingSoon,
      'docent_depth': docentDepth.name,
    },
    'hard': <String, Object>{
      'dietary_modes': dietaryModes.map((value) => value.name).toList()..sort(),
      'allergens': allergens.map((value) => value.name).toList()..sort(),
      'avoid_ingredients': avoidIngredients,
      'avoid_stairs': avoidStairs,
      'wheelchair_access': wheelchairAccess,
      'stroller_access': strollerAccess,
      'verified_accessibility_only': verifiedAccessibilityOnly,
      'max_wait_minutes': maxWaitMinutes,
    },
    'locale': <String, Object>{
      'docent_autoplay': docentAutoplay,
      'place_name_mode': placeNameMode.name,
      'narration_speed': narrationSpeed,
      'continue_narration': continueNarration,
      'pronunciation_help': pronunciationHelp,
    },
  };

  factory TravelPreferences.fromJson(Object? raw) {
    if (raw is! Map || raw['version'] != schemaVersion) {
      return const TravelPreferences();
    }
    final soft = raw['soft'] is Map
        ? raw['soft'] as Map
        : const <Object, Object>{};
    final hard = raw['hard'] is Map
        ? raw['hard'] as Map
        : const <Object, Object>{};
    final locale = raw['locale'] is Map
        ? raw['locale'] as Map
        : const <Object, Object>{};
    final wait = hard['max_wait_minutes'];
    final avoidIngredients = hard['avoid_ingredients'] is String
        ? (hard['avoid_ingredients'] as String).trim()
        : '';
    return TravelPreferences(
      pace: _enumValue(TravelPace.values, soft['pace'], TravelPace.balanced),
      crowdTolerance: _enumValue(
        CrowdTolerance.values,
        soft['crowd_tolerance'],
        CrowdTolerance.balanced,
      ),
      walkingBand: _enumValue(
        WalkingBand.values,
        soft['walking_band'],
        WalkingBand.medium,
      ),
      interests: _enumSet(
        TravelInterest.values,
        soft['interests'],
        maxInterests,
      ),
      travelStyles: _enumSet(
        TravelStyle.values,
        soft['travel_styles'],
        maxTravelStyles,
      ),
      indoorOutdoorPreference: _enumValue(
        IndoorOutdoorPreference.values,
        soft['indoor_outdoor'],
        IndoorOutdoorPreference.balanced,
      ),
      weatherSensitivity: _enumValue(
        WeatherSensitivity.values,
        soft['weather_sensitivity'],
        WeatherSensitivity.medium,
      ),
      cuisines: _enumSet(
        FoodCuisine.values,
        soft['food_cuisines'],
        maxCuisines,
      ),
      foodAdventure: _enumValue(
        FoodAdventure.values,
        soft['food_adventure'],
        FoodAdventure.balanced,
      ),
      dietaryModes: _enumSet(
        DietaryMode.values,
        hard['dietary_modes'],
        DietaryMode.values.length,
      ),
      allergens: _enumSet(
        Allergen.values,
        hard['allergens'],
        Allergen.values.length,
      ),
      avoidIngredients: _boundedText(
        avoidIngredients,
        maxAvoidIngredientsLength,
      ),
      companions: _enumSet(
        TravelCompanion.values,
        soft['companions'],
        TravelCompanion.values.length,
        fallback: const <TravelCompanion>{TravelCompanion.solo},
      ),
      transportModes: _enumSet(
        TransportMode.values,
        soft['transport_modes'],
        TransportMode.values.length,
        fallback: const <TransportMode>{
          TransportMode.walk,
          TransportMode.transit,
        },
      ),
      restFrequency: _enumValue(
        RestFrequency.values,
        soft['rest_frequency'],
        RestFrequency.balanced,
      ),
      maxOneWayMinutes:
          soft['max_one_way_minutes'] is int &&
              _allowedOneWayMinutes.contains(soft['max_one_way_minutes'])
          ? soft['max_one_way_minutes'] as int
          : 30,
      maxTransfers:
          soft['max_transfers'] is int &&
              _allowedTransfers.contains(soft['max_transfers'])
          ? soft['max_transfers'] as int
          : 2,
      avoidStairs: hard['avoid_stairs'] == true,
      wheelchairAccess: hard['wheelchair_access'] == true,
      strollerAccess: hard['stroller_access'] == true,
      verifiedAccessibilityOnly: hard['verified_accessibility_only'] == true,
      budgetBand: _enumValue(
        BudgetBand.values,
        soft['budget_band'],
        BudgetBand.balanced,
      ),
      maxWaitMinutes: wait is int && _allowedWaitMinutes.contains(wait)
          ? wait
          : 20,
      dayRhythm: _enumValue(
        DayRhythm.values,
        soft['day_rhythm'],
        DayRhythm.daytime,
      ),
      excludeClosingSoon: soft['exclude_closing_soon'] != false,
      docentDepth: _enumValue(
        DocentDepth.values,
        soft['docent_depth'],
        DocentDepth.standard,
      ),
      docentAutoplay: locale['docent_autoplay'] == true,
      placeNameMode: _enumValue(
        PlaceNameMode.values,
        locale['place_name_mode'],
        PlaceNameMode.localizedWithKorean,
      ),
      narrationSpeed:
          locale['narration_speed'] is num &&
              _allowedNarrationSpeeds.contains(
                (locale['narration_speed'] as num).toDouble(),
              )
          ? (locale['narration_speed'] as num).toDouble()
          : 1.0,
      continueNarration: locale['continue_narration'] != false,
      pronunciationHelp: locale['pronunciation_help'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TravelPreferences &&
      other.pace == pace &&
      other.crowdTolerance == crowdTolerance &&
      other.walkingBand == walkingBand &&
      setEquals(other.interests, interests) &&
      setEquals(other.travelStyles, travelStyles) &&
      other.indoorOutdoorPreference == indoorOutdoorPreference &&
      other.weatherSensitivity == weatherSensitivity &&
      setEquals(other.cuisines, cuisines) &&
      other.foodAdventure == foodAdventure &&
      setEquals(other.dietaryModes, dietaryModes) &&
      setEquals(other.allergens, allergens) &&
      other.avoidIngredients == avoidIngredients &&
      setEquals(other.companions, companions) &&
      setEquals(other.transportModes, transportModes) &&
      other.restFrequency == restFrequency &&
      other.maxOneWayMinutes == maxOneWayMinutes &&
      other.maxTransfers == maxTransfers &&
      other.avoidStairs == avoidStairs &&
      other.wheelchairAccess == wheelchairAccess &&
      other.strollerAccess == strollerAccess &&
      other.verifiedAccessibilityOnly == verifiedAccessibilityOnly &&
      other.budgetBand == budgetBand &&
      other.maxWaitMinutes == maxWaitMinutes &&
      other.dayRhythm == dayRhythm &&
      other.excludeClosingSoon == excludeClosingSoon &&
      other.docentDepth == docentDepth &&
      other.docentAutoplay == docentAutoplay &&
      other.placeNameMode == placeNameMode &&
      other.narrationSpeed == narrationSpeed &&
      other.continueNarration == continueNarration &&
      other.pronunciationHelp == pronunciationHelp;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    pace,
    crowdTolerance,
    walkingBand,
    _stableEnumSetHash(interests),
    _stableEnumSetHash(travelStyles),
    indoorOutdoorPreference,
    weatherSensitivity,
    _stableEnumSetHash(cuisines),
    foodAdventure,
    _stableEnumSetHash(dietaryModes),
    _stableEnumSetHash(allergens),
    avoidIngredients,
    _stableEnumSetHash(companions),
    _stableEnumSetHash(transportModes),
    restFrequency,
    maxOneWayMinutes,
    maxTransfers,
    avoidStairs,
    wheelchairAccess,
    strollerAccess,
    verifiedAccessibilityOnly,
    budgetBand,
    maxWaitMinutes,
    dayRhythm,
    excludeClosingSoon,
    docentDepth,
    docentAutoplay,
    placeNameMode,
    narrationSpeed,
    continueNarration,
    pronunciationHelp,
  ]);
}

const Set<int> _allowedWaitMinutes = <int>{10, 20, 40, 60};
const Set<int> _allowedOneWayMinutes = <int>{15, 30, 60, 90};
const Set<int> _allowedTransfers = <int>{0, 1, 2, 3};
final Set<double> _allowedNarrationSpeeds = <double>{0.8, 1.0, 1.2};

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final value in values) {
    if (value.name == raw) {
      return value;
    }
  }
  return fallback;
}

Set<T> _enumSet<T extends Enum>(
  List<T> values,
  Object? raw,
  int limit, {
  Set<T>? fallback,
}) {
  if (raw is! List) {
    return Set<T>.unmodifiable(fallback ?? <T>{});
  }
  final allowed = <String, T>{for (final value in values) value.name: value};
  final decoded = <T>{};
  for (final item in raw) {
    final value = allowed[item];
    if (value != null) {
      decoded.add(value);
    }
    if (decoded.length == limit) {
      break;
    }
  }
  return Set<T>.unmodifiable(decoded);
}

String _boundedText(String value, int limit) {
  final trimmed = value.trim();
  return trimmed.length <= limit ? trimmed : trimmed.substring(0, limit);
}

int _stableEnumSetHash<T extends Enum>(Set<T> values) {
  final names = values.map((value) => value.name).toList()..sort();
  return Object.hashAll(names);
}
