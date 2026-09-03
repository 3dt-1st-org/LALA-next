// Cross-tab cold-start persistence for the selected-place id + daily plan
// (§13.4 / Lane 2).
//
// Lane 1 wired process-local sharing via SelectedPlaceStore / PlanContextStore.
// Those holders deliberately own no prefs/keys: this module makes the active
// selection + plan survive a process restart by persisting them under disjoint
// versioned keys and hydrating them on cold start through the holders' PUBLIC
// set() API — without editing the holder files.
//
// Privacy contract: ONLY (a) the opaque selected-place id String and (b) the
// plan DTO are persisted, under lala.crosstab.v1.*. Precise current-device
// coordinates / region coordinates / PII are never stored here (the manual
// region id is owned by onboarding_preferences; the plan's center/weather are
// part of the sanctioned plan DTO, not a standalone coordinates key).
//
// Data integrity: every read is failure-safe. A store error, corrupt JSON, or a
// version mismatch degrades to a clean CrossTabSnapshot(null, null) so the app
// always starts.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:lala_next_app/core/state/plan_context_store.dart';
import 'package:lala_next_app/core/state/selected_place_store.dart';

/// Versioned key prefix so cross-tab keys never collide with onboarding's
/// `lala.onboarding.v1.*` or any future schema.
const String kCrossTabStoragePrefix = 'lala.crosstab.v1.';

const String _kSelectedPlaceId = '${kCrossTabStoragePrefix}selectedPlaceId';
const String _kPlan = '${kCrossTabStoragePrefix}plan';

/// Envelope version. Bumping this makes every older persisted plan read as
/// "version mismatch -> null", the sanctioned corrupt-degrade path.
const int kCrossTabEnvelopeVersion = 1;

/// Immutable snapshot of the persisted cross-tab state.
@immutable
class CrossTabSnapshot {
  const CrossTabSnapshot({this.selectedPlaceId, this.plan});

  /// The opaque server place id, or null when nothing is selected / the stored
  /// value was empty or not a String.
  final String? selectedPlaceId;

  /// The persisted daily plan, or null when none was stored / the stored JSON
  /// was corrupt or a version mismatch.
  final LalaDailyPlan? plan;
}

/// Storage seam so persistence is unit-testable without the SharedPreferences
/// plugin, mirroring [OnboardingPreferencesBackend]. The method set is the
/// subset cross-tab needs (read/write/remove String), so an in-memory fake that
/// already implements OnboardingPreferencesBackend satisfies this interface.
abstract interface class CrossTabPreferencesBackend {
  Future<String?> getString(String key);

  Future<void> setString(String key, String value);

  Future<void> remove(String key);
}

/// [CrossTabPreferencesBackend] backed by SharedPreferences (production).
class SharedPreferencesCrossTabBackend implements CrossTabPreferencesBackend {
  SharedPreferencesCrossTabBackend(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<String?> getString(String key) async => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

/// Reads + writes the cold-start cross-tab snapshot.
///
/// All reads are failure-safe: a store error, corrupt JSON, or a version
/// mismatch degrades to a clean [CrossTabSnapshot] (the app still starts).
/// Writes propagate errors to the caller so the in-memory layer stays the
/// authority regardless of durability.
class CrossTabPreferences {
  CrossTabPreferences(this._backend);

  final CrossTabPreferencesBackend _backend;

  /// Production instance backed by SharedPreferences. Shares the same
  /// SharedPreferences singleton as onboarding so both stores live in one
  /// process-local disk file.
  static Future<CrossTabPreferences> createDefault() async {
    final prefs = await SharedPreferences.getInstance();
    return CrossTabPreferences(SharedPreferencesCrossTabBackend(prefs));
  }

  /// Loads the persisted snapshot. Never throws — a store failure, corrupt
  /// JSON, or version mismatch degrades to a clean snapshot.
  Future<CrossTabSnapshot> load() async {
    String? idRaw;
    String? planRaw;
    try {
      idRaw = await _backend.getString(_kSelectedPlaceId);
      planRaw = await _backend.getString(_kPlan);
    } on Object {
      return const CrossTabSnapshot();
    }
    return CrossTabSnapshot(
      selectedPlaceId: _decodeSelectedPlaceId(idRaw),
      plan: _decodePlanJson(planRaw),
    );
  }

  /// Persists (or clears, when [id] is null / blank) the selected-place id.
  Future<void> writeSelectedPlaceId(String? id) async {
    if (id == null || id.trim().isEmpty) {
      await _backend.remove(_kSelectedPlaceId);
    } else {
      await _backend.setString(_kSelectedPlaceId, id);
    }
  }

  /// Persists (or clears, when [plan] is null) the daily plan as a versioned
  /// JSON envelope. Encoding is app-owned (the generated client has no toJson).
  Future<void> writePlan(LalaDailyPlan? plan) async {
    if (plan == null) {
      await _backend.remove(_kPlan);
    } else {
      await _backend.setString(_kPlan, _encodePlanEnvelope(plan));
    }
  }

  /// Clears every persisted cross-tab key (re-onboarding / reset).
  Future<void> clearAll() async {
    await _backend.remove(_kSelectedPlaceId);
    await _backend.remove(_kPlan);
  }

  static String? _decodeSelectedPlaceId(String? raw) {
    if (raw == null) {
      return null;
    }
    if (raw.trim().isEmpty) {
      return null;
    }
    return raw;
  }

  static LalaDailyPlan? _decodePlanJson(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      if (decoded['v'] != kCrossTabEnvelopeVersion) {
        return null;
      }
      final plan = decoded['plan'];
      if (plan is! Map) {
        return null;
      }
      // fromJsonObject never throws for a Map (all _as* helpers degrade), but
      // wrap defensively so a future client change can never crash cold start.
      return LalaDailyPlan.fromJsonObject(plan);
    } on Object {
      return null;
    }
  }

  static String _encodePlanEnvelope(LalaDailyPlan plan) {
    return jsonEncode(<String, dynamic>{
      'v': kCrossTabEnvelopeVersion,
      'plan': encodeLalaDailyPlan(plan),
    });
  }
}

// ---------------------------------------------------------------------------
// APP-OWNED plan encoder.
//
// The generated LalaDailyPlan has fromJsonObject but NO toJson (adding one is
// forbidden — codegen regen would clobber it). These functions hand-roll the
// inverse of fromJson, field by field, mirroring the exact snake_case shape so
// a round-trip writePlan -> load -> fromJsonObject is lossless.
// ---------------------------------------------------------------------------

/// Encodes a [LalaDailyPlan] into the JSON object shape [LalaDailyPlan.fromJson]
/// accepts. Public so tests can assert the encoded shape directly.
Map<String, dynamic> encodeLalaDailyPlan(LalaDailyPlan plan) {
  return <String, dynamic>{
    'language': plan.language,
    'center': _encodeCoordinate(plan.center),
    'radius_m': plan.radiusM,
    'weather': _encodeWeather(plan.weather),
    'slots': plan.slots.map(_encodePlanSlot).toList(),
    'source': plan.source,
    'request_hash': plan.requestHash,
    'cache_key': plan.cacheKey,
  };
}

Map<String, dynamic> _encodeCoordinate(LalaCoordinate c) {
  return <String, dynamic>{'lat': c.lat, 'lng': c.lng};
}

Map<String, dynamic> _encodeWeather(LalaWeather w) {
  return <String, dynamic>{
    'lat': w.lat,
    'lng': w.lng,
    'temp': w.temp,
    'icon': w.icon,
    'dust': _encodeDust(w.dust),
    'forecast': w.forecast.map(_encodeForecastItem).toList(),
    'outdoor_status': w.outdoorStatus,
    'force': w.force,
    'source': w.source,
    if (w.location != null) 'location': w.location,
    if (w.recordTime != null) 'record_time': w.recordTime,
    if (w.locationMatch != null) 'location_match': w.locationMatch,
  };
}

Map<String, dynamic> _encodeDust(LalaDust d) {
  return <String, dynamic>{
    'pm10': d.pm10,
    'pm25': d.pm25,
    'grade': d.grade,
    'grade_ko': d.gradeKo,
    'pm10_grade': d.pm10Grade,
    'pm10_grade_ko': d.pm10GradeKo,
    'pm25_grade': d.pm25Grade,
    'pm25_grade_ko': d.pm25GradeKo,
  };
}

Map<String, dynamic> _encodeForecastItem(LalaForecastItem f) {
  return <String, dynamic>{'time': f.time, 'temp': f.temp, 'icon': f.icon};
}

Map<String, dynamic> _encodePlanSlot(LalaPlanSlot s) {
  return <String, dynamic>{
    'period': s.period,
    'title': s.title,
    if (s.place != null) 'place': _encodePlace(s.place!),
    if (s.weatherHint != null) 'weather_hint': s.weatherHint,
    if (s.startTime != null) 'start_time': s.startTime,
    if (s.stayDurationMinutes != null)
      'stay_duration_minutes': s.stayDurationMinutes,
    if (s.travelTimeFromPreviousMinutes != null)
      'travel_time_from_previous_minutes': s.travelTimeFromPreviousMinutes,
    if (s.estimatedOpeningHours != null)
      'estimated_opening_hours': s.estimatedOpeningHours,
    if (s.openingHoursValid != null) 'opening_hours_valid': s.openingHoursValid,
    if (s.indoorOutdoor != null) 'indoor_outdoor': s.indoorOutdoor,
    if (s.recommendationReason != null)
      'recommendation_reason': s.recommendationReason,
    if (s.localFranchiseConfidence != null)
      'local_franchise_confidence': s.localFranchiseConfidence,
    'swappable_alternatives': s.swappableAlternatives
        .map(_encodePlace)
        .toList(),
    if (s.unavailableReason != null) 'unavailable_reason': s.unavailableReason,
  };
}

Map<String, dynamic> _encodePlace(LalaPlace p) {
  return <String, dynamic>{
    'place_id': p.placeId,
    'name': p.name,
    'category': p.category,
    'lat': p.lat,
    'lng': p.lng,
    'address': p.address,
    'distance_m': p.distanceM,
    'source': p.source,
    if (p.nameKo != null) 'name_ko': p.nameKo,
    if (p.nameEn != null) 'name_en': p.nameEn,
    if (p.imageUrl != null) 'image_url': p.imageUrl,
    if (p.upstreamSource != null) 'upstream_source': p.upstreamSource,
    if (p.regionKo != null) 'region_ko': p.regionKo,
    if (p.regionEn != null) 'region_en': p.regionEn,
    if (p.eventStartDate != null) 'event_start_date': p.eventStartDate,
    if (p.eventEndDate != null) 'event_end_date': p.eventEndDate,
    if (p.eventUrl != null) 'event_url': p.eventUrl,
    if (p.isOngoing != null) 'is_ongoing': p.isOngoing,
    if (p.isApproximateLocation != null)
      'is_approximate_location': p.isApproximateLocation,
    if (p.isIndoor != null) 'is_indoor': p.isIndoor,
    if (p.score != null) 'score': _encodeScore(p.score!),
    if (p.reason != null) 'reason': p.reason,
    if (p.freshness != null) 'freshness': p.freshness,
  };
}

Map<String, dynamic> _encodeScore(LalaPlaceScore s) {
  return <String, dynamic>{
    'final_score': s.finalScore,
    'formula_version': s.formulaVersion,
    'components': _encodeScoreComponents(s.components),
    'data_basis': s.dataBasis,
    'features': s.features,
  };
}

Map<String, dynamic> _encodeScoreComponents(LalaPlaceScoreComponents c) {
  return <String, dynamic>{
    if (c.localSpendingScore != null)
      'local_spending_score': c.localSpendingScore,
    if (c.smallMerchantFitScore != null)
      'small_merchant_fit_score': c.smallMerchantFitScore,
    if (c.demandDispersionScore != null)
      'demand_dispersion_score': c.demandDispersionScore,
    if (c.weatherFitScore != null) 'weather_fit_score': c.weatherFitScore,
    if (c.reviewQualityScore != null)
      'review_quality_score': c.reviewQualityScore,
    if (c.cultureRelevanceScore != null)
      'culture_relevance_score': c.cultureRelevanceScore,
    if (c.accessibilityFitScore != null)
      'accessibility_fit_score': c.accessibilityFitScore,
  };
}

// ---------------------------------------------------------------------------
// Cold-start hydration gateway: write-through listeners + epoch guard.
//
// The holders own no persistence, so this module attaches its OWN listeners to
// the holders' listentables and restores via set() on cold start. An epoch
// guard suppresses stale hydration: if a fresh set() lands during the load
// window, the persisted value must NOT clobber it.
// ---------------------------------------------------------------------------

/// Attaches cross-tab write-through persistence and performs cold-start
/// hydration. Owns its own listeners (the holders expose no attach/detach).
class CrossTabPersistence {
  CrossTabPersistence._();

  /// Monotonic counter incremented on every holder change. Captured at
  /// load-start; if it advanced by the time load resolves, a fresh value
  /// appeared and the stale persisted value is suppressed.
  static int _epoch = 0;

  static VoidCallback? _selectedPlaceDisposer;
  static VoidCallback? _planDisposer;
  static bool _attached = false;
  static CrossTabPreferences? _preferences;

  /// Attaches write-through listeners and hydrates the holders from [prefs].
  ///
  /// The epoch guard ensures a [SelectedPlaceStore.set] / [PlanContextStore.set]
  /// that fires during the load window is NOT clobbered by the stale persisted
  /// value when load resolves.
  static Future<void> attachAndHydrate(CrossTabPreferences prefs) async {
    detach();
    _attached = true;
    _preferences = prefs;
    final epochAtLoadStart = _epoch;

    _selectedPlaceDisposer = _listen(
      SelectedPlaceStore.listenable,
      () => unawaited(
        _safeWrite(prefs.writeSelectedPlaceId(SelectedPlaceStore.current)),
      ),
    );
    _planDisposer = _listen(
      PlanContextStore.listenable,
      () => unawaited(_safeWrite(prefs.writePlan(PlanContextStore.current))),
    );

    final snapshot = await prefs.load();

    // Detached during the load window — nothing to apply.
    if (!_attached) {
      return;
    }
    // A fresh value appeared during the load window — do not clobber it.
    if (_epoch != epochAtLoadStart) {
      return;
    }
    if (snapshot.selectedPlaceId != null) {
      SelectedPlaceStore.set(snapshot.selectedPlaceId);
    }
    if (snapshot.plan != null) {
      PlanContextStore.set(snapshot.plan);
    }
  }

  /// Detaches the write-through listeners (test isolation / failure path).
  static void detach() {
    _selectedPlaceDisposer?.call();
    _planDisposer?.call();
    _selectedPlaceDisposer = null;
    _planDisposer = null;
    _attached = false;
    _preferences = null;
  }

  /// Clears the persisted and process-local guest selection and plan.
  static Future<void> clearAndFlush() async {
    SelectedPlaceStore.clear();
    PlanContextStore.clear();
    await _preferences?.clearAll();
  }

  static VoidCallback _listen(
    ValueListenable<dynamic> listenable,
    void Function() body,
  ) {
    void listener() {
      _epoch++;
      body();
    }

    listenable.addListener(listener);
    return () => listenable.removeListener(listener);
  }

  static Future<void> _safeWrite(Future<void> future) async {
    try {
      await future;
    } on Object {
      // Best-effort persistence; the in-memory holder stays authoritative.
    }
  }
}
