// CP1 regression: the plan composer awaits the process-wide preference/trip
// store singletons from every plan-generation entry point, so `ensureLoaded`
// must be safe to call from a *later* Flutter test zone than the one that
// performed the first load. Awaiting a future that completed inside an earlier
// (now dead) zone's fake async hung the later test; the stores now hand out a
// fresh completed future per call once loaded.
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:lala_next_app/features/planning/domain/plan_preference_context.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_store.dart';

void main() {
  testWidgets('first zone: singleton loads and composer resolves', (tester) async {
    await TravelPreferencesStore.instance.ensureLoaded();
    await TripLibraryStore.instance.ensureLoaded();
    expect(TravelPreferencesStore.instance.isLoaded, isTrue);
    expect(TripLibraryStore.instance.isLoaded, isTrue);

    final context = await composePlanPreferenceContext();
    expect(context, isA<LalaPlanPreferenceContext>());
    expect(context.maxOneWayMinutes, greaterThan(0));
  });

  testWidgets(
    'later zone: ensureLoaded/composer must not await a dead zone future',
    (tester) async {
      // Regression: pre-fix these awaits never completed in the second zone.
      await TravelPreferencesStore.instance.ensureLoaded();
      await TripLibraryStore.instance.ensureLoaded();

      final context = await composePlanPreferenceContext();
      expect(context, isA<LalaPlanPreferenceContext>());
    },
  );
}
