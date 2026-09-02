// V5-B VISIT holder (§V5-B D2): the per-slot visit status, held in a process-local
// singleton so a check-in made on the plan tab persists across reloads and survives
// a cold start once action_preferences attaches. Structural mirror of
// PlanContextStore's reactive surface.
//
// In-memory only: this holder owns no prefs/keys. action_preferences.dart hydrates
// it on cold start (bootstrap) and persists changes by listening to [listenable].
//
// Keying: "$planDate:$slotPeriod" (contract A1/D1 — one plan per user per day, UTC
// date key). Value: "planned" | "visited" | "not_visited" (API status shape). A slot with
// no entry is implicitly "planned" (contract A9/D9 honest empty → slots render as
// planned), so the map only stores non-default (visited) entries.
import 'package:flutter/foundation.dart';

/// The visit status of a plan slot. Mirrors [LalaSlotVisit.status] string values
/// without depending on the generated client at the holder layer.
typedef SlotVisitMap = Map<String, String>;

/// Process-local singleton holding per-slot visit statuses. The reactive SSOT for
/// the VISIT action (§V5-B).
class SlotVisitStore {
  SlotVisitStore._();

  /// Default status for a slot with no recorded visit (contract A9 honest empty).
  static const String defaultStatus = 'planned';

  static final ValueNotifier<SlotVisitMap> _notifier =
      ValueNotifier<SlotVisitMap>(const <String, String>{});

  /// Cross-tab listenable for the visit map.
  static ValueListenable<SlotVisitMap> get listenable => _notifier;

  /// The current visit map (unmodifiable view).
  static SlotVisitMap get current =>
      Map<String, String>.unmodifiable(_notifier.value);

  /// Build the composite key for a slot.
  static String key(String planDate, String slotPeriod) =>
      '$planDate:$slotPeriod';

  /// Status for a slot, or [defaultStatus] when unrecorded (honest empty → planned).
  static String statusFor(String planDate, String slotPeriod) {
    return _notifier.value[key(planDate, slotPeriod)] ?? defaultStatus;
  }

  /// Restore the full map on cold start (action_preferences only).
  static void restore(SlotVisitMap visits) =>
      _notifier.value = Map<String, String>.of(visits);

  /// Toggle a slot between [defaultStatus] and [visited]. Returns the new status.
  /// Notifies listeners once. Idempotent re-check-in collapses to one entry
  /// (contract A5/D3 — no duplicate row).
  static String toggle(String planDate, String slotPeriod) {
    final k = key(planDate, slotPeriod);
    final next = Map<String, String>.of(_notifier.value);
    final visited = 'visited';
    final wasVisited = next[k] == visited;
    if (wasVisited) {
      // visited → planned: remove the entry so the map only stores non-defaults.
      next.remove(k);
    } else {
      next[k] = visited;
    }
    _notifier.value = next;
    return wasVisited ? defaultStatus : visited;
  }

  /// Sets an explicit bounded outcome. Planned remains the implicit default and
  /// is therefore removed from the persisted map.
  static void setStatus(String planDate, String slotPeriod, String status) {
    if (!const <String>{'planned', 'visited', 'not_visited'}.contains(status)) {
      throw ArgumentError.value(status, 'status', 'unknown visit status');
    }
    final k = key(planDate, slotPeriod);
    final next = Map<String, String>.of(_notifier.value);
    if (status == defaultStatus) {
      next.remove(k);
    } else {
      next[k] = status;
    }
    _notifier.value = next;
  }

  /// Reset to empty (tests / re-onboarding).
  static void clear() => _notifier.value = const <String, String>{};
}
