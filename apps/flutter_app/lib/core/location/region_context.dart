// Wave-1 location/weather: deterministic region context.
//
// The app shell previously had no shared location/region state: each tab
// (home/search/plan) built its own backend from LalaAppConfig defaults and
// silently fell back to the Suwon coordinates whenever geolocation did not
// resolve. Onboarding even discarded the user's manual/current choice. This
// module is the single in-memory holder so a choice made in onboarding (or on
// one tab) drives place + weather calls on every tab, and so an *intentional*
// default region can be disclosed honestly instead of presented as "nearby".
//
// Wave-1 cold-start: a *manual* selection is persisted by stable regionId so it
// survives a process restart and is restored before the search/plan/map tabs seed
// their first backend. RegionSource.current (precise device coordinates) is NEVER
// persisted — once current becomes the active context, the saved manual id is
// cleared so a cold start yields no real region (the provider may re-request).
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/manual_location_options.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

/// How the active region context was established.
enum RegionSource {
  /// Live geolocation resolved to real device coordinates.
  current,

  /// User picked a province/district from the manual list.
  manual,

  /// No current/manual context yet. The app falls back to a disclosed default
  /// region — it must be labeled as a default, never as the user's location.
  defaultRegion,
}

/// Immutable region context that drives place + weather calls.
///
/// Carries coordinates, a stable region id, localized labels, and a [source]
/// so the UI can disclose a default region honestly (see [isDefault]) instead
/// of silently presenting it as the user's "nearby" location.
@immutable
class RegionContext {
  const RegionContext({
    required this.lat,
    required this.lng,
    required this.regionId,
    required this.labelKo,
    required this.labelEn,
    required this.source,
  });

  /// Context from live geolocation. Coordinates only; no stable region id.
  factory RegionContext.current({required double lat, required double lng}) {
    return RegionContext(
      lat: lat,
      lng: lng,
      regionId: 'current',
      labelKo: '현재 위치',
      labelEn: 'Current location',
      source: RegionSource.current,
    );
  }

  /// Context from a manual province/district selection.
  factory RegionContext.manual(ManualLocationOption option) {
    return RegionContext(
      lat: option.lat,
      lng: option.lng,
      regionId: option.id,
      labelKo: option.labelKo,
      labelEn: option.labelEn,
      source: RegionSource.manual,
    );
  }

  final double lat;
  final double lng;
  final String regionId;
  final String labelKo;
  final String labelEn;
  final RegionSource source;

  /// True when this is the disclosed default (no real user context).
  bool get isDefault => source == RegionSource.defaultRegion;

  /// Label for the active language. ko/en are kept exclusive.
  /// V6: ja/zh-Hans/zh-Hant 은 EN 라벨로 정직 폴백한다(계약 §6 — 지역명은
  /// KO/EN 정적 데이터만 있으므로, 확장 로케일 화면에 한국어가 섞이는 것을
  /// 금지하고 영문명을 보여준다).
  String label(String language) {
    final normalized = normalizeLalaLanguage(language);
    return normalized == 'ko' ? labelKo : labelEn;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegionContext &&
          runtimeType == other.runtimeType &&
          lat == other.lat &&
          lng == other.lng &&
          regionId == other.regionId &&
          source == other.source;

  @override
  int get hashCode => Object.hash(lat, lng, regionId, source);

  @override
  String toString() => 'RegionContext($regionId, ${source.name}, $lat, $lng)';
}

/// In-memory singleton region holder, analogous to [OnboardingState].
///
/// Holds the user's resolved current/manual context across onboarding and the
/// app shell. `null` means "no real context yet" — callers then use the app's
/// documented default coordinates and must show an honest default indicator.
/// A *manual* selection is optionally persisted (see [attachPersistence]) so the
/// choice survives a process restart; precise current coordinates are not.
class RegionContextStore {
  RegionContextStore._();

  static final ValueNotifier<RegionContext?> _notifier =
      ValueNotifier<RegionContext?>(null);

  // Optional cold-start persistence for the manual region id. null in tests that
  // don't exercise persistence.
  static OnboardingPreferences? _prefs;

  /// Listen for cross-tab context changes.
  static ValueListenable<RegionContext?> get listenable => _notifier;

  /// The active context, or `null` when only the disclosed default applies.
  static RegionContext? get current => _notifier.value;

  /// Attaches cold-start persistence for this process (see bootstrapAppState).
  static void attachPersistence(OnboardingPreferences prefs) => _prefs = prefs;

  /// Detaches persistence (test isolation).
  static void detachPersistence() => _prefs = null;

  /// Publish a resolved current/manual context (or `null` to revert to default).
  ///
  /// Best-effort: the manual-id write is fire-and-forget. Use [setAndFlush] at
  /// completion points (onboarding finish, manual re-pick) where the choice must
  /// be durable before the UI proceeds.
  ///
  /// Privacy: only an explicit manual selection is persisted. RegionSource.current
  /// is never stored; when current becomes active the saved manual id is cleared so
  /// a cold start yields no real region (provider may re-request). Reverting to
  /// null/clear also clears the saved manual id.
  static void set(RegionContext? context) {
    _notifier.value = context;
    final prefs = _prefs;
    if (prefs == null) {
      return;
    }
    unawaited(_safeWriteRegionId(prefs, _persistedIdFor(context)));
  }

  /// Awaited variant of [set] for completion-time writes. Updates memory
  /// immediately, then durably writes (or clears) the manual id before returning,
  /// so a process kill right after the tap cannot lose the restart state. Never
  /// throws — a write failure leaves the in-memory context authoritative for the
  /// session; the choice simply won't survive a cold restart (non-durable).
  ///
  /// Privacy is identical to [set]: current/null/clear writes null (clears any
  /// prior manual id); only a manual selection writes its region id.
  static Future<void> setAndFlush(RegionContext? context) async {
    _notifier.value = context;
    final prefs = _prefs;
    if (prefs == null) {
      return;
    }
    await _safeWriteRegionId(prefs, _persistedIdFor(context));
  }

  /// Cold start: restore the manual region from a persisted id. Resolves the id
  /// to a [ManualLocationOption]; null/unknown id -> no real context (disclosed
  /// default). Does not write back — the id is already the durable truth.
  static void applyManualRegionId(String? id) {
    final option = manualOptionForId(id);
    _notifier.value = option == null ? null : RegionContext.manual(option);
  }

  /// Reset to "no real context" (disclosed default). Used by tests/re-onboarding.
  /// Also forgets the persisted manual id so a restart cannot resurrect it.
  static void clear() {
    _notifier.value = null;
    final prefs = _prefs;
    if (prefs == null) {
      return;
    }
    unawaited(_safeWriteRegionId(prefs, null));
  }

  static Future<void> _safeWriteRegionId(
    OnboardingPreferences prefs,
    String? id,
  ) async {
    try {
      await prefs.writeManualRegionId(id);
    } on Object {
      // best-effort persistence; the in-memory context stays authoritative.
    }
  }

  // Only a manual selection has a durable id. current/default/null all map to
  // null so the saved manual id is cleared (precise coordinates are never stored).
  static String? _persistedIdFor(RegionContext? context) {
    return (context != null && context.source == RegionSource.manual)
        ? context.regionId
        : null;
  }
}
