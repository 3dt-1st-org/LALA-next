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
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';

/// Factory that builds the production [OnboardingPreferences]. Injectable so
/// tests can simulate SharedPreferences plugin initialization throwing, which
/// [OnboardingPreferences.createDefault] itself cannot be made to do.
typedef OnboardingPreferencesFactory = Future<OnboardingPreferences> Function();

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
    return;
  }
  // Attach so subsequent select/markCompleted/clear/set calls persist this session.
  OnboardingState.attachPersistence(prefs);
  RegionContextStore.attachPersistence(prefs);
  // load() never throws; an invalid manual id is already dropped to null.
  final snapshot = await prefs.load();
  OnboardingState.applySnapshot(snapshot);
  RegionContextStore.applyManualRegionId(snapshot.manualRegionId);
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
