// V5-B SAVE holder (§V5-B D1): the saved-place id SET, held in a process-local
// singleton so a save made anywhere drives every surface, and survives a cold
// start once action_preferences attaches. Structural mirror of
// SelectedPlaceStore's reactive surface — one static ValueNotifier, a listenable,
// a value getter, a toggle/add/remove, and a clear.
//
// In-memory only: this holder owns no prefs/keys. action_preferences.dart hydrates
// it on cold start (bootstrap) and persists changes by listening to [listenable],
// the same way CrossTabPersistence relates to SelectedPlaceStore.
//
// Privacy: the id is an opaque server place id (e.g. 'seed-test-cafe') and carries
// no coordinates/PII (contract A2/A8 privacy scope: place-id only).
import 'package:flutter/foundation.dart';

/// Process-local singleton holding the saved-place id set. The reactive SSOT for
/// the SAVE action (§V5-B).
class SavedPlaceStore {
  SavedPlaceStore._();

  static final ValueNotifier<Set<String>> _notifier =
      ValueNotifier<Set<String>>(const <String>{});

  /// Cross-tab listenable for the saved-place id set. Listeners no-op-skip
  /// unchanged values because ValueNotifier suppresses redundant notifications
  /// (Set equality under the hood: a new instance is emitted on every change).
  static ValueListenable<Set<String>> get listenable => _notifier;

  /// The current saved-place id set (unmodifiable view).
  static Set<String> get current =>
      Set<String>.unmodifiable(_notifier.value);

  /// Whether [placeId] is saved.
  static bool isSaved(String placeId) => _notifier.value.contains(placeId);

  /// Restore the full set on cold start (action_preferences only). External
  /// callers toggle via [toggle]/[add]/[remove].
  // Why: the sole bulk-restore seam so persistence can hydrate without editing
  // every add site, mirroring SelectedPlaceStore.set.
  static void restore(Set<String> ids) =>
      _notifier.value = Set<String>.of(ids);

  /// Toggle a save. Returns the new saved state (true = now saved). Notifies
  /// listeners once.
  static bool toggle(String placeId) {
    final next = Set<String>.of(_notifier.value);
    final alreadySaved = next.remove(placeId);
    if (!alreadySaved) {
      next.add(placeId);
    }
    _notifier.value = next;
    return !alreadySaved;
  }

  /// Mark [placeId] saved (idempotent).
  static void add(String placeId) {
    if (_notifier.value.contains(placeId)) {
      return;
    }
    final next = Set<String>.of(_notifier.value)..add(placeId);
    _notifier.value = next;
  }

  /// Unmark [placeId] (idempotent).
  static void remove(String placeId) {
    if (!_notifier.value.contains(placeId)) {
      return;
    }
    final next = Set<String>.of(_notifier.value)..remove(placeId);
    _notifier.value = next;
  }

  /// Reset to empty (tests / re-onboarding).
  static void clear() => _notifier.value = const <String>{};
}
