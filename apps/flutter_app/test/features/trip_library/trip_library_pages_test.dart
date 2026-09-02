import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/navigation/local_signal_action.dart';
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/core/state/plan_context_store.dart';
import 'package:lala_next_app/core/state/saved_place_store.dart';
import 'package:lala_next_app/core/state/slot_visit_store.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_remote.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_store.dart';
import 'package:lala_next_app/features/trip_library/domain/trip_library_models.dart';
import 'package:lala_next_app/features/trip_library/presentation/pages/past_trips_page.dart';
import 'package:lala_next_app/features/trip_library/presentation/pages/saved_places_page.dart';
import 'package:lala_next_app/features/trip_library/presentation/pages/trip_settings_page.dart';
import 'package:lala_next_app/features/trip_library/presentation/pages/visit_confirmation_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    OnboardingState.applySnapshot(
      const OnboardingSnapshot(completed: true, language: 'ko'),
    );
    SavedPlaceStore.clear();
    SlotVisitStore.clear();
    PlanContextStore.clear();
  });

  tearDown(() {
    OnboardingState.reset();
    SavedPlaceStore.clear();
    SlotVisitStore.clear();
    PlanContextStore.clear();
  });

  testWidgets(
    'S-22 saves a soft trip override without hiding safety defaults',
    (tester) async {
      await _phone(tester);
      final tripStore = TripLibraryStore();
      final preferencesStore = TravelPreferencesStore();
      await preferencesStore.ensureLoaded();
      await preferencesStore.save(
        const TravelPreferences(allergens: {Allergen.shellfish}),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TripSettingsPage(
            planDate: '2026-09-03',
            tripStore: tripStore,
            preferencesStore: preferencesStore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('trip-settings-page')), findsOneWidget);
      expect(find.text('이번 여행 설정'), findsOneWidget);
      await tester.tap(find.text('알차게'));
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(find.textContaining('알레르기·식이·접근성 조건'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('trip-settings-save')),
      );
      await tester.tap(find.byKey(const ValueKey('trip-settings-save')));
      await tester.pumpAndSettle();

      expect(tripStore.overrideFor('2026-09-03').pace, TravelPace.packed);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('S-23 projects saved IDs through current public place data', (
    tester,
  ) async {
    await _phone(tester);
    SavedPlaceStore.add(_place.placeId);

    await tester.pumpWidget(
      MaterialApp(
        home: SavedPlacesPage(
          backendFactory: (_) => _SavedPlaceBackend(),
          initialConfig: const LalaAppConfig(
            baseUri: 'https://example.invalid',
          ),
          actionController: LocalSignalActionController(),
          tripStore: TripLibraryStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('saved-places-page')), findsOneWidget);
    expect(find.text('성수 정본 식당'), findsOneWidget);
    expect(find.textContaining('실시간 추천'), findsOneWidget);
    expect(find.text('현재 정보를 확인할 수 없는 장소'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('S-24 shows account-scoped past trips without coordinates', (
    tester,
  ) async {
    await _phone(tester);
    final store = TripLibraryStore();
    await store.connectAccount(
      _TripRemote(
        pastTrips: const <PastTripSummary>[
          PastTripSummary(
            planDate: '2026-08-30',
            region: '서울 성동구',
            slotCount: 4,
            visitedCount: 3,
          ),
        ],
      ),
    );
    addTearDown(store.disconnectAccount);

    await tester.pumpWidget(MaterialApp(home: PastTripsPage(tripStore: store)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('past-trips-page')), findsOneWidget);
    expect(find.text('2026-08-30'), findsOneWidget);
    expect(find.text('서울 성동구'), findsOneWidget);
    expect(find.textContaining('좌표'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('S-24 discloses that past trips require an account', (
    tester,
  ) async {
    await _phone(tester);

    await tester.pumpWidget(
      MaterialApp(home: PastTripsPage(tripStore: TripLibraryStore())),
    );
    await tester.pumpAndSettle();

    expect(find.text('계정 연결이 필요해요.'), findsOneWidget);
    expect(find.textContaining('현재 일정은 이 기기에 유지'), findsOneWidget);
  });

  testWidgets('S-25 stores a bounded not-visited reason and explicit consent', (
    tester,
  ) async {
    await _phone(tester);
    final store = TripLibraryStore();
    const slot = LalaPlanSlot(period: 'lunch', title: '점심 식사', place: _place);

    await tester.pumpWidget(
      MaterialApp(
        home: VisitConfirmationPage(
          planDate: '2026-09-03',
          slotPeriod: 'lunch',
          slot: slot,
          tripStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('visit-confirmation-page')),
      findsOneWidget,
    );
    expect(find.text('성수 정본 식당'), findsOneWidget);
    expect(find.text('점심 식사'), findsNothing);
    await tester.tap(find.text('방문하지 않았어요'));
    await tester.pump();
    await tester.tap(find.text('날씨'));
    await tester.tap(
      find.byKey(const ValueKey('visit-recommendation-consent')),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('save-visit-outcome')),
    );
    await tester.tap(find.byKey(const ValueKey('save-visit-outcome')));
    await tester.pumpAndSettle();

    final feedback = store.visitFor('2026-09-03', 'lunch');
    expect(feedback.status, TripVisitStatus.notVisited);
    expect(feedback.reason, TripVisitReason.weather);
    expect(feedback.useForRecommendations, isTrue);
    expect(SlotVisitStore.statusFor('2026-09-03', 'lunch'), 'not_visited');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _phone(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

const LalaPlace _place = LalaPlace(
  placeId: 'canonical-restaurant',
  name: '성수 정본 식당',
  nameKo: '성수 정본 식당',
  nameEn: 'Canonical Seongsu Restaurant',
  category: 'restaurant',
  lat: 37.55,
  lng: 127.04,
  address: '서울특별시 성동구',
  regionKo: '성수동',
  regionEn: 'Seongsu-dong',
  distanceM: 420,
  source: 'db',
  upstreamSource: 'tour_api',
);

class _SavedPlaceBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async => _envelope(
    const LalaPlacesResponse(
      count: 1,
      places: <LalaPlace>[_place],
      query: LalaPlacesQuery(
        lat: 37.55,
        lng: 127.04,
        radiusM: 3000,
        limit: 100,
        category: 'all',
        language: 'ko',
      ),
      source: 'db',
      locationEngine: 'postgis',
      dataAsOf: '2026-09-03T09:00:00Z',
    ),
  );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used');
}

class _TripRemote implements TripLibraryRemote {
  _TripRemote({this.pastTrips = const <PastTripSummary>[]});

  final List<PastTripSummary> pastTrips;

  @override
  Future<void> deleteOverride(String planDate) async {}

  @override
  Future<void> deletePlan(String planDate) async {}

  @override
  Future<TripOverrideDocument?> getOverride(String planDate) async => null;

  @override
  Future<Set<String>> listSavedPlaceIds() async => const <String>{};

  @override
  Future<List<PastTripSummary>> listPastTrips({
    String? before,
    int limit = 20,
  }) async => pastTrips;

  @override
  Future<Map<String, TripVisitFeedback>> listVisits(String planDate) async =>
      const <String, TripVisitFeedback>{};

  @override
  Future<LalaDailyPlan?> loadPlan(String planDate) async => null;

  @override
  Future<TripOverrideDocument> putOverride(
    String planDate, {
    required int expectedRevision,
    required TripPreferenceOverride value,
  }) async => TripOverrideDocument(
    value: value,
    revision: expectedRevision + 1,
    updatedAt: null,
  );

  @override
  Future<TripVisitFeedback> putVisit(
    String planDate,
    String slotPeriod, {
    required String? placeId,
    required TripVisitFeedback feedback,
  }) async => feedback;

  @override
  Future<void> savePlan(String planDate, Map<String, dynamic> plan) async {}

  @override
  Future<void> setSavedPlace(String placeId, {required bool saved}) async {}
}

LalaEnvelope<T> _envelope<T>(T data) => LalaEnvelope<T>(
  ok: true,
  data: data,
  meta: const <String, dynamic>{},
  error: null,
  statusCode: 200,
  requestId: 'trip-library-screen-test',
);
