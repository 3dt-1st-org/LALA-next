// D-1 회귀(교차 탭 재생성 금지): 플랜 탭 첫 진입은 현재 요청 컨텍스트와 같은
// 활성 플랜이 공유 스토어에 있으면 그 인스턴스를 채택한다 — 재요청/재생성 없음.
// 뷰 전환만으로 슬롯이 뒤섞이던 결함(맵 플랜 vs 플랜 탭 자체 생성)의 회귀 검증.
// 명시적 새로고침(달력/재생성)은 여전히 네트워크 생성을 돈다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/state/plan_context_store.dart';
import 'package:lala_next_app/features/plan/presentation/pages/plan_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';

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

/// createDailyPlan 이 호출되면 실패하는 fake — 채택 경로에서는 절대 불리지 않아야 한다.
class _NoFetchBackend implements LalaBackend {
  int planRequestCount = 0;

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({
    String? selectedPlaceId,
  }) async {
    planRequestCount++;
    return _envelope(
      LalaDailyPlan(
        language: 'ko',
        center: const LalaCoordinate(lat: _lat, lng: _lng),
        radiusM: 3000,
        weather: _weather(),
        slots: [_slot('morning', '오전', 'fresh-place', '새로 생성된 플랜')],
        source: 'db',
        requestHash: 'fresh-plan-hash',
        cacheKey: 'daily_plan:fresh-plan',
      ),
    );
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
}
