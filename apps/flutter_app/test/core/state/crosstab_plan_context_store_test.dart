// Lane 1 (§13.4) — unit tests for PlanContextStore, the cross-tab daily-plan SSOT
// that replaces the map/plan dual fetch. Verifies the reactive surface Lane 2 will
// persist against. LalaDailyPlan has identity equality (no operator ==), so each
// new instance notifies — consumers no-op-skip by comparing against their own hold.
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/state/plan_context_store.dart';

LalaDailyPlan _plan({required String cacheKey}) {
  return LalaDailyPlan(
    language: 'ko',
    center: const LalaCoordinate(lat: 37.2636, lng: 127.0286),
    radiusM: 3000,
    weather: LalaWeather(
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
      forecast: const <LalaForecastItem>[],
      outdoorStatus: 'good',
      force: false,
      source: 'db',
      location: 'Suwon',
      recordTime: '2026-06-18T09:00:00+09:00',
      locationMatch: true,
    ),
    slots: const <LalaPlanSlot>[
      LalaPlanSlot(period: 'morning', title: '화성행궁 산책 코스'),
    ],
    source: 'db',
    // 저엔트로피 테스트 값(detect-secrets 허위 양성 회피; 실제 키/해시 아님).
    requestHash: 'test-plan-request-hash',
    cacheKey: cacheKey,
  );
}

void main() {
  // Process-local singleton: reset before each case so a plan published in one
  // test cannot leak into another tab's state.
  setUp(PlanContextStore.clear);

  group('PlanContextStore', () {
    test('current is null after clear', () {
      expect(PlanContextStore.current, isNull);
    });

    test('set publishes the plan and current reflects it', () {
      final plan = _plan(cacheKey: 'daily_plan:test-a');
      PlanContextStore.set(plan);
      expect(identical(PlanContextStore.current, plan), isTrue);
    });

    test('clear reverts to honest empty (null plan)', () {
      PlanContextStore.set(_plan(cacheKey: 'daily_plan:test-b'));
      PlanContextStore.clear();
      expect(PlanContextStore.current, isNull);
    });

    test('listenable fires on each published plan (identity equality)', () {
      final seen = <LalaDailyPlan?>[];
      PlanContextStore.listenable.addListener(() {
        seen.add(PlanContextStore.current);
      });

      final a = _plan(cacheKey: 'daily_plan:test-c');
      final b = _plan(cacheKey: 'daily_plan:test-d');
      PlanContextStore.set(a);
      PlanContextStore.set(b);

      expect(seen.length, 2);
      expect(identical(seen[0], a), isTrue);
      expect(identical(seen[1], b), isTrue);
    });

    test('a consumer no-op-skips its own publish (same instance)', () {
      LalaDailyPlan? held;
      var rebuilds = 0;
      PlanContextStore.listenable.addListener(() {
        final next = PlanContextStore.current;
        if (next == held) {
          return; // mirror the plan-page / map-tab listener skip
        }
        held = next;
        rebuilds++;
      });

      final plan = _plan(cacheKey: 'daily_plan:test-e');
      PlanContextStore.set(plan); // a tab publishes its own fetch result
      expect(rebuilds, 1);

      // Re-publishing the SAME instance (no real change) still notifies (identity
      // equality is identity), but the consumer skips because it already holds it.
      PlanContextStore.set(plan);
      expect(rebuilds, 1);
    });
  });
}
