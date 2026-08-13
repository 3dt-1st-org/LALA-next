// Cross-tab shared state (§13.4 / Lane 1, contract D1): the active daily plan,
// held in a process-local singleton so the plan shown on the map tab and the plan
// tab is the SAME object, not two independent createDailyPlan() fetches that can
// diverge. Structural mirror of RegionContextStore's *reactive surface*.
//
// In-memory only: this lane wires sharing, not durability. Lane 2 adds persistence
// (a versioned plan DTO under lala.crosstab.v1.*) + bootstrap cold-start hydration
// WITHOUT editing this holder, by attaching an external listener to [listenable]
// and restoring via [set] on cold start. That is why this file deliberately owns
// no prefs/keys/attachPersistence.
//
// Whichever tab generates/regenerates a plan publishes it via [set]; all tabs read
// the same value, eliminating the dual-fetch divergence (home_page createDailyPlan
// vs plan_page createDailyPlan). A tab that adopts a shared plan does NOT re-publish
// (last well-formed publish wins; no feedback loop).
import 'package:flutter/foundation.dart';

import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

/// Process-local singleton holding the active daily plan (or null = honest empty).
/// The reactive SSOT for cross-tab plan (§13.4 "일정 … 반응형으로 공유").
class PlanContextStore {
  PlanContextStore._();

  static final ValueNotifier<LalaDailyPlan?> _notifier =
      ValueNotifier<LalaDailyPlan?>(null);

  /// Cross-tab listenable for the active plan. Consumers must no-op-skip their own
  // publishes by comparing the new value against the plan they already hold.
  static ValueListenable<LalaDailyPlan?> get listenable => _notifier;

  /// The active daily plan, or null when none has been published this session.
  static LalaDailyPlan? get current => _notifier.value;

  /// Publish the active plan (or null to clear). One notification per assignment.
  // Why: the sole write seam so Lane 2 can persist by listening here and restore on
  // cold start by calling [set] — never by editing this holder.
  static void set(LalaDailyPlan? plan) => _notifier.value = plan;

  /// Reset to no plan (tests / re-onboarding).
  static void clear() => _notifier.value = null;
}
