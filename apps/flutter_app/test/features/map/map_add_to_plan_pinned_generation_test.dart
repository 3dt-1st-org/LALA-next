// D-1 회귀: addToPlan 액션이 요청된 카노니컬 장소를 selectedPlaceId 로 플랜
// 생성에 전달하고, 그 '정확한 플랜'을 PlanContextStore(공유 SSOT)에 게시하며,
// 플래너 시트를 연다. 포함을 보장할 수 없으면 시트를 열지 않고 정직한 실패
// 안내만 낸다(추가된 척 금지). 라이브 호출 없음 — 백엔드/위치는 주입 fake.
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
import 'package:lala_next_app/features/map_route/presentation/pages/map_route_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/planner/widgets/planner_sheet_content.dart';

import '../docent/inert_docent_audio_player.dart';

LalaEnvelope<T> _envelope<T>(T data) => LalaEnvelope<T>(
  ok: true,
  data: data,
  meta: const <String, dynamic>{'request_id': 'add-to-plan-test'},
  error: null,
  statusCode: 200,
  requestId: 'add-to-plan-test',
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
  // 저엔트로피 테스트 값(실제 키/해시 아님).
  requestHash: 'add-to-plan-pinned-test-hash',
  cacheKey: 'daily_plan:add-to-plan-pinned-test',
);

class _ImmediateLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() => Future.value(
    const LalaLocationResult.found(LalaLocation(lat: 37.2828, lng: 127.0101)),
  );
}

/// Map fake: records every createDailyPlan selectedPlaceId. The first call
/// (map refresh, unpinned) returns a plan without the place; the pinned call
/// must explicitly request the canonical id and then receives a plan that
/// includes it exactly once.
class _RecordingPlanBackend implements LalaBackend {
  final List<String?> requestedSelectedPlaceIds = <String?>[];
  final Object? Function(String? selectedPlaceId)? planFailure;

  _RecordingPlanBackend({this.planFailure});

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async =>
    _envelope(_placesResponse());

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({
    String? selectedPlaceId,
    LalaPlanPreferenceContext? preferenceContext,
    }) async {
    requestedSelectedPlaceIds.add(selectedPlaceId);
    final failure = planFailure?.call(selectedPlaceId);
    if (failure != null) {
      throw failure;
    }
    if (selectedPlaceId == null) {
      // 지도 리프레시용 비고정 플랜(장소 미포함) — 고정 요청과 구분된다.
      return _envelope(
        LalaDailyPlan(
          language: 'ko',
          center: const LalaCoordinate(lat: 37.2828, lng: 127.0101),
          radiusM: 3000,
          weather: _weather(),
          slots: const <LalaPlanSlot>[],
          source: 'db',
          requestHash: 'add-to-plan-unpinned-test-hash',
          cacheKey: 'daily_plan:add-to-plan-unpinned-test',
        ),
      );
    }
    return _envelope(_pinnedPlan());
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'not used in add-to-plan: ${invocation.memberName}',
  );
}

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
    'addToPlan generates a pinned plan, publishes the exact plan and opens the planner',
    (tester) async {
      final backend = _RecordingPlanBackend();
      final controller = LocalSignalActionController();
      final docentController = _docentController();
      addTearDown(docentController.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MapRoutePage(
            backendFactory: (config) => backend,
            initialConfig: const LalaAppConfig(baseUri: 'http://test'),
            locationProvider: _ImmediateLocationProvider(),
            recommendationRecoveryDelays: const <Duration>[],
            authControllerFactory: createLalaAuthController,
            localSignalActionController: controller,
            docentExperienceController: docentController,
          ),
        ),
      );
      await _flush(tester);

      // 액션 전: 리프레시만으로 발생한 비고정 플랜(장소 없음)이 공유 스토어에 있다.
      expect(backend.requestedSelectedPlaceIds, <String?>[null]);

      controller.dispatch(
        const LocalSignalPlaceActionRequest(
          placeId: 'pin-restaurant',
          action: LocalSignalPlaceAction.addToPlan,
        ),
      );
      await _flush(tester);

      // 고정 생성이 정확히 한 번, 카노니컬 id 로 요청되었다.
      expect(backend.requestedSelectedPlaceIds, <String?>[null, 'pin-restaurant']);
      // 공유 스토어(=크로스탭 persistence 게시 지점)가 '정확한 플랜'을 보유:
      // 장소가 포함되고, unpinned cache_key 와 다른 정체성이다.
      final shared = PlanContextStore.current;
      expect(shared, isNotNull);
      expect(shared!.cacheKey, 'daily_plan:add-to-plan-pinned-test');
      expect(
        shared.slots.where((s) => s.place?.placeId == 'pin-restaurant').length,
        1,
      );
      // 플래너 시트가 열려 그 플랜을 보여준다.
      expect(find.byType(PlannerSheetContent), findsOneWidget);
      expect(find.text('고정 맛집'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'addToPlan failure shows truthful copy and does not open the planner',
    (tester) async {
      final backend = _RecordingPlanBackend(
        planFailure: (selectedPlaceId) => selectedPlaceId == null
            ? null
            : const LalaApiException(
                code: 'HTTP_422',
                message: 'unavailable',
                statusCode: 422,
                retryable: false,
              ),
      );
      final controller = LocalSignalActionController();
      final docentController = _docentController();
      addTearDown(docentController.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MapRoutePage(
            backendFactory: (config) => backend,
            initialConfig: const LalaAppConfig(baseUri: 'http://test'),
            locationProvider: _ImmediateLocationProvider(),
            recommendationRecoveryDelays: const <Duration>[],
            authControllerFactory: createLalaAuthController,
            localSignalActionController: controller,
            docentExperienceController: docentController,
          ),
        ),
      );
      await _flush(tester);

      final before = PlanContextStore.current;
      controller.dispatch(
        const LocalSignalPlaceActionRequest(
          placeId: 'pin-restaurant',
          action: LocalSignalPlaceAction.addToPlan,
        ),
      );
      await _flush(tester);

      // 고정 요청은 발사했지만, 실패 → 정직한 안내 + 시트 미개방 + 스토어 보존.
      expect(backend.requestedSelectedPlaceIds, <String?>[null, 'pin-restaurant']);
      expect(find.text('이 장소를 일정에 추가하지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
      expect(find.byType(PlannerSheetContent), findsNothing);
      expect(identical(PlanContextStore.current, before), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
