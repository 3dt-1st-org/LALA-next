// P1 회귀(D-1 정오회보): unpinned 리프레시가 먼저 시작되고, addToPlan 고정 생성이
// 먼저 완료되어 게시된 뒤, '오래된 unpinned 요청'이 가장 늦게 완료되는 인터리빙에서
// 정확한 고정 플랜과 선택 장소가 HomePage 상태/UI 와 PlanContextStore 모두에
// 그대로 남아 있어야 한다. 완순 제어는 completer fake 로만(슬립 금지).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/navigation/local_signal_action.dart';
import 'package:lala_next_app/core/persistence/cross_tab_preferences.dart';
import 'package:lala_next_app/core/state/plan_context_store.dart';
import 'package:lala_next_app/core/state/selected_place_store.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_controller.dart';
import 'package:lala_next_app/features/home/home_page.dart';
import 'package:lala_next_app/features/map_route/presentation/pages/map_route_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/planner/widgets/planner_sheet_content.dart';

import '../docent/inert_docent_audio_player.dart';

LalaEnvelope<T> _envelope<T>(T data) => LalaEnvelope<T>(
  ok: true,
  data: data,
  meta: const <String, dynamic>{'request_id': 'pinned-race-test'},
  error: null,
  statusCode: 200,
  requestId: 'pinned-race-test',
);

const LalaPlace _pinPlace = LalaPlace(
  placeId: 'pin-restaurant',
  name: '고정 맛집',
  nameKo: '고정 맛집',
  nameEn: 'Pinned Restaurant',
  category: 'restaurant',
  lat: 37.2828,
  lng: 127.0101,
  address: '경기도 수원시 팔달구',
  regionKo: '수원',
  regionEn: 'Suwon',
  distanceM: 120,
  source: 'db',
);

LalaPlacesResponse _placesResponse() => LalaPlacesResponse(
  count: 1,
  places: const <LalaPlace>[_pinPlace],
  query: const LalaPlacesQuery(
    lat: 37.2828,
    lng: 127.0101,
    radiusM: 3000,
    limit: 60,
    category: 'all',
    language: 'ko',
  ),
  source: 'db',
  locationEngine: 'postgis',
);

LalaWeather _weather() => LalaWeather(
  lat: 37.2828,
  lng: 127.0101,
  temp: '14°C',
  icon: 'partly-cloudy',
  dust: const LalaDust(
    pm10: '31',
    pm25: '14',
    grade: 'normal',
    gradeKo: '보통',
    pm10Grade: 'normal',
    pm10GradeKo: '보통',
    pm25Grade: 'good',
    pm25GradeKo: '좋음',
  ),
  forecast: const <LalaForecastItem>[],
  outdoorStatus: 'good',
  force: false,
  source: 'db',
);

LalaDailyPlan _pinnedPlan() => LalaDailyPlan(
  language: 'ko',
  center: const LalaCoordinate(lat: 37.2828, lng: 127.0101),
  radiusM: 3000,
  weather: _weather(),
  slots: [
    LalaPlanSlot(
      period: 'lunch',
      title: '점심',
      place: _pinPlace,
      weatherHint: 'good',
      swappableAlternatives: const <LalaPlace>[],
    ),
  ],
  source: 'db',
  requestHash: 'pinned-race-test-hash',
  cacheKey: 'daily_plan:pinned-race-test',
);

/// 고정 플랜과 '다른' 슬롯 정체성을 가진 unpinned 플랜 — 늦은 도착이 채택되면
/// UI/스토어에서 이 슬롯 텍스트로 즉시 탐지된다.
LalaDailyPlan _unpinnedPlan() => LalaDailyPlan(
  language: 'ko',
  center: const LalaCoordinate(lat: 37.2828, lng: 127.0101),
  radiusM: 3000,
  weather: _weather(),
  slots: [
    LalaPlanSlot(
      period: 'morning',
      title: '오전',
      place: const LalaPlace(
        placeId: 'unpinned-place',
        name: '대체 안맞는 장소',
        category: 'attraction',
        lat: 37.2828,
        lng: 127.0101,
        address: '주소',
        distanceM: 90,
        source: 'db',
      ),
      weatherHint: 'good',
    ),
  ],
  source: 'db',
  requestHash: 'unpinned-race-test-hash',
  cacheKey: 'daily_plan:unpinned-race-test',
);

class _ImmediateLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() => Future.value(
    const LalaLocationResult.found(LalaLocation(lat: 37.2828, lng: 127.0101)),
  );
}

/// Completer-제어 fake: places 와 unpinned/pinned createDailyPlan 각각 독립된
/// 완료 지점을 가진다. 나머지 엔드포인트는 throw — _refresh 의 loadOptional 이
/// reportError:false 로 흡수하므로 places/plan await 만이 유일한 경합 지점이 된다.
class _RaceBackend implements LalaBackend {
  _RaceBackend(this.config);

  final LalaAppConfig config;

  final Completer<LalaEnvelope<LalaPlacesResponse>> placesCompleter =
      Completer<LalaEnvelope<LalaPlacesResponse>>();
  final Completer<LalaEnvelope<LalaDailyPlan>> unpinnedPlanCompleter =
      Completer<LalaEnvelope<LalaDailyPlan>>();
  final Completer<LalaEnvelope<LalaDailyPlan>> pinnedPlanCompleter =
      Completer<LalaEnvelope<LalaDailyPlan>>();

  int unpinnedPlanCalls = 0;
  int pinnedPlanCalls = 0;

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() =>
      placesCompleter.future;

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({
    String? selectedPlaceId,
  }) {
    if (selectedPlaceId == null) {
      unpinnedPlanCalls++;
      return unpinnedPlanCompleter.future;
    }
    pinnedPlanCalls++;
    return pinnedPlanCompleter.future;
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'not used in pinned-race: ${invocation.memberName}',
  );
}

/// Bounded flush — 리프레시/재생성 타이머 기계가 프레임 루프를 계속 살릴 수 있어
/// pumpAndSettle 대신 사용한다(슬립이 아닌 프레임 펌핑).
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

DocentExperienceController _docentController() => DocentExperienceController(
  backendFactory: (_) => throw StateError('docent unused'),
  baseConfig: const LalaAppConfig(baseUri: ''),
  player: InertDocentAudioPlayer(),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CrossTabPersistence.detach();
    SelectedPlaceStore.clear();
    PlanContextStore.clear();
    OnboardingState.reset();
    OnboardingState.markCompleted();
  });

  tearDown(() {
    CrossTabPersistence.detach();
    SelectedPlaceStore.clear();
    PlanContextStore.clear();
    OnboardingState.reset();
  });

  testWidgets(
    'late stale unpinned refresh cannot overwrite the published pinned plan',
    (tester) async {
      final backends = <_RaceBackend>[];
      final controller = LocalSignalActionController();
      final docentController = _docentController();
      addTearDown(docentController.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MapRoutePage(
            backendFactory: (config) {
              final backend = _RaceBackend(config);
              backends.add(backend);
              return backend;
            },
            initialConfig: const LalaAppConfig(baseUri: 'http://test'),
            locationProvider: _ImmediateLocationProvider(),
            recommendationRecoveryDelays: const <Duration>[],
            authControllerFactory: createLalaAuthController,
            localSignalActionController: controller,
            docentExperienceController: docentController,
          ),
        ),
      );

      // Descendant context so the test seams' findAncestorStateOfType resolves.
      final context = tester.element(
        find.descendant(
          of: find.byType(LalaHomePage),
          matching: find.byType(Scaffold),
        ),
      );

      // 1) Prime: initial (location-driven) refresh #0 completes fully — its
      //    unpinned plan is published to the store.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(backends.length, greaterThanOrEqualTo(2));
      backends[1].placesCompleter.complete(_envelope(_placesResponse()));
      backends[1].unpinnedPlanCompleter.complete(_envelope(_unpinnedPlan()));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(PlanContextStore.current?.cacheKey, 'daily_plan:unpinned-race-test');

      // 2) The RACED unpinned refresh begins first: places resolve so it passes
      //    the mid-refresh epoch guard (loading=false) and fires its unpinned
      //    createDailyPlan — then suspends at the plan await.
      LalaHomePage.simulateRefreshForTesting(context);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(backends.length, 3);
      final raceBackend = backends[2];
      raceBackend.placesCompleter.complete(_envelope(_placesResponse()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(raceBackend.unpinnedPlanCalls, 1);
      expect(LalaHomePage.placesStateForTesting(context).loading, isFalse);

      // 3) addToPlan: pinned generation starts (invalidating the in-flight
      //    refresh) and suspends at its own plan await.
      controller.dispatch(
        const LocalSignalPlaceActionRequest(
          placeId: 'pin-restaurant',
          action: LocalSignalPlaceAction.addToPlan,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(raceBackend.pinnedPlanCalls, 1);

      // 4) The PINNED request completes FIRST → exact pinned plan published to
      //    HomePage state, PlanContextStore and the planner sheet.
      raceBackend.pinnedPlanCompleter.complete(_envelope(_pinnedPlan()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(PlanContextStore.current?.cacheKey, 'daily_plan:pinned-race-test');
      expect(find.byType(PlannerSheetContent), findsOneWidget);

      // 5) The OLDER unpinned request completes LAST — it must be discarded
      //    before it can touch state or the store.
      raceBackend.unpinnedPlanCompleter.complete(_envelope(_unpinnedPlan()));
      await _flush(tester);

      // Exact pinned plan intact in HomePage state (not just the store).
      final statePlan = LalaHomePage.dailyPlanStateForTesting(context);
      expect(statePlan?.data?.cacheKey, 'daily_plan:pinned-race-test');
      expect(identical(statePlan?.data, PlanContextStore.current), isTrue);
      expect(
        statePlan?.data?.slots
            .where((s) => s.place?.placeId == 'pin-restaurant')
            .length,
        1,
      );
      // Selected place survives too.
      expect(SelectedPlaceStore.current, 'pin-restaurant');
      // UI: planner sheet still shows the pinned place, never the unpinned slot.
      expect(find.byType(PlannerSheetContent), findsOneWidget);
      expect(find.text('고정 맛집'), findsWidgets);
      expect(find.text('대체 안맞는 장소'), findsNothing);
      // The epoch bump must not leave the loading indicator stuck.
      expect(LalaHomePage.placesStateForTesting(context).loading, isFalse);

      // Resolve the never-awaited init-state backend for a clean clock.
      backends[0].placesCompleter.complete(_envelope(_placesResponse()));
      backends[0].unpinnedPlanCompleter.complete(_envelope(_unpinnedPlan()));
      await _flush(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
