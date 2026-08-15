// Cold-start persistence for the onboarding outcome + chosen manual region.
//
// Privacy contract: only intentional user choices survive a process restart —
// onboarding completion, chosen UI language, tourist type, and a manually
// selected region id. Precise current-device coordinates and RegionSource.current
// are NEVER stored here; a retained current context becomes null on cold start so
// the location provider may re-request it (see region_context.dart).
//
// The storage seam ([OnboardingPreferencesBackend]) keeps this unit-testable
// without the SharedPreferences plugin, and lets a failing store degrade to a
// clean first-run instead of crashing the app. This module deliberately has no
// dependency on OnboardingState: the tourist type is persisted as a code string
// and the enum<->code mapping lives with OnboardingState, so there is no import
// cycle between the two.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/manual_location_options.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

/// Versioned key prefix so schema changes never collide with older installs.
const String kOnboardingStoragePrefix = 'lala.onboarding.v1.';

const String _kCompleted = '${kOnboardingStoragePrefix}completed';
const String _kLanguage = '${kOnboardingStoragePrefix}language';
const String _kTouristType = '${kOnboardingStoragePrefix}touristType';
const String _kManualRegionId = '${kOnboardingStoragePrefix}manualRegionId';

/// Persisted tourist-type codes. Kept here (next to storage) so the on-disk
/// format is defined once; [OnboardingState] maps the enum to/from these.
const String kTouristTypeCodeForeign = 'foreignTourist';
const String kTouristTypeCodeLocal = 'localTourist';

/// Immutable snapshot of the persisted onboarding + region choices.
@immutable
class OnboardingSnapshot {
  const OnboardingSnapshot({
    this.completed = false,
    this.language = 'ko',
    this.touristTypeCode = kTouristTypeCodeLocal,
    this.manualRegionId,
  });

  /// Whether onboarding has been completed. False on a clean first run.
  final bool completed;

  /// Chosen UI language code ('ko' / 'en' / 'ja' / 'zh-Hans' / 'zh-Hant').
  /// Unknown values fall back to 'ko' (V6 visitor locales included).
  final String language;

  /// Persisted tourist-type code (see [kTouristTypeCode*]). Unknown -> local.
  final String touristTypeCode;

  /// Stable id of the last manually selected region (manual_location_options),
  /// or null when none was selected / the persisted id is no longer valid.
  final String? manualRegionId;
}

/// Storage seam so persistence can be unit-tested with an in-memory fake and a
/// failing store, independent of the SharedPreferences plugin.
abstract interface class OnboardingPreferencesBackend {
  Future<bool?> getBool(String key);

  Future<String?> getString(String key);

  Future<void> setBool(String key, bool value);

  Future<void> setString(String key, String value);

  Future<void> remove(String key);
}

/// [OnboardingPreferencesBackend] backed by SharedPreferences (production).
class SharedPreferencesOnboardingBackend
    implements OnboardingPreferencesBackend {
  SharedPreferencesOnboardingBackend(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<bool?> getBool(String key) async => _prefs.getBool(key);

  @override
  Future<String?> getString(String key) async => _prefs.getString(key);

  @override
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

/// Reads + writes the cold-start onboarding/region snapshot.
///
/// All reads are failure-safe: a store error, or an invalid persisted manual
/// region id, degrades to a clean first-run [OnboardingSnapshot] (the app still
/// starts). Writes propagate errors to the caller so the in-memory layer can keep
/// its UI consistent regardless of durability.
class OnboardingPreferences {
  OnboardingPreferences(this._backend);

  final OnboardingPreferencesBackend _backend;

  /// Production instance backed by SharedPreferences.
  static Future<OnboardingPreferences> createDefault() async {
    final prefs = await SharedPreferences.getInstance();
    return OnboardingPreferences(SharedPreferencesOnboardingBackend(prefs));
  }

  /// Loads the persisted snapshot. Never throws — a store failure or an invalid
  /// manual region id degrades to a clean first-run snapshot.
  Future<OnboardingSnapshot> load() async {
    bool completed;
    String language;
    String touristTypeCode;
    String? manualRegionId;
    try {
      completed = (await _backend.getBool(_kCompleted)) ?? false;
      language = _decodeLanguage(await _backend.getString(_kLanguage));
      touristTypeCode = _decodeTouristTypeCode(
        await _backend.getString(_kTouristType),
      );
      manualRegionId = await _backend.getString(_kManualRegionId);
    } on Object {
      return const OnboardingSnapshot();
    }
    // Validate the persisted manual id against the current option list: a stale
    // or removed id must not crash and must not pretend to be a real region.
    final validatedId = _validateManualRegionId(manualRegionId);
    if (manualRegionId != null && validatedId == null) {
      // Drop the bad value so future loads are clean.
      try {
        await _backend.remove(_kManualRegionId);
      } on Object {
        // best-effort cleanup; ignore.
      }
    }
    return OnboardingSnapshot(
      completed: completed,
      language: language,
      touristTypeCode: touristTypeCode,
      manualRegionId: validatedId,
    );
  }

  /// Durably persists the onboarding completion flag + chosen language/type code.
  Future<void> writeOnboarding({
    required bool completed,
    required String language,
    required String touristTypeCode,
  }) async {
    await _backend.setBool(_kCompleted, completed);
    await _backend.setString(_kLanguage, language);
    await _backend.setString(_kTouristType, touristTypeCode);
  }

  /// Persists (or clears, when [id] is null) the active manual region selection.
  Future<void> writeManualRegionId(String? id) async {
    if (id == null) {
      await _backend.remove(_kManualRegionId);
    } else {
      await _backend.setString(_kManualRegionId, id);
    }
  }

  /// Clears every persisted onboarding/region key (re-onboarding / reset).
  Future<void> clearAll() async {
    await _backend.remove(_kCompleted);
    await _backend.remove(_kLanguage);
    await _backend.remove(_kTouristType);
    await _backend.remove(_kManualRegionId);
  }

  // V6: 디스크 포맷은 키/네임스페이스 그대로 두고, 디코드만 확장 로케일을 허용한다.
  String _decodeLanguage(String? raw) => normalizeLalaLanguage(raw);

  String _decodeTouristTypeCode(String? raw) {
    return raw == kTouristTypeCodeForeign
        ? kTouristTypeCodeForeign
        : kTouristTypeCodeLocal;
  }
}

/// Resolves a persisted manual region id to a [ManualLocationOption], or null if
/// the id is unknown/removed. Shared by load-time validation and store hydration.
ManualLocationOption? manualOptionForId(String? id) {
  if (id == null) {
    return null;
  }
  for (final option in manualLocationOptions) {
    if (option.id == id) {
      return option;
    }
  }
  return null;
}

String? _validateManualRegionId(String? id) =>
    manualOptionForId(id) == null ? null : id;
