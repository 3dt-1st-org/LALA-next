import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/core/state/plan_context_store.dart';
import 'package:lala_next_app/core/state/saved_place_store.dart';
import 'package:lala_next_app/core/state/slot_visit_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_remote.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_store.dart';
import 'package:lala_next_app/features/trip_library/domain/trip_library_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SavedPlaceStore.clear();
    SlotVisitStore.clear();
    PlanContextStore.clear();
  });

  test('one-trip override cannot weaken dietary or accessibility safety', () {
    const defaults = TravelPreferences(
      pace: TravelPace.balanced,
      allergens: {Allergen.shellfish},
      dietaryModes: {DietaryMode.halal},
      avoidIngredients: '고수',
      avoidStairs: true,
      verifiedAccessibilityOnly: true,
    );
    const override = TripPreferenceOverride(
      pace: TravelPace.packed,
      crowdTolerance: CrowdTolerance.popular,
      maxWaitMinutes: 40,
    );

    final effective = override.applyTo(defaults);

    expect(effective.pace, TravelPace.packed);
    expect(effective.crowdTolerance, CrowdTolerance.popular);
    expect(effective.maxWaitMinutes, 40);
    expect(effective.allergens, {Allergen.shellfish});
    expect(effective.dietaryModes, {DietaryMode.halal});
    expect(effective.avoidIngredients, '고수');
    expect(effective.avoidStairs, isTrue);
    expect(effective.verifiedAccessibilityOnly, isTrue);
    expect(override.toJson(), isNot(contains('allergens')));
    expect(override.toJson(), isNot(contains('avoid_stairs')));
  });

  test('trip library date key preserves the selected calendar date', () {
    final selectedDate = DateTime(2026, 9, 3, 0, 5);

    expect(tripLibraryDateKey(selectedDate), '2026-09-03');
  });

  test(
    'override and visit metadata round-trip through device storage',
    () async {
      const date = '2026-09-03';
      final first = TripLibraryStore();
      await first.ensureLoaded();
      await first.saveOverride(
        date,
        const TripPreferenceOverride(
          pace: TravelPace.relaxed,
          companions: {TravelCompanion.family},
        ),
      );
      await first.saveVisit(
        date,
        'evening',
        placeId: 'place-safe-id',
        feedback: const TripVisitFeedback(
          status: TripVisitStatus.notVisited,
          reason: TripVisitReason.weather,
          useForRecommendations: true,
          confirmedAt: '2026-09-03T10:00:00Z',
        ),
      );

      SlotVisitStore.clear();
      final second = TripLibraryStore();
      await second.ensureLoaded();

      expect(second.overrideFor(date).pace, TravelPace.relaxed);
      expect(second.overrideFor(date).companions, {TravelCompanion.family});
      expect(
        second.visitFor(date, 'evening'),
        isA<TripVisitFeedback>()
            .having(
              (value) => value.status,
              'status',
              TripVisitStatus.notVisited,
            )
            .having((value) => value.reason, 'reason', TripVisitReason.weather)
            .having(
              (value) => value.useForRecommendations,
              'recommendation consent',
              isTrue,
            ),
      );
      expect(SlotVisitStore.statusFor(date, 'evening'), 'not_visited');

      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(kTripLibraryStorageKey);
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded.keys, containsAll(<String>['v', 'overrides', 'visits']));
      expect(raw, isNot(contains('place-safe-id')));
    },
  );

  test('different account override becomes an explicit conflict', () async {
    final date = tripLibraryDateKey();
    final store = TripLibraryStore();
    await store.ensureLoaded();
    await store.saveOverride(
      date,
      const TripPreferenceOverride(pace: TravelPace.relaxed),
    );
    final remote = _MemoryTripRemote(
      overrides: <String, TripOverrideDocument>{
        date: const TripOverrideDocument(
          value: TripPreferenceOverride(pace: TravelPace.packed),
          revision: 4,
          updatedAt: '2026-09-03T00:00:00Z',
        ),
      },
    );

    await store.connectAccount(remote);
    addTearDown(store.disconnectAccount);

    expect(store.syncStatus, TripLibrarySyncStatus.conflict);
    expect(store.overrideFor(date).pace, TravelPace.relaxed);
    expect(store.overrideDocumentFor(date)?.revision, 4);
    expect(store.overrideDocumentFor(date)?.dirty, isTrue);
  });

  test('remote failure leaves visit outcome on this device', () async {
    const date = '2026-09-03';
    final store = TripLibraryStore();
    final remote = _MemoryTripRemote(failVisit: true);
    await store.connectAccount(remote);
    addTearDown(store.disconnectAccount);

    await store.saveVisit(
      date,
      'lunch',
      placeId: 'restaurant-id',
      feedback: const TripVisitFeedback(
        status: TripVisitStatus.visited,
        useForRecommendations: false,
      ),
    );

    expect(store.syncStatus, TripLibrarySyncStatus.error);
    expect(store.visitFor(date, 'lunch').status, TripVisitStatus.visited);
    expect(SlotVisitStore.statusFor(date, 'lunch'), 'visited');

    final restored = TripLibraryStore();
    await restored.ensureLoaded();
    expect(restored.visitFor(date, 'lunch').status, TripVisitStatus.visited);
  });

  test('saved-place reconciliation unions device and account IDs', () async {
    SavedPlaceStore.add('device-place');
    final remote = _MemoryTripRemote(savedIds: <String>{'account-place'});
    final store = TripLibraryStore();

    await store.connectAccount(remote);
    addTearDown(store.disconnectAccount);

    expect(SavedPlaceStore.current, {'device-place', 'account-place'});
    expect(remote.savedIds, {'device-place', 'account-place'});
    expect(store.syncStatus, TripLibrarySyncStatus.synced);
  });
}

class _MemoryTripRemote implements TripLibraryRemote {
  _MemoryTripRemote({
    Set<String>? savedIds,
    Map<String, TripOverrideDocument>? overrides,
    this.failVisit = false,
  }) : savedIds = savedIds ?? <String>{},
       overrides = overrides ?? <String, TripOverrideDocument>{};

  final Set<String> savedIds;
  final Map<String, TripOverrideDocument> overrides;
  final bool failVisit;
  final Map<String, Map<String, TripVisitFeedback>> visits =
      <String, Map<String, TripVisitFeedback>>{};

  @override
  Future<void> deleteOverride(String planDate) async {
    overrides.remove(planDate);
  }

  @override
  Future<void> deletePlan(String planDate) async {}

  @override
  Future<TripOverrideDocument?> getOverride(String planDate) async =>
      overrides[planDate];

  @override
  Future<Set<String>> listSavedPlaceIds() async => Set<String>.of(savedIds);

  @override
  Future<List<PastTripSummary>> listPastTrips({
    String? before,
    int limit = 20,
  }) async => const <PastTripSummary>[];

  @override
  Future<Map<String, TripVisitFeedback>> listVisits(String planDate) async =>
      Map<String, TripVisitFeedback>.of(
        visits[planDate] ?? const <String, TripVisitFeedback>{},
      );

  @override
  Future<LalaDailyPlan?> loadPlan(String planDate) async => null;

  @override
  Future<TripOverrideDocument> putOverride(
    String planDate, {
    required int expectedRevision,
    required TripPreferenceOverride value,
  }) async {
    final next = TripOverrideDocument(
      value: value,
      revision: expectedRevision + 1,
      updatedAt: '2026-09-03T00:00:00Z',
    );
    overrides[planDate] = next;
    return next;
  }

  @override
  Future<TripVisitFeedback> putVisit(
    String planDate,
    String slotPeriod, {
    required String? placeId,
    required TripVisitFeedback feedback,
  }) async {
    if (failVisit) throw StateError('offline');
    visits.putIfAbsent(
      planDate,
      () => <String, TripVisitFeedback>{},
    )[slotPeriod] = feedback;
    return feedback;
  }

  @override
  Future<void> savePlan(String planDate, Map<String, dynamic> plan) async {}

  @override
  Future<void> setSavedPlace(String placeId, {required bool saved}) async {
    if (saved) {
      savedIds.add(placeId);
    } else {
      savedIds.remove(placeId);
    }
  }
}
