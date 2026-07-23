// 모바일 비주얼 계약(Slice E / S6): 일정 '준비 중' 상태 검증.
// - pending: '준비 중' 카드 정확히 한 장 + 타임라인 스켈레톤.
// - 타이머/퍼센트/서버 단계 완료 주장 텍스트가 없어야 한다.
// - 종료 상태(에러) 도달 시 로딩 카드/스켈레톤은 사라진다(loaded 도 동일 분기).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/features/plan/presentation/pages/plan_page.dart';

void main() {
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

      // 에러 도착 → 로딩 카드/스켈레톤 제거, 재시도 노출.
      backend.completeError();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('planner-loading-card')), findsNothing);
      expect(find.byKey(const ValueKey('plan-timeline-skeleton')), findsNothing);
      expect(find.text('재시도'), findsOneWidget);
    },
  );
}

class _FoundLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() async =>
      const LalaLocationResult.found(
        LalaLocation(lat: 37.2636, lng: 127.0286),
      );
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
