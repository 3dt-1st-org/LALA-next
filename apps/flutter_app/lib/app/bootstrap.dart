// Wave-1 cold-start hydration.
//
// Runs before runApp: restores persisted onboarding/region state into the static
// holders so that GoRouter.redirect sees the true completion flag on the very
// first frame (no transient onboarding flash for a known-completed user) and the
// search/plan/map tabs seed their first backend from a retained manual region
// before they ever build.
//
// Privacy: only intentional choices are restored — completion, language, tourist
// type, manual region id. Precise current-device coordinates / RegionSource.current
// are never persisted, so a retained current context becomes null on cold start;
// the location provider may re-request it.
//
// Failure safety: any storage error degrades to a clean first-run state
// (completed=false, no region). The app always starts — including when the
// SharedPreferences-backed default cannot be created at all.
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/persistence/action_preferences.dart';
import 'package:lala_next_app/core/persistence/cross_tab_preferences.dart';
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/core/state/plan_context_store.dart';
import 'package:lala_next_app/core/state/saved_place_store.dart';
import 'package:lala_next_app/core/state/selected_place_store.dart';
import 'package:lala_next_app/core/state/slot_visit_store.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';

/// Factory that builds the production [OnboardingPreferences]. Injectable so
/// tests can simulate SharedPreferences plugin initialization throwing, which
/// [OnboardingPreferences.createDefault] itself cannot be made to do.
typedef OnboardingPreferencesFactory = Future<OnboardingPreferences> Function();

/// Factory that builds the production [CrossTabPreferences]. Injectable so
/// tests can pass an in-memory backend or simulate init failure, mirroring
/// [OnboardingPreferencesFactory].
typedef CrossTabPreferencesFactory = Future<CrossTabPreferences> Function();

/// Factory that builds the production [ActionPreferences] (V5-B SAVE/VISIT
/// persistence). Injectable so tests can pass an in-memory backend or simulate
/// init failure, mirroring [CrossTabPreferencesFactory].
typedef ActionPreferencesFactory = Future<ActionPreferences> Function();

/// Hydrates persisted onboarding/region state into the static holders and attaches
/// persistence for the rest of the process.
///
/// Pass [preferences] to inject an in-memory/fake store in tests, or
/// [preferencesFactory] to simulate the production default failing to initialize.
/// In production the SharedPreferences-backed default is created lazily and is
/// failure-safe: if plugin init throws, any stale persistence refs are detached,
/// memory is forced to a clean first run, and the app starts non-durable.
Future<void> bootstrapAppState({
  OnboardingPreferences? preferences,
  OnboardingPreferencesFactory? preferencesFactory,
  CrossTabPreferences? crossTabPreferences,
  CrossTabPreferencesFactory? crossTabPreferencesFactory,
  ActionPreferences? actionPreferences,
  ActionPreferencesFactory? actionPreferencesFactory,
}) async {
  final prefs = await _resolvePreferences(preferences, preferencesFactory);
  if (prefs == null) {
    // SharedPreferences init failed. Don't strand the app: drop any stale
    // persistence references, force a clean first-run memory state, and run this
    // session non-durable (choices hold in memory but won't survive a restart).
    OnboardingState.detachPersistence();
    RegionContextStore.detachPersistence();
    OnboardingState.reset();
    RegionContextStore.clear();
    // Cross-tab holders stay non-durable (in-memory only) for this session.
    CrossTabPersistence.detach();
    SelectedPlaceStore.clear();
    PlanContextStore.clear();
    // V5-B action holders stay non-durable (in-memory only) for this session.
    ActionPersistence.detach();
    SavedPlaceStore.clear();
    SlotVisitStore.clear();
    return;
  }
  // Attach so subsequent select/markCompleted/clear/set calls persist this session.
  OnboardingState.attachPersistence(prefs);
  RegionContextStore.attachPersistence(prefs);
  // load() never throws; an invalid manual id is already dropped to null.
  final snapshot = await prefs.load();
  OnboardingState.applySnapshot(snapshot);
  RegionContextStore.applyManualRegionId(snapshot.manualRegionId);

  // Cross-tab cold-start hydration (§13.4 / Lane 2). Built from the same
  // SharedPreferences singleton as onboarding. The epoch guard inside
  // attachAndHydrate suppresses a stale persisted value when a fresh selection
  // or plan lands during the load window. Failure-safe: a null resolution
  // leaves the cross-tab holders non-durable for the session.
  final crossTab = await _resolveCrossTabPreferences(
    crossTabPreferences,
    crossTabPreferencesFactory,
  );
  if (crossTab != null) {
    await CrossTabPersistence.attachAndHydrate(crossTab);
  }

  // V5-B action cold-start hydration (SAVE set + VISIT map). Built from the same
  // SharedPreferences singleton. The epoch guard inside attachAndHydrate
  // suppresses a stale persisted value when a fresh save/check-in lands during
  // the load window. Failure-safe: a null resolution leaves the action holders
  // non-durable for the session.
  final actions = await _resolveActionPreferences(
    actionPreferences,
    actionPreferencesFactory,
  );
  if (actions != null) {
    await ActionPersistence.attachAndHydrate(actions);
  }
}

Future<ActionPreferences?> _resolveActionPreferences(
  ActionPreferences? preferences,
  ActionPreferencesFactory? factory,
) async {
  if (preferences != null) {
    return preferences;
  }
  try {
    return await (factory ?? ActionPreferences.createDefault)();
  } on Object {
    // Plugin init failure: action holders stay non-durable for this session.
    return null;
  }
}

Future<OnboardingPreferences?> _resolvePreferences(
  OnboardingPreferences? preferences,
  OnboardingPreferencesFactory? factory,
) async {
  if (preferences != null) {
    return preferences;
  }
  try {
    return await (factory ?? OnboardingPreferences.createDefault)();
  } on Object {
    // Plugin init failure: degrade to a non-durable first run (see bootstrapAppState).
    return null;
  }
}

Future<CrossTabPreferences?> _resolveCrossTabPreferences(
  CrossTabPreferences? preferences,
  CrossTabPreferencesFactory? factory,
) async {
  if (preferences != null) {
    return preferences;
  }
  try {
    return await (factory ?? CrossTabPreferences.createDefault)();
  } on Object {
    // Plugin init failure: cross-tab stays non-durable for this session.
    return null;
  }
}
