// Wave-1 location/weather: deterministic region context.
//
// The app shell previously had no shared location/region state: each tab
// (home/search/plan) built its own backend from LalaAppConfig defaults and
// silently fell back to the Suwon coordinates whenever geolocation did not
// resolve. Onboarding even discarded the user's manual/current choice. This
// module is the single in-memory holder so a choice made in onboarding (or on
// one tab) drives place + weather calls on every tab, and so an *intentional*
// default region can be disclosed honestly instead of presented as "nearby".
import 'package:flutter/foundation.dart';

import 'package:lala_next_app/manual_location_options.dart';

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
  String label(String language) => language == 'en' ? labelEn : labelKo;

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
/// Persistence (SharedPreferences) is intentionally out of scope here; the
/// holder is process-local, matching the existing onboarding state pattern.
class RegionContextStore {
  RegionContextStore._();

  static final ValueNotifier<RegionContext?> _notifier =
      ValueNotifier<RegionContext?>(null);

  /// Listen for cross-tab context changes.
  static ValueListenable<RegionContext?> get listenable => _notifier;

  /// The active context, or `null` when only the disclosed default applies.
  static RegionContext? get current => _notifier.value;

  /// Publish a resolved current/manual context (or `null` to revert to default).
  static void set(RegionContext? context) {
    _notifier.value = context;
  }

  /// Reset to "no real context" (disclosed default). Used by tests/re-onboarding.
  static void clear() {
    _notifier.value = null;
  }
}
