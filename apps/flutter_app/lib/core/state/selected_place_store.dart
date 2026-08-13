// Cross-tab shared state (§13.4 / Lane 1, contract D1): the active selected-place
// id, held in a process-local singleton so a selection made on one tab drives
// every other tab's resolution. This is a structural mirror of RegionContextStore's
// *reactive surface* — one static ValueNotifier, a listenable, a value getter, a
// setter, and a clear.
//
// In-memory only: this lane wires sharing, not durability. Lane 2 adds persistence
// (SharedPreferences + bootstrap cold-start hydration) WITHOUT editing this holder,
// by attaching an external listener to [listenable] and restoring via [set] on cold
// start — the same way bootstrapAppState hydrates RegionContextStore. That is why
// this file deliberately owns no prefs/keys/attachPersistence.
//
// The id is opaque (a server place id, e.g. 'seed-test-cafe') and carries no
// location/PII; the resolved LalaPlace is NOT centralized — each tab resolves
// `placeById(itsItems, SelectedPlaceStore.current) ?? featuredPlace(itsItems)`,
// exactly as the map tab always has. This mirrors region: regionId is the durable
// truth; coordinates are resolved from the option list.
import 'package:flutter/foundation.dart';

/// Process-local singleton holding the active selected-place id (or null = honest
/// empty). The reactive SSOT for cross-tab selection (§13.4 "선택 장소 … 반응형으로
/// 공유").
class SelectedPlaceStore {
  SelectedPlaceStore._();

  static final ValueNotifier<String?> _notifier = ValueNotifier<String?>(null);

  /// Cross-tab listenable for the active selected-place id. Listeners no-op-skip
  /// unchanged values because ValueNotifier suppresses redundant notifications
  /// (String? equality — contract D4).
  static ValueListenable<String?> get listenable => _notifier;

  /// The active selected-place id, or null when nothing is selected.
  static String? get current => _notifier.value;

  /// Publish a selection (or null to clear). One notification per distinct value.
  // Why: the sole write seam so Lane 2 can persist changes by listening here and
  // restore on cold start by calling [set] — never by editing this holder.
  static void set(String? id) => _notifier.value = id;

  /// Reset to no selection (tests / re-onboarding).
  static void clear() => _notifier.value = null;
}
