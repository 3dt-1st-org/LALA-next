import 'package:flutter/foundation.dart';

import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';

enum TripVisitStatus { planned, visited, notVisited }

enum TripVisitReason {
  closed,
  weather,
  crowded,
  time,
  transport,
  changedMind,
  other,
}

@immutable
class TripPreferenceOverride {
  const TripPreferenceOverride({
    this.companions,
    this.pace,
    this.crowdTolerance,
    this.walkingBand,
    this.indoorOutdoorPreference,
    this.weatherSensitivity,
    this.transportModes,
    this.maxWaitMinutes,
    this.budgetBand,
    this.dayRhythm,
    this.excludeClosingSoon,
  });

  final Set<TravelCompanion>? companions;
  final TravelPace? pace;
  final CrowdTolerance? crowdTolerance;
  final WalkingBand? walkingBand;
  final IndoorOutdoorPreference? indoorOutdoorPreference;
  final WeatherSensitivity? weatherSensitivity;
  final Set<TransportMode>? transportModes;
  final int? maxWaitMinutes;
  final BudgetBand? budgetBand;
  final DayRhythm? dayRhythm;
  final bool? excludeClosingSoon;

  TripPreferenceOverride copyWith({
    Set<TravelCompanion>? companions,
    TravelPace? pace,
    CrowdTolerance? crowdTolerance,
    WalkingBand? walkingBand,
    IndoorOutdoorPreference? indoorOutdoorPreference,
    WeatherSensitivity? weatherSensitivity,
    Set<TransportMode>? transportModes,
    int? maxWaitMinutes,
    BudgetBand? budgetBand,
    DayRhythm? dayRhythm,
    bool? excludeClosingSoon,
  }) {
    return TripPreferenceOverride(
      companions: companions ?? this.companions,
      pace: pace ?? this.pace,
      crowdTolerance: crowdTolerance ?? this.crowdTolerance,
      walkingBand: walkingBand ?? this.walkingBand,
      indoorOutdoorPreference:
          indoorOutdoorPreference ?? this.indoorOutdoorPreference,
      weatherSensitivity: weatherSensitivity ?? this.weatherSensitivity,
      transportModes: transportModes ?? this.transportModes,
      maxWaitMinutes: maxWaitMinutes ?? this.maxWaitMinutes,
      budgetBand: budgetBand ?? this.budgetBand,
      dayRhythm: dayRhythm ?? this.dayRhythm,
      excludeClosingSoon: excludeClosingSoon ?? this.excludeClosingSoon,
    );
  }

  bool get isEmpty => differenceCount == 0;

  int get differenceCount => <Object?>[
    companions,
    pace,
    crowdTolerance,
    walkingBand,
    indoorOutdoorPreference,
    weatherSensitivity,
    transportModes,
    maxWaitMinutes,
    budgetBand,
    dayRhythm,
    excludeClosingSoon,
  ].where((value) => value != null).length;

  TravelPreferences applyTo(TravelPreferences defaults) {
    return defaults.copyWith(
      companions: companions,
      pace: pace,
      crowdTolerance: crowdTolerance,
      walkingBand: walkingBand,
      indoorOutdoorPreference: indoorOutdoorPreference,
      weatherSensitivity: weatherSensitivity,
      transportModes: transportModes,
      maxWaitMinutes: maxWaitMinutes,
      budgetBand: budgetBand,
      dayRhythm: dayRhythm,
      excludeClosingSoon: excludeClosingSoon,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 1,
    if (companions != null)
      'companions': companions!.map((value) => value.name).toList()..sort(),
    if (pace != null) 'pace': pace!.name,
    if (crowdTolerance != null) 'crowd_tolerance': crowdTolerance!.name,
    if (walkingBand != null) 'walking_band': walkingBand!.name,
    if (indoorOutdoorPreference != null)
      'indoor_outdoor': indoorOutdoorPreference!.name,
    if (weatherSensitivity != null)
      'weather_sensitivity': weatherSensitivity!.name,
    if (transportModes != null)
      'transport_modes': transportModes!.map((value) => value.name).toList()
        ..sort(),
    if (maxWaitMinutes != null) 'max_wait_minutes': maxWaitMinutes,
    if (budgetBand != null) 'budget_band': budgetBand!.name,
    if (dayRhythm != null) 'day_rhythm': dayRhythm!.name,
    if (excludeClosingSoon != null) 'exclude_closing_soon': excludeClosingSoon,
  };

  factory TripPreferenceOverride.fromJson(Object? raw) {
    if (raw is! Map || raw['version'] != 1) {
      return const TripPreferenceOverride();
    }
    return TripPreferenceOverride(
      companions: _enumSet(TravelCompanion.values, raw['companions']),
      pace: _enumValue(TravelPace.values, raw['pace']),
      crowdTolerance: _enumValue(CrowdTolerance.values, raw['crowd_tolerance']),
      walkingBand: _enumValue(WalkingBand.values, raw['walking_band']),
      indoorOutdoorPreference: _enumValue(
        IndoorOutdoorPreference.values,
        raw['indoor_outdoor'],
      ),
      weatherSensitivity: _enumValue(
        WeatherSensitivity.values,
        raw['weather_sensitivity'],
      ),
      transportModes: _enumSet(TransportMode.values, raw['transport_modes']),
      maxWaitMinutes: _allowedWaitMinutes.contains(raw['max_wait_minutes'])
          ? raw['max_wait_minutes'] as int
          : null,
      budgetBand: _enumValue(BudgetBand.values, raw['budget_band']),
      dayRhythm: _enumValue(DayRhythm.values, raw['day_rhythm']),
      excludeClosingSoon: raw['exclude_closing_soon'] is bool
          ? raw['exclude_closing_soon'] as bool
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TripPreferenceOverride &&
        setEquals(other.companions, companions) &&
        other.pace == pace &&
        other.crowdTolerance == crowdTolerance &&
        other.walkingBand == walkingBand &&
        other.indoorOutdoorPreference == indoorOutdoorPreference &&
        other.weatherSensitivity == weatherSensitivity &&
        setEquals(other.transportModes, transportModes) &&
        other.maxWaitMinutes == maxWaitMinutes &&
        other.budgetBand == budgetBand &&
        other.dayRhythm == dayRhythm &&
        other.excludeClosingSoon == excludeClosingSoon;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(companions ?? const <TravelCompanion>[]),
    pace,
    crowdTolerance,
    walkingBand,
    indoorOutdoorPreference,
    weatherSensitivity,
    Object.hashAllUnordered(transportModes ?? const <TransportMode>[]),
    maxWaitMinutes,
    budgetBand,
    dayRhythm,
    excludeClosingSoon,
  );
}

@immutable
class TripOverrideDocument {
  const TripOverrideDocument({
    required this.value,
    required this.revision,
    required this.updatedAt,
    this.dirty = false,
  });

  final TripPreferenceOverride value;
  final int revision;
  final String? updatedAt;
  final bool dirty;

  Map<String, dynamic> toLocalJson() => <String, dynamic>{
    'revision': revision,
    'updated_at': updatedAt,
    'dirty': dirty,
    'value': value.toJson(),
  };

  factory TripOverrideDocument.fromLocalJson(Object? raw) {
    if (raw is! Map) {
      return const TripOverrideDocument(
        value: TripPreferenceOverride(),
        revision: 0,
        updatedAt: null,
      );
    }
    return TripOverrideDocument(
      value: TripPreferenceOverride.fromJson(raw['value']),
      revision: raw['revision'] is int ? raw['revision'] as int : 0,
      updatedAt: raw['updated_at'] is String
          ? raw['updated_at'] as String
          : null,
      dirty: raw['dirty'] == true,
    );
  }
}

@immutable
class TripVisitFeedback {
  const TripVisitFeedback({
    this.status = TripVisitStatus.planned,
    this.reason,
    this.useForRecommendations = false,
    this.confirmedAt,
  });

  final TripVisitStatus status;
  final TripVisitReason? reason;
  final bool useForRecommendations;
  final String? confirmedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'status': _visitStatusWire(status),
    if (reason != null) 'reason_code': _visitReasonWire(reason!),
    'use_for_recommendations': useForRecommendations,
    if (confirmedAt != null) 'confirmed_at': confirmedAt,
  };

  factory TripVisitFeedback.fromJson(Object? raw) {
    if (raw is! Map) return const TripVisitFeedback();
    final status = switch (raw['status']) {
      'visited' => TripVisitStatus.visited,
      'not_visited' => TripVisitStatus.notVisited,
      _ => TripVisitStatus.planned,
    };
    final reason = _enumValue(
      TripVisitReason.values,
      _visitReasonName(raw['reason_code']),
    );
    return TripVisitFeedback(
      status: status,
      reason: status == TripVisitStatus.notVisited ? reason : null,
      useForRecommendations: status == TripVisitStatus.planned
          ? false
          : raw['use_for_recommendations'] == true,
      confirmedAt: raw['confirmed_at'] is String
          ? raw['confirmed_at'] as String
          : null,
    );
  }

  // Value equality so sync reconciliation can compare a device copy against a
  // decoded server copy (identity comparison would always differ and force a
  // re-push on every reconnect).
  @override
  bool operator ==(Object other) =>
      other is TripVisitFeedback &&
      other.status == status &&
      other.reason == reason &&
      other.useForRecommendations == useForRecommendations &&
      other.confirmedAt == confirmedAt;

  @override
  int get hashCode =>
      Object.hash(status, reason, useForRecommendations, confirmedAt);
}

@immutable
class PastTripSummary {
  const PastTripSummary({
    required this.planDate,
    required this.slotCount,
    required this.visitedCount,
    this.region,
    this.updatedAt,
  });

  final String planDate;
  final String? region;
  final int slotCount;
  final int visitedCount;
  final String? updatedAt;
}

String tripLibraryDateKey([DateTime? value]) {
  final calendarDate = value ?? DateTime.now();
  return '${calendarDate.year.toString().padLeft(4, '0')}-'
      '${calendarDate.month.toString().padLeft(2, '0')}-'
      '${calendarDate.day.toString().padLeft(2, '0')}';
}

String tripVisitKey(String planDate, String slotPeriod) =>
    '$planDate:$slotPeriod';

String tripVisitStatusWire(TripVisitStatus status) => _visitStatusWire(status);

String? tripVisitReasonWire(TripVisitReason? reason) =>
    reason == null ? null : _visitReasonWire(reason);

T? _enumValue<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String) return null;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return null;
}

Set<T>? _enumSet<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! List) return null;
  final result = raw
      .map((item) => _enumValue(values, item))
      .whereType<T>()
      .toSet();
  return result.isEmpty ? null : Set<T>.unmodifiable(result);
}

String _visitStatusWire(TripVisitStatus status) => switch (status) {
  TripVisitStatus.planned => 'planned',
  TripVisitStatus.visited => 'visited',
  TripVisitStatus.notVisited => 'not_visited',
};

String _visitReasonWire(TripVisitReason reason) => switch (reason) {
  TripVisitReason.changedMind => 'changed_mind',
  _ => reason.name,
};

String? _visitReasonName(Object? raw) => switch (raw) {
  'changed_mind' => 'changedMind',
  String value => value,
  _ => null,
};

const Set<int> _allowedWaitMinutes = <int>{10, 20, 40, 60};
