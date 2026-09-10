// D-1 회귀(교차 탭 재생성 금지): 플랜 탭 첫 진입은 현재 요청 컨텍스트와 같은
// 활성 플랜이 공유 스토어에 있으면 그 인스턴스를 채택한다 — 재요청/재생성 없음.
// 뷰 전환만으로 슬롯이 뒤섞이던 결함(맵 플랜 vs 플랜 탭 자체 생성)의 회귀 검증.
// 명시적 새로고침(달력/재생성)은 여전히 네트워크 생성을 돈다.
// P2 회귀(정오회보): 마운트 이후 게시된 공유 플랜도 같은 호환 계약
// (_canAdoptSharedPlan)으로 걸러진다 — 다른 언어/반경/지역의 플랜(지역·언어
// 리로드 중 도착 포함)은 채택되지 않고, 호환 플랜 채택은 계속 동작한다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/state/plan_context_store.dart';
import 'package:lala_next_app/features/plan/presentation/pages/plan_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/manual_location_options.dart';

const double _lat = 37.2828;
const double _lng = 127.0101;

LalaEnvelope<T> _envelope<T>(T data) => LalaEnvelope<T>(
  ok: true,
  data: data,
  meta: const <String, dynamic>{'request_id': 'plan-adoption-test'},
  error: null,
  statusCode: 200,
  requestId: 'plan-adoption-test',
);

LalaWeather _weather() => LalaWeather(
  lat: _lat,
  lng: _lng,
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

LalaPlanSlot _slot(String period, String title, String placeId, String name) =>
    LalaPlanSlot(
      period: period,
      title: title,
      place: LalaPlace(
        placeId: placeId,
        name: name,
        category: 'attraction',
        lat: _lat,
        lng: _lng,
        address: '주소',
        distanceM: 100,
        source: 'db',
      ),
      weatherHint: 'good',
    );

LalaDailyPlan _sharedPlan({
  String language = 'ko',
  double lat = _lat,
  double lng = _lng,
  int radiusM = 3000,
  String cacheKey = 'daily_plan:shared-active-plan',
}) => LalaDailyPlan(
  language: language,
  center: LalaCoordinate(lat: lat, lng: lng),
  radiusM: radiusM,
  weather: _weather(),
  slots: [
    _slot('morning', '오전', 'shared-place-1', '공유 플랜 명소'),
    _slot('lunch', '점심', 'shared-place-2', '공유 플랜 식당'),
  ],
  source: 'db',
  requestHash: 'shared-active-plan-hash',
  cacheKey: cacheKey,
);

class _FoundLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() => Future.value(
    const LalaLocationResult.found(LalaLocation(lat: _lat, lng: _lng)),
  );
}

/// createDailyPlan 이 completer 로 완순 제어되는 fake — region/language 리로드
/// 경합처럼 '요청 중' 상태를 만들어야 하는 테스트용. 슬립 없이 명시적 완료 지점.
class _ControlledPlanBackend implements LalaBackend {
  final Completer<LalaEnvelope<LalaDailyPlan>> planCompleter =
      Completer<LalaEnvelope<LalaDailyPlan>>();
  int planRequestCount = 0;

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({
    String? selectedPlaceId,
    LalaPlanPreferenceContext? preferenceContext,
    }) {
    planRequestCount++;
    return planCompleter.future;
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'not used in plan adoption: ${invocation.memberName}',
  );
}

LalaDailyPlan _freshPlan() => LalaDailyPlan(
  language: 'ko',
  center: const LalaCoordinate(lat: _lat, lng: _lng),
  radiusM: 3000,
  weather: _weather(),
  slots: [_slot('morning', '오전', 'fresh-place', '새로 생성된 플랜')],
  source: 'db',
  requestHash: 'fresh-plan-hash',
  cacheKey: 'daily_plan:fresh-plan',
);

/// createDailyPlan 이 호출되면 즉시 완료되는 fake — 채택 경로에서는 불리지 않아야
/// 하고, 자체 생성 경로(호환 불가/명시적 새로고침)에서 즉시 플랜을 반환한다.
class _NoFetchBackend implements LalaBackend {
  int planRequestCount = 0;

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({
    String? selectedPlaceId,
    LalaPlanPreferenceContext? preferenceContext,
    }) async {
    planRequestCount++;
    return _envelope(_freshPlan());
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'not used in plan adoption: ${invocation.memberName}',
  );
}

void main() {
  setUp(() {
    PlanContextStore.clear();
    OnboardingState.reset();
    OnboardingState.selectLanguage('ko');
  });

  tearDown(() {
    PlanContextStore.clear();
    OnboardingState.reset();
  });

  Future<void> pumpPlan(WidgetTester tester, _NoFetchBackend backend) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlanPage(
          locationProvider: _FoundLocationProvider(),
          backendFactory: (config) => backend,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'first open adopts the compatible shared plan without refetching '
    '(no cross-tab reshuffle)',
    (tester) async {
      final shared = _sharedPlan();
      PlanContextStore.set(shared);
      final backend = _NoFetchBackend();
      await pumpPlan(tester, backend);

      // 동일 인스턴스 채택: 네트워크 생성 0회, 공유 플랜의 슬롯 그대로 노출.
      expect(backend.planRequestCount, 0);
      expect(identical(PlanContextStore.current, shared), isTrue);
      expect(find.text('공유 플랜 명소'), findsOneWidget);
      expect(find.text('공유 플랜 식당'), findsOneWidget);
      expect(find.text('새로 생성된 플랜'), findsNothing);
    },
  );

  testWidgets(
    'incompatible shared plan (language change) still fetches its own plan',
    (tester) async {
      PlanContextStore.set(_sharedPlan(language: 'en'));
      final backend = _NoFetchBackend();
      await pumpPlan(tester, backend);

      expect(backend.planRequestCount, 1);
      expect(find.text('새로 생성된 플랜'), findsOneWidget);
    },
  );

  testWidgets(
    'incompatible shared plan (far center) still fetches its own plan',
    (tester) async {
      // 요청 중심(37.28, 127.01)에서 플랜 반경(3km) 밖의 부산 중심 플랜은 채택 불가.
      PlanContextStore.set(_sharedPlan(lat: 35.1796, lng: 129.0756));
      final backend = _NoFetchBackend();
      await pumpPlan(tester, backend);

      expect(backend.planRequestCount, 1);
      expect(find.text('새로 생성된 플랜'), findsOneWidget);
    },
  );

  testWidgets('explicit refresh (calendar) regenerates over the adopted plan', (
    tester,
  ) async {
    PlanContextStore.set(_sharedPlan());
    final backend = _NoFetchBackend();
    await pumpPlan(tester, backend);
    expect(backend.planRequestCount, 0);
    expect(find.text('공유 플랜 명소'), findsOneWidget);

    // 달력 액션 = 명시적 새로고침 → 새 플랜 생성(재게시)이 허용된다.
    await tester.tap(find.byTooltip('달력'));
    await tester.pumpAndSettle();

    expect(backend.planRequestCount, 1);
    expect(find.text('새로 생성된 플랜'), findsOneWidget);
    expect(PlanContextStore.current?.cacheKey, 'daily_plan:fresh-plan');
  });

  testWidgets(
    'post-mount incompatible shared plan (different language) is not adopted',
    (tester) async {
      final backend = _NoFetchBackend();
      await pumpPlan(tester, backend);
      expect(backend.planRequestCount, 1);
      expect(find.text('새로 생성된 플랜'), findsOneWidget);

      // 마운트 이후 게시된 EN 플랜 — 활성 KO 요청 컨텍스트와 호환되지 않는다.
      PlanContextStore.set(_sharedPlan(language: 'en'));
      await tester.pump();

      expect(find.text('새로 생성된 플랜'), findsOneWidget);
      expect(find.text('공유 플랜 명소'), findsNothing);
      expect(backend.planRequestCount, 1);
    },
  );

  testWidgets(
    'post-mount incompatible shared plan (different radius) is not adopted',
    (tester) async {
      final backend = _NoFetchBackend();
      await pumpPlan(tester, backend);
      expect(find.text('새로 생성된 플랜'), findsOneWidget);

      PlanContextStore.set(_sharedPlan(radiusM: 5000));
      await tester.pump();

      expect(find.text('새로 생성된 플랜'), findsOneWidget);
      expect(find.text('공유 플랜 명소'), findsNothing);
      expect(backend.planRequestCount, 1);
    },
  );

  testWidgets('post-mount compatible shared plan publish is still adopted', (
    tester,
  ) async {
    final backend = _NoFetchBackend();
    await pumpPlan(tester, backend);
    expect(backend.planRequestCount, 1);
    expect(find.text('새로 생성된 플랜'), findsOneWidget);

    final shared = _sharedPlan();
    PlanContextStore.set(shared);
    await tester.pump();

    expect(find.text('공유 플랜 명소'), findsOneWidget);
    expect(find.text('공유 플랜 식당'), findsOneWidget);
    expect(find.text('새로 생성된 플랜'), findsNothing);
    expect(identical(PlanContextStore.current, shared), isTrue);
    // 채택은 재요청 없이 수용된다.
    expect(backend.planRequestCount, 1);
  });

  testWidgets(
    'incompatible shared plan published during a region reload is not adopted',
    (tester) async {
      final backends = <_ControlledPlanBackend>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PlanPage(
            locationProvider: _FoundLocationProvider(),
            backendFactory: (config) {
              final backend = _ControlledPlanBackend();
              backends.add(backend);
              return backend;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      // backends[0] = initState 사전 생성(사용 안 함), backends[1] = 첫 fetch.
      expect(backends.length, 2);
      backends[1].planCompleter.complete(_envelope(_freshPlan()));
      await tester.pumpAndSettle();
      expect(find.text('새로 생성된 플랜'), findsOneWidget);

      // 지역 전환(수원 → 부산): 리로드가 시작되고 새 요청은 completer 로 대기 중.
      RegionContextStore.set(
        RegionContext.manual(
          const ManualLocationOption(
            id: 'busan',
            provinceId: '26',
            provinceKo: '부산광역시',
            provinceEn: 'Busan',
            labelKo: '부산',
            labelEn: 'Busan',
            lat: 35.1796,
            lng: 129.0756,
          ),
        ),
      );
      await tester.pump();
      expect(backends.length, 3);
      expect(find.byKey(const ValueKey('plan-loading-view')), findsOneWidget);

      // 리로드 진행 중 게시된 '구지역(수원) 중심' 플랜 — 부산 요청 컨텍스트와
      // 호환되지 않으므로 채택되지 않는다(로딩 상태가 그대로 유지된다).
      PlanContextStore.set(_sharedPlan());
      await tester.pump();
      expect(find.byKey(const ValueKey('plan-loading-view')), findsOneWidget);
      expect(find.text('공유 플랜 명소'), findsNothing);

      // 리로드 요청이 완료되면 부산 컨텍스트의 플랜이 정상 렌더링된다.
      backends[2].planCompleter.complete(_envelope(_freshPlan()));
      await tester.pumpAndSettle();
      expect(find.text('새로 생성된 플랜'), findsOneWidget);
      expect(PlanContextStore.current?.cacheKey, 'daily_plan:fresh-plan');
    },
  );

  testWidgets(
    'incompatible shared plan published during a language reload is not adopted',
    (tester) async {
      final backends = <_ControlledPlanBackend>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PlanPage(
            locationProvider: _FoundLocationProvider(),
            backendFactory: (config) {
              final backend = _ControlledPlanBackend();
              backends.add(backend);
              return backend;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      // backends[0] = initState 사전 생성(사용 안 함), backends[1] = 첫 fetch.
      expect(backends.length, 2);
      backends[1].planCompleter.complete(_envelope(_freshPlan()));
      await tester.pumpAndSettle();
      expect(find.text('새로 생성된 플랜'), findsOneWidget);

      // 언어 전환(ko → en): 리로드가 시작되고 새 요청은 completer 로 대기 중.
      OnboardingState.selectLanguage('en');
      await tester.pump();
      expect(backends.length, 3);
      expect(find.byKey(const ValueKey('plan-loading-view')), findsOneWidget);

      // 리로드 진행 중 게시된 KO 플랜 — EN 요청 컨텍스트와 호환되지 않는다.
      PlanContextStore.set(_sharedPlan());
      await tester.pump();
      expect(find.byKey(const ValueKey('plan-loading-view')), findsOneWidget);
      expect(find.text('공유 플랜 명소'), findsNothing);

      // 리로드 완료 → EN 컨텍스트의 새 플랜 렌더링(타일 key 로 검증 — EN 표기는
      // nameEn 폴백 규칙을 따르므로 언어 불변 key 가 안정적이다).
      backends[2].planCompleter.complete(_envelope(_freshPlan()));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('plan-slot-fresh-place')),
        findsOneWidget,
      );
    },
  );
}
