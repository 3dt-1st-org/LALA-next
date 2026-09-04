// §13.5 Plan 탭 5개 상태(loading/loaded/empty/unavailable/error) honest distinct
// 표시 + 접근성(최소 44dp 터치 타겟, Semantics 라벨, 393dp 오버플로 없음) 검증.
// 어떤 상태도 mock/demo 데이터를 쓰지 않으며, API 실패 카피는 빈 상태(no-data)
// 카피와 절대 겹치지 않는다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/state/plan_context_store.dart';
import 'package:lala_next_app/features/plan/presentation/pages/plan_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';

void main() {
  setUp(() {
    RegionContextStore.clear();
    // D-1: 플랜 탭 첫 진입은 공유 플랜을 채택할 수 있으므로 상태별 백엔드 동작을
    // 검증하려면 스토어가 깨끗해야 한다(프로세스 로컬 싱글턴 격리).
    PlanContextStore.clear();
    OnboardingState.selectLanguage('ko');
  });

  // ---- loading ----
  testWidgets('loading shows exactly one preparing card and skeleton, no slots',
      (tester) async {
    await _pumpPlan(tester, backend: _HangingPlanBackend());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(find.byKey(const ValueKey('planner-loading-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-timeline-skeleton')), findsOneWidget);
    // 실제 슬롯/실패 카피가 로딩 중에는 섞이지 않는다.
    expect(find.text('화성행궁 산책 코스'), findsNothing);
    expect(find.textContaining('연결할 수 없어요'), findsNothing);
  });

  // ---- loaded ----
  testWidgets('loaded shows a real timeline and never a skeleton', (tester) async {
    await _pumpPlan(tester, backend: _LoadedPlanBackend());
    await tester.pumpAndSettle();

    expect(find.text('화성행궁 산책 코스'), findsOneWidget);
    // loaded 는 스켈레톤/로딩 카드/빈·실패 카피를 띄우지 않는다.
    expect(find.byKey(const ValueKey('planner-loading-card')), findsNothing);
    expect(find.byKey(const ValueKey('plan-timeline-skeleton')), findsNothing);
    expect(find.text('표시할 일정이 없어요.'), findsNothing);
    expect(find.textContaining('연결할 수 없어요'), findsNothing);
  });

  // ---- empty (no-data; distinct from any failure) ----
  testWidgets('empty shows the no-data message, distinct from failure copy',
      (tester) async {
    await _pumpPlan(tester, backend: _EmptySlotsBackend());
    await tester.pumpAndSettle();

    expect(find.text('표시할 일정이 없어요.'), findsOneWidget);
    expect(find.text('일정 다시 만들기'), findsOneWidget);
    // 빈 상태 카피는 실패 카피와 겹치지 않는다.
    expect(find.textContaining('연결할 수 없어요'), findsNothing);
    expect(find.textContaining('불러오지 못했어요'), findsNothing);
    // 빈 상태는 스켈레톤/로딩 카드를 띄우지 않는다.
    expect(find.byKey(const ValueKey('planner-loading-card')), findsNothing);
    expect(find.byKey(const ValueKey('plan-timeline-skeleton')), findsNothing);
  });

  // ---- unavailable (network/timeout; can't reach the service) ----
  testWidgets('unavailable shows the reachability copy and is not the empty/error copy',
      (tester) async {
    await _pumpPlan(
      tester,
      backend: _ThrowingPlanBackend(
        const LalaApiException(
          code: 'NETWORK_ERROR',
          message: 'unreachable',
          statusCode: 0,
          retryable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plan-unavailable-view')), findsOneWidget);
    expect(find.textContaining('연결할 수 없어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    // unavailable ≠ empty no-data copy.
    expect(find.text('표시할 일정이 없어요.'), findsNothing);
    // unavailable ≠ error copy (서비스가 응답한 오류 문구).
    expect(find.textContaining('불러오지 못했어요'), findsNothing);
    expect(find.byKey(const ValueKey('planner-loading-card')), findsNothing);
    expect(find.byKey(const ValueKey('plan-timeline-skeleton')), findsNothing);
  });

  // ---- error (service responded with an error) ----
  testWidgets('error shows the service-error copy, distinct from empty and unavailable',
      (tester) async {
    await _pumpPlan(
      tester,
      backend: _ThrowingPlanBackend(
        const LalaApiException(
          code: 'HTTP_503',
          message: 'upstream error',
          statusCode: 503,
          retryable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plan-error-view')), findsOneWidget);
    expect(find.textContaining('불러오지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    // error ≠ empty no-data copy.
    expect(find.text('표시할 일정이 없어요.'), findsNothing);
    // error ≠ unavailable copy.
    expect(find.textContaining('연결할 수 없어요'), findsNothing);
  });

  // ---- a11y: Semantics labels present on each terminal state ----
  testWidgets('empty state exposes a Semantics label', (tester) async {
    await _pumpPlan(tester, backend: _EmptySlotsBackend());
    await tester.pumpAndSettle();
    expect(
      _hasSemanticsLabel(tester, containing: '빈 일정'),
      isTrue,
      reason: 'empty state must expose a Semantics label',
    );
  });

  testWidgets('unavailable state exposes a Semantics label', (tester) async {
    await _pumpPlan(
      tester,
      backend: _ThrowingPlanBackend(
        const LalaApiException(
          code: 'REQUEST_TIMEOUT',
          message: 'timed out',
          statusCode: 0,
          retryable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      _hasSemanticsLabel(tester, containing: '서버 연결 불가'),
      isTrue,
      reason: 'unavailable must expose a label',
    );
  });

  testWidgets('error state exposes a Semantics label', (tester) async {
    await _pumpPlan(
      tester,
      backend: _ThrowingPlanBackend(
        const LalaApiException(
          code: 'HTTP_500',
          message: 'server error',
          statusCode: 500,
          retryable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      _hasSemanticsLabel(tester, containing: '불러오기 실패'),
      isTrue,
      reason: 'error must expose a label',
    );
  });

  testWidgets('loading state exposes a Semantics label', (tester) async {
    await _pumpPlan(tester, backend: _HangingPlanBackend());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(
      _hasSemanticsLabel(tester, containing: '일정을 준비하고 있어요'),
      isTrue,
      reason: 'loading state must expose a label',
    );
  });

  // ---- a11y: slot meta Semantics (period, travel time, est. hours, indoor/outdoor) ----
  testWidgets('slot tile aggregates period/travel/est-hours/indoor into Semantics',
      (tester) async {
    await _pumpPlan(tester, backend: _RichSlotBackend());
    await tester.pumpAndSettle();

    expect(_hasSemanticsLabel(tester, containing: '도보 9분'), isTrue);
    expect(_hasSemanticsLabel(tester, containing: '영업 11:00-22:00 (추정)'), isTrue);
    expect(_hasSemanticsLabel(tester, containing: '실내'), isTrue);
    expect(_hasSemanticsLabel(tester, containing: '점심'), isTrue);
  });

  // ---- a11y: minimum 44dp touch targets (regenerate + failure retry) ----
  testWidgets('loaded regenerate button meets the 44dp minimum touch target',
      (tester) async {
    await _pumpPlan(tester, backend: _LoadedPlanBackend());
    await tester.pumpAndSettle();

    final regen = find.byKey(const ValueKey('planner-regenerate'));
    expect(regen, findsOneWidget);
    expect(tester.getSize(regen).height, greaterThanOrEqualTo(44));
  });

  testWidgets('error retry button meets the 44dp minimum touch target',
      (tester) async {
    await _pumpPlan(
      tester,
      backend: _ThrowingPlanBackend(
        const LalaApiException(
          code: 'HTTP_500',
          message: 'server error',
          statusCode: 500,
          retryable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final retry = find.widgetWithText(FilledButton, '다시 시도');
    expect(retry, findsOneWidget);
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(44));
  });

  testWidgets('empty regenerate button meets the 44dp minimum touch target',
      (tester) async {
    await _pumpPlan(tester, backend: _EmptySlotsBackend());
    await tester.pumpAndSettle();

    final regen = find.widgetWithText(OutlinedButton, '일정 다시 만들기');
    expect(regen, findsOneWidget);
    expect(tester.getSize(regen).height, greaterThanOrEqualTo(44));
  });

  // ---- a11y: slot tile meets 44dp minimum height + no overflow at 393dp ----
  testWidgets('slot tile meets 44dp min height and does not overflow at 393dp',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpPlan(tester, backend: _RichSlotBackend());
    await tester.pumpAndSettle();

    // RenderFlex overflow assertion would throw → takeException picks it up.
    expect(tester.takeException(), isNull);
    final tile = find.byKey(const ValueKey('planner-slot-rich-slot'));
    expect(tile, findsOneWidget);
    expect(tester.getSize(tile).height, greaterThanOrEqualTo(44));
  });

  // ---- a11y: failure/empty states do not overflow at 393dp on a tall message ----
  testWidgets('unavailable and empty states do not overflow at 393dp', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpPlan(
      tester,
      backend: _ThrowingPlanBackend(
        const LalaApiException(
          code: 'NETWORK_ERROR',
          message: 'unreachable',
          statusCode: 0,
          retryable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _pumpPlan(tester, backend: _EmptySlotsBackend());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  tearDown(() {
    RegionContextStore.clear();
    PlanContextStore.clear();
    OnboardingState.reset();
  });
}

// ---- helpers ----

Future<void> _pumpPlan(WidgetTester tester, {required LalaBackend backend}) {
  return tester.pumpWidget(
    MaterialApp(
      home: PlanPage(
        locationProvider: _FoundLocationProvider(),
        backendFactory: (config) => backend,
      ),
    ),
  );
}

/// 시맨틱 트리 전체에서 [containing] 부분문자열을 label 로 갖는 노드가 하나라도
/// 있는지 재귀 탐색. Semantics 라벨 존재/내용 검증에 사용.
bool _hasSemanticsLabel(WidgetTester tester, {required String containing}) {
  final root = tester.getSemantics(find.byType(MaterialApp));
  bool deep(SemanticsNode node) {
    if (node.label.contains(containing)) {
      return true;
    }
    var found = false;
    node.visitChildren((child) {
      if (!found) {
        found = deep(child);
      }
      return !found; // continue until found
    });
    return found;
  }

  return deep(root);
}

class _FoundLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() async =>
      const LalaLocationResult.found(LalaLocation(lat: 37.2636, lng: 127.0286));
}

/// 일정 응답을 영원히 대기(hanging) — loading 상태 고정용. mock 데이터 없음.
class _HangingPlanBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({String? selectedPlaceId, LalaPlanPreferenceContext? preferenceContext}) =>
      Completer<LalaEnvelope<LalaDailyPlan>>().future;

  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() =>
      Completer<LalaEnvelope<LalaIntervention>>().future;

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: ${invocation.memberName}');
}

class _LoadedPlanBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({String? selectedPlaceId, LalaPlanPreferenceContext? preferenceContext}) async => _envelope(
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
      throw UnimplementedError('not used: ${invocation.memberName}');
}

/// period/이동시간/추정시간/실내 를 모두 가진 슬롯(시맨틱 집계 검증용).
class _RichSlotBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({String? selectedPlaceId, LalaPlanPreferenceContext? preferenceContext}) async => _envelope(
        LalaDailyPlan(
          language: 'ko',
          center: const LalaCoordinate(lat: 37.2636, lng: 127.0286),
          radiusM: 3000,
          weather: _weather(),
          slots: <LalaPlanSlot>[
            LalaPlanSlot(
              period: 'lunch',
              title: '점심',
              place: const LalaPlace(
                placeId: 'rich-slot',
                name: '그레이브릭스커피 고덕점',
                category: 'restaurant',
                lat: 37.5,
                lng: 127.0,
                address: '서울',
                distanceM: 100,
                source: 'db',
              ),
              travelTimeFromPreviousMinutes: 9,
              estimatedOpeningHours: '11:00-22:00',
              indoorOutdoor: 'indoor',
            ),
          ],
          source: 'db',
          requestHash: 'test-plan-rich-hash',
          cacheKey: 'daily_plan:test-rich',
        ),
      );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: ${invocation.memberName}');
}

class _EmptySlotsBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({String? selectedPlaceId, LalaPlanPreferenceContext? preferenceContext}) async => _envelope(
        LalaDailyPlan(
          language: 'ko',
          center: const LalaCoordinate(lat: 37.2636, lng: 127.0286),
          radiusM: 3000,
          weather: _weather(),
          slots: const <LalaPlanSlot>[],
          source: 'db',
          requestHash: 'test-plan-empty-hash',
          cacheKey: 'daily_plan:test-empty',
        ),
      );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: ${invocation.memberName}');
}

/// createDailyPlan 이 [failure] 를 throw — unavailable/error 분류 검증용.
class _ThrowingPlanBackend implements LalaBackend {
  _ThrowingPlanBackend(this.failure);

  final Object failure;

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({String? selectedPlaceId, LalaPlanPreferenceContext? preferenceContext}) async {
    throw failure;
  }

  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() async {
    throw failure;
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: ${invocation.memberName}');
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
