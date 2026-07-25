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
// (completed=false, no region). The app always starts.
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';

/// Hydrates persisted onboarding/region state into the static holders and attaches
/// persistence for the rest of the process. Pass [preferences] to inject an
/// in-memory/fake store in tests; in production the SharedPreferences-backed
/// default is created lazily.
Future<void> bootstrapAppState({OnboardingPreferences? preferences}) async {
  final prefs = preferences ?? await OnboardingPreferences.createDefault();
  // Attach so subsequent select/markCompleted/clear/set calls persist this session.
  OnboardingState.attachPersistence(prefs);
  RegionContextStore.attachPersistence(prefs);
  // load() never throws; an invalid manual id is already dropped to null.
  final snapshot = await prefs.load();
  OnboardingState.applySnapshot(snapshot);
  RegionContextStore.applyManualRegionId(snapshot.manualRegionId);
}
