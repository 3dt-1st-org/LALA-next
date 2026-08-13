// 모바일 비주얼 계약(Slice E / S6): 일정 '준비 중' 상태 검증.
// - pending: '준비 중' 카드 정확히 한 장 + 타임라인 스켈레톤.
// - 타이머/퍼센트/서버 단계 완료 주장 텍스트가 없어야 한다.
// - 종료 상태(에러) 도달 시 로딩 카드/스켈레톤은 사라진다(loaded 도 동일 분기).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/features/plan/presentation/pages/plan_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/manual_location_options.dart';

void main() {
  // RegionContextStore is a process-local singleton; reset it before each test
  // so a manual/current choice from another test cannot leak into this tab's
  // seed coordinates.
  setUp(() {
    RegionContextStore.clear();
    OnboardingState.selectLanguage('ko');
  });

  testWidgets(
    'plan pending shows one generating card and a skeleton timeline, then clears',
    (tester) async {
      final backend = _PendingPlanBackend();
      await tester.pumpWidget(
        MaterialApp(
          home: PlanPage(
            locationProvider: _FoundLocationProvider(),
            backendFactory: (config) => backend,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      // '준비 중' 카드는 정확히 한 장(중복 금지).
      expect(
        find.byKey(const ValueKey('planner-loading-card')),
        findsOneWidget,
      );
      // 타임라인 스켈레톤 존재.
      expect(
        find.byKey(const ValueKey('plan-timeline-skeleton')),
        findsOneWidget,
      );
      // 타이머/퍼센트/가짜 완료 주장이 없어야 한다.
      expect(find.textContaining('%'), findsNothing);
      expect(find.text('일정을 준비하고 있어요'), findsOneWidget);

      // 에러 도착 → 로딩 카드/스켈레톤 제거, 재시도 노출(§13.5 honest error state).
      backend.completeError();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('planner-loading-card')), findsNothing);
      expect(
        find.byKey(const ValueKey('plan-timeline-skeleton')),
        findsNothing,
      );
      expect(find.text('다시 시도'), findsOneWidget);
    },
  );

  testWidgets(
    'plan loaded shows real slots and readable weather with no loading card',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlanPage(
            locationProvider: _FoundLocationProvider(),
            backendFactory: (config) => _LoadedPlanBackend(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // loaded: 로딩 카드/타임라인 스켈레톤 없음.
      expect(find.byKey(const ValueKey('planner-loading-card')), findsNothing);
      expect(
        find.byKey(const ValueKey('plan-timeline-skeleton')),
        findsNothing,
      );
      // 실제 슬롯 제목(서버 순서 그대로).
      expect(find.text('화성행궁 산책 코스'), findsOneWidget);
      // 읽을 수 있는 날씨/먼지(말줄임/중복 라벨 아님).
      expect(find.textContaining('14°C'), findsWidgets);
      expect(find.text('PM10 31 보통'), findsOneWidget);
    },
  );

  testWidgets(
    'store-driven manual region reloads the backend without re-requesting location',
    (tester) async {
      final configs = <LalaAppConfig>[];
      final locationProvider = _CountingLocationProvider(
        const LalaLocationResult.unavailable(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PlanPage(
            locationProvider: locationProvider,
            // _load/_reloadFromStore 모두 백엔드를 재생성하므로 호출될 때마다
            // 사용된 config 를 기록한다.
            backendFactory: (config) {
              configs.add(config);
              return _LoadedPlanBackend();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 초기 로드는 기기 위치를 정확히 한 번 요청한다(기존 동작).
      expect(locationProvider.requests, 1);

      // 온보딩/다른 탭에서 수동 지역이 공유 store 에 게시되면 리스너가 발동한다.
      RegionContextStore.set(RegionContext.manual(_busanOption()));
      await tester.pumpAndSettle();

      // 수동 선택이 발생한 리로드는 기기 위치를 다시 요청하지 않는다.
      expect(locationProvider.requests, 1);
      // 가장 마지막 백엔드는 수동 선택의 좌표로 구성되었다.
      expect(configs.last.lat, 35.16);
      expect(configs.last.lng, 129.16);
    },
  );

  testWidgets(
    'a manual region retained from onboarding is not overwritten by the initial location request',
    (tester) async {
      // 온보딩이 수동 선택을 store 에 남긴 채 탭이 마운트되는 상황.
      RegionContextStore.set(RegionContext.manual(_busanOption()));
      final configs = <LalaAppConfig>[];
      // found provider(서울 인근) — 이 결과가 수동 선택을 덮어쓰면 안 된다.
      final locationProvider = _CountingLocationProvider(
        const LalaLocationResult.found(
          LalaLocation(lat: 37.2636, lng: 127.0286),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PlanPage(
            locationProvider: locationProvider,
            backendFactory: (config) {
              configs.add(config);
              return _LoadedPlanBackend();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Why: with a real context already in the store, the initial _load() must
      // NOT request device location at all, so the deliberate manual choice can't
      // be clobbered by a later geolocation fix.
      expect(locationProvider.requests, 0);
      expect(configs.last.lat, 35.16);
      expect(configs.last.lng, 129.16);
    },
  );

  // ---- P6G: Plan empty state ("make a plan" CTA) ----
  // honest empty branch(dailyPlan == null || visibleSlots.isEmpty) 검증.
  // dailyPlan == null 은 로드 실패(ERROR) 상태로 별도 분기이므로, 여기서는
  // visibleSlots 가 비는 도달 가능한 두 경로(빈 slots / 필터링된 placeholder
  // slot)로 empty UI 가 독점 표시되는지 확인한다.

  testWidgets(
    'plan with no slots shows the empty message and regenerate action',
    (tester) async {
      final backend = _EmptySlotsBackend();
      await tester.pumpWidget(
        MaterialApp(
          home: PlanPage(
            locationProvider: _FoundLocationProvider(),
            backendFactory: (config) => backend,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // empty visibleSlots → honest empty 안내문 + regenerate 버튼.
      expect(find.text('표시할 일정이 없어요.'), findsOneWidget);
      expect(find.text('일정 다시 만들기'), findsOneWidget);
      // 로딩 카드/스켈레톤과 중복 표시 없음(empty 분기 독점).
      expect(find.byKey(const ValueKey('planner-loading-card')), findsNothing);
      expect(
        find.byKey(const ValueKey('plan-timeline-skeleton')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'plan whose only slot is a hidden preparing placeholder shows the empty state',
    (tester) async {
      // slot 은 존재하지만 hasVisiblePlanSlot 로 필터링되어 visibleSlots 가 비는 경로.
      await tester.pumpWidget(
        MaterialApp(
          home: PlanPage(
            locationProvider: _FoundLocationProvider(),
            backendFactory: (config) => _HiddenSlotsBackend(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('표시할 일정이 없어요.'), findsOneWidget);
      expect(find.text('일정 다시 만들기'), findsOneWidget);
    },
  );

  testWidgets('tapping the regenerate action reloads the plan exactly once', (
    tester,
  ) async {
    final backend = _EmptySlotsBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: PlanPage(
          locationProvider: _FoundLocationProvider(),
          backendFactory: (config) => backend,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 초기 로드로 createDailyPlan 이 1회 호출되었다.
    expect(backend.planRequests, 1);

    await tester.tap(find.widgetWithText(OutlinedButton, '일정 다시 만들기'));
    await tester.pumpAndSettle();

    // onRegenerate(_load) 가 정확히 한 번 더 실행되었다(총 2회).
    expect(backend.planRequests, 2);
  });

  testWidgets(
    'english config shows the exclusive English empty copy and action',
    (tester) async {
      OnboardingState.selectLanguage('en');
      await tester.pumpWidget(
        MaterialApp(
          home: PlanPage(
            initialConfig: const LalaAppConfig(
              baseUri: 'http://test',
              lang: 'en',
            ),
            locationProvider: _FoundLocationProvider(),
            backendFactory: (config) => _EmptySlotsBackend(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No plan slots to show.'), findsOneWidget);
      expect(find.text('Regenerate plan'), findsOneWidget);
      // KO·EN 배타: 한국어 카피가 섞이지 않는다.
      expect(find.text('표시할 일정이 없어요.'), findsNothing);
      expect(find.text('일정 다시 만들기'), findsNothing);
    },
  );

  testWidgets('selected language updates Plan immediately and reloads in EN', (
    tester,
  ) async {
    RegionContextStore.set(RegionContext.manual(_busanOption()));
    final configs = <LalaAppConfig>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PlanPage(
          locationProvider: _CountingLocationProvider(
            const LalaLocationResult.unavailable(),
          ),
          backendFactory: (config) {
            configs.add(config);
            return _LoadedPlanBackend();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('오늘 일정'), findsOneWidget);

    OnboardingState.selectLanguage('en');
    await tester.pumpAndSettle();

    expect(find.text('Today\'s Plan'), findsOneWidget);
    expect(find.text('오늘 일정'), findsNothing);
    expect(configs.last.lang, 'en');
  });

  tearDown(() {
    RegionContextStore.clear();
    OnboardingState.reset();
  });
}

class _FoundLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() async =>
      const LalaLocationResult.found(LalaLocation(lat: 37.2636, lng: 127.0286));
}

/// 일정/개입 조회를 Completer 로 지연시키는 테스트용 백엔드.
class _PendingPlanBackend implements LalaBackend {
  final Completer<LalaEnvelope<LalaDailyPlan>> _planCompleter =
      Completer<LalaEnvelope<LalaDailyPlan>>();
  final Completer<LalaEnvelope<LalaIntervention>> _interventionCompleter =
      Completer<LalaEnvelope<LalaIntervention>>();

  void completeError() {
    _planCompleter.completeError(StateError('plan backend unavailable'));
    _interventionCompleter.completeError(
      StateError('intervention backend unavailable'),
    );
  }

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() =>
      _planCompleter.future;

  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() =>
      _interventionCompleter.future;

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used in plan: ${invocation.memberName}');
}

/// 실제 일정(슬롯 + 날씨)을 반환하는 테스트용 백엔드.
class _LoadedPlanBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() async => _envelope(
    LalaDailyPlan(
      language: 'ko',
      center: const LalaCoordinate(lat: 37.2636, lng: 127.0286),
      radiusM: 3000,
      weather: _weather(),
      slots: const <LalaPlanSlot>[
        LalaPlanSlot(period: 'morning', title: '화성행궁 산책 코스'),
      ],
      source: 'db',
      // 저엔트로피 테스트 값(detect-secrets 허위 양성 회피; 실제 키/해시 아님).
      requestHash: 'test-plan-request-hash',
      cacheKey: 'daily_plan:test-plan',
    ),
  );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used in plan: ${invocation.memberName}');
}

/// 표시할 슬롯이 없는(빈 slots) 테스트용 백엔드. createDailyPlan 호출 수를 센다
/// (regenerate 액션이 정확히 한 번 더 로드하는지 검증용).
class _EmptySlotsBackend implements LalaBackend {
  int planRequests = 0;

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() async {
    planRequests += 1;
    return _envelope(
      LalaDailyPlan(
        language: 'ko',
        center: const LalaCoordinate(lat: 37.2636, lng: 127.0286),
        radiusM: 3000,
        weather: _weather(),
        slots: const <LalaPlanSlot>[],
        source: 'db',
        // 저엔트로피 테스트 값(허위 양성 회피; 실제 키/해시 아님).
        requestHash: 'test-plan-empty-hash',
        cacheKey: 'daily_plan:test-empty',
      ),
    );
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used in plan: ${invocation.memberName}');
}

/// 표시 가능한 슬롯이 없는(preparing placeholder 만 → 필터링됨) 테스트용 백엔드.
class _HiddenSlotsBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() async => _envelope(
    LalaDailyPlan(
      language: 'ko',
      center: const LalaCoordinate(lat: 37.2636, lng: 127.0286),
      radiusM: 3000,
      weather: _weather(),
      slots: const <LalaPlanSlot>[
        LalaPlanSlot(period: 'afternoon', title: '일정 준비 중'),
      ],
      source: 'db',
      requestHash: 'test-plan-hidden-hash',
      cacheKey: 'daily_plan:test-hidden',
    ),
  );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used in plan: ${invocation.memberName}');
}

LalaWeather _weather() {
  return LalaWeather(
    lat: 37.2636,
    lng: 127.0286,
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
    forecast: const <LalaForecastItem>[
      LalaForecastItem(time: '15:00', temp: '22C', icon: 'partly-cloudy'),
    ],
    outdoorStatus: 'good',
    force: false,
    source: 'db',
    location: 'Suwon',
    recordTime: '2026-06-18T09:00:00+09:00',
    locationMatch: true,
  );
}

LalaEnvelope<T> _envelope<T>(T data) {
  return LalaEnvelope<T>(
    ok: true,
    data: data,
    meta: const <String, dynamic>{'request_id': 'test-request-id'},
    error: null,
    statusCode: 200,
    requestId: 'test-request-id',
  );
}

/// Counts how many times the tab asked for device location. Used to prove a
/// store-driven reload does NOT re-request location.
class _CountingLocationProvider implements LalaLocationProvider {
  _CountingLocationProvider(this._result);

  final LalaLocationResult _result;
  int requests = 0;

  @override
  Future<LalaLocationResult> requestCurrentLocation() async {
    requests += 1;
    return _result;
  }
}

ManualLocationOption _busanOption() {
  return const ManualLocationOption(
    id: 'busan-haeundae',
    provinceId: 'busan',
    provinceKo: '부산광역시',
    provinceEn: 'Busan',
    labelKo: '해운대구',
    labelEn: 'Haeundae-gu',
    lat: 35.16,
    lng: 129.16,
  );
}
