// CP1: 모든 플랜 생성 진입점(지도 리프레시, addToPlan 고정 생성, 플랜 탭 생성)이
// '동일한' 유효 선호 컨텍스트를 보내는지 검증한다. 실제 기본 공급자 경로
// (전역 싱글턴 스토어 → composePlanPreferenceContext)를 그대로 사용한다 —
// 주입된 공급자로 대체하지 않는다. 싱글턴은 최초 1회 로드되므로, 파일 내 모든
// 테스트는 같은 시드를 사용한다.
import 'dart:convert';

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
import 'package:lala_next_app/features/plan/presentation/pages/plan_page.dart';
import 'package:lala_next_app/features/trip_library/domain/trip_library_models.dart';

import '../docent/inert_docent_audio_player.dart';

LalaEnvelope<T> _envelope<T>(T data) => LalaEnvelope<T>(
  ok: true,
  data: data,
  meta: const <String, dynamic>{'request_id': 'entry-point-ctx-test'},
  error: null,
  statusCode: 200,
  requestId: 'entry-point-ctx-test',
);

const LalaPlace _pinPlace = LalaPlace(
  placeId: 'pin-restaurant',
  name: '고정 맛집',
  category: 'restaurant',
  lat: 37.2828,
  lng: 127.0101,
  address: '주소',
  distanceM: 120,
  source: 'db',
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

LalaDailyPlan _plan({required String cacheKey, bool withPin = false}) =>
    LalaDailyPlan(
      language: 'ko',
      center: const LalaCoordinate(lat: 37.2828, lng: 127.0101),
      radiusM: 3000,
      weather: _weather(),
      slots: withPin
          ? [
              LalaPlanSlot(
                period: 'lunch',
                title: '점심',
                place: _pinPlace,
                weatherHint: 'good',
              ),
            ]
          : const <LalaPlanSlot>[],
      source: 'db',
      requestHash: 'entry-point-ctx-test-hash',
      cacheKey: cacheKey,
    );

/// 모든 createDailyPlan 호출의 (selectedPlaceId, preferenceContext) 를 기록.
class _RecordingBackend implements LalaBackend {
  final List<({String? selectedPlaceId, LalaPlanPreferenceContext? context})>
  requests = [];

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async => _envelope(
    LalaPlacesResponse(
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
    ),
  );

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({
    String? selectedPlaceId,
    LalaPlanPreferenceContext? preferenceContext,
  }) async {
    requests.add((selectedPlaceId: selectedPlaceId, context: preferenceContext));
    return _envelope(
      _plan(
        cacheKey: selectedPlaceId == null
            ? 'daily_plan:entry-unpinned'
            : 'daily_plan:entry-pinned',
        withPin: selectedPlaceId != null,
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() async => _envelope(
    LalaIntervention(
      center: const LalaCoordinate(lat: 37.2828, lng: 127.0101),
      radiusM: 3000,
      shouldIntervene: false,
      reason: 'ok',
      recommendedAction: 'ok',
      source: 'db',
    ),
  );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'not used here: ${invocation.memberName}',
  );
}

class _ImmediateLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() => Future.value(
    const LalaLocationResult.found(LalaLocation(lat: 37.2828, lng: 127.0101)),
  );
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// 시드가 만들어야 하는 유효 컨텍스트(override 는 지원 필드만 승리).
const LalaPlanPreferenceContext _expectedContext = LalaPlanPreferenceContext(
  indoorOutdoor: 'indoor', // override 승리(기본 outdoor)
  weatherSensitivity: 'high', // override 승리(기본 low)
  walkingBand: 'short', // override 승리(기본 medium)
  maxOneWayMinutes: 90, // 기본값 상속
  foodCuisines: <String>['korean'], // 기본값 상속(정렬)
  budgetBand: 'value', // 기본값 상속
  excludeClosingSoon: false, // 기본값 상속
);

void _seedPreferenceStores() {
  final planDate = tripLibraryDateKey();
  final preferencesDoc = jsonEncode(<String, dynamic>{
    'version': 1,
    'soft': <String, dynamic>{
      'indoor_outdoor': 'outdoor',
      'weather_sensitivity': 'low',
      'walking_band': 'medium',
      'food_cuisines': <String>['korean'],
      'max_one_way_minutes': 90,
      'budget_band': 'value',
      'exclude_closing_soon': false,
    },
    'hard': <String, dynamic>{},
    'locale': <String, dynamic>{},
  });
  final tripDoc = jsonEncode(<String, dynamic>{
    'v': 1,
    'overrides': <String, dynamic>{
      planDate: <String, dynamic>{
        'revision': 1,
        'updated_at': null,
        'dirty': false,
        'value': <String, dynamic>{
          'version': 1,
          'indoor_outdoor': 'indoor',
          'weather_sensitivity': 'high',
          'walking_band': 'short',
        },
      },
    },
    'visits': <String, dynamic>{},
  });
  SharedPreferences.setMockInitialValues(<String, Object>{
    'lala.travel_preferences.v1': preferencesDoc,
    'lala.trip_library.v1': tripDoc,
  });
}

DocentExperienceController _docentController() => DocentExperienceController(
  backendFactory: (_) => throw StateError('docent unused'),
  baseConfig: const LalaAppConfig(baseUri: ''),
  player: InertDocentAudioPlayer(),
);

void main() {
  setUp(() {
    _seedPreferenceStores();
    CrossTabPersistence.detach();
    SelectedPlaceStore.clear();
    PlanContextStore.clear();
    OnboardingState.reset();
    OnboardingState.markCompleted();
    OnboardingState.selectLanguage('ko');
  });

  tearDown(() {
    CrossTabPersistence.detach();
    SelectedPlaceStore.clear();
    PlanContextStore.clear();
    OnboardingState.reset();
  });

  testWidgets(
    'map refresh and addToPlan pinned generation send the same effective context',
    (tester) async {
      final backend = _RecordingBackend();
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

      // 진입점 1: 일반 지도 리프레시(비고정).
      expect(backend.requests.map((r) => r.selectedPlaceId), <String?>[null]);

      // 진입점 2: addToPlan 고정 생성.
      controller.dispatch(
        const LocalSignalPlaceActionRequest(
          placeId: 'pin-restaurant',
          action: LocalSignalPlaceAction.addToPlan,
        ),
      );
      await _flush(tester);
      expect(
        backend.requests.map((r) => r.selectedPlaceId),
        <String?>[null, 'pin-restaurant'],
      );

      // 두 진입점 모두 같은 유효 컨텍스트(시드된 기본값+override 합성)를 실었다.
      expect(
        backend.requests.map((r) => r.context),
        everyElement(_expectedContext),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'plan tab generation sends the same effective context as the map entry points',
    (tester) async {
      final backend = _RecordingBackend();
      await tester.pumpWidget(
        MaterialApp(
          home: PlanPage(
            locationProvider: _ImmediateLocationProvider(),
            backendFactory: (config) => backend,
          ),
        ),
      );
      await _flush(tester);

      // 진입점 3: 플랜 탭 최초 생성(비고정) — 지도 진입점과 동일한 컨텍스트.
      expect(backend.requests, hasLength(1));
      expect(backend.requests.single.selectedPlaceId, isNull);
      expect(backend.requests.single.context, _expectedContext);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
