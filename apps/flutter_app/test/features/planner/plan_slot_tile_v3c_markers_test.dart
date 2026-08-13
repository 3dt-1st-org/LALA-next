// V3-C (D2/D3/D4) 슬롯 위젯 마커 렌더 + 접근성 + 단일언어 + honest-empty 검증.
// 모델은 직접 생성(라이브 API 없음). null 필드 처리가 honest-empty의 핵심이다.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/planner/widgets/plan_slot_tile.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

LalaPlace _place({
  String id = 'p1',
  String name = '카페',
  String category = 'restaurant',
}) {
  return LalaPlace(
    placeId: id,
    name: name,
    category: category,
    lat: 37.5,
    lng: 127.0,
    address: '서울',
    distanceM: 100,
    source: 'db',
  );
}

/// 시맨틱 트리를 재귀 탐색하여 [parts] 의 모든 부분문자열을 포함하는 단일 노드가
/// 있는지 확인. tile 루트 Semantics(container:true, label=aggregated) 한 노드에서
/// 세 마커(운영상태/예보/대기질)가 모두 읽히는지를 검증한다(C5 — 색상 단독 신호 금지).
bool _hasSemanticsNodeWithAll(WidgetTester tester, List<String> parts) {
  final root = tester.getSemantics(find.byType(MaterialApp));
  bool deep(SemanticsNode node) {
    if (parts.every((p) => node.label.contains(p))) {
      return true;
    }
    var found = false;
    node.visitChildren((child) {
      if (!found) {
        found = deep(child);
      }
      return !found;
    });
    return found;
  }

  return deep(root);
}

void main() {
  group('D4 closureState badge (C1)', () {
    testWidgets('open → teal 영업중/Open icon+text (KO)', (tester) async {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        closureState: 'open',
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );
      expect(find.text('영업중'), findsOneWidget);
      // triple signal: icon + text (not color-only).
      final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle_outline));
      expect(icon.color, const Color(0xFF0F766E)); // teal token
    });

    testWidgets('closed → red 영업종료/Closed (EN)', (tester) async {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: 'Lunch',
        place: _place(),
        closureState: 'closed',
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'en', onSelectPlace: (_) {})),
      );
      expect(find.text('Closed'), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(Icons.cancel_outlined));
      expect(icon.color, const Color(0xFFC53030)); // red token
    });

    testWidgets('unknown → slate 미확인/Unknown', (tester) async {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        closureState: 'unknown',
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );
      expect(find.text('미확인'), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(Icons.help_outline));
      expect(icon.color, const Color(0xFF64748B)); // slate token
    });

    testWidgets('null → 미확인/Unknown (honest-empty, never fabricated open)',
        (tester) async {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        closureState: null,
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );
      expect(find.text('미확인'), findsOneWidget);
      // null must never fabricate an authoritative "open".
      expect(find.text('영업중'), findsNothing);
    });
  });

  group('D2 forecastWindow (C2)', () {
    testWidgets('present → renders "time · temp"', (tester) async {
      final slot = LalaPlanSlot(
        period: 'morning',
        title: '오전',
        place: _place(),
        forecastWindow: const LalaForecastItem(
          time: '11:00',
          temp: '12°',
          icon: 'clear',
        ),
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );
      expect(find.text('11:00 · 12°'), findsOneWidget);
    });

    testWidgets('null → hidden, no placeholder/spinner', (tester) async {
      final slot = LalaPlanSlot(
        period: 'morning',
        title: '오전',
        place: _place(),
        forecastWindow: null,
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );
      expect(find.textContaining('·'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('D3 airQualityBad marker (C3)', () {
    testWidgets('true && outdoor → shows AQ marker (KO)', (tester) async {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        indoorOutdoor: 'outdoor',
        airQualityBad: true,
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );
      expect(find.text('외부 대기질 나쁨'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('true && indoor → hidden (outdoor-only)', (tester) async {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        indoorOutdoor: 'indoor',
        airQualityBad: true,
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );
      expect(find.textContaining('대기질'), findsNothing);
    });

    testWidgets('null → hidden (never fabricated bad)', (tester) async {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        indoorOutdoor: 'outdoor',
        airQualityBad: null,
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );
      expect(find.textContaining('대기질'), findsNothing);
    });

    testWidgets('false → hidden', (tester) async {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        indoorOutdoor: 'outdoor',
        airQualityBad: false,
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );
      expect(find.textContaining('대기질'), findsNothing);
    });
  });

  group('C5 semantics (not color-only)', () {
    testWidgets('aggregated semantics node includes closure + forecast + AQ',
        (tester) async {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        indoorOutdoor: 'outdoor',
        closureState: 'open',
        forecastWindow:
            const LalaForecastItem(time: '11:00', temp: '12°', icon: 'clear'),
        airQualityBad: true,
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );
      // One semantics node (the tile root, container:true) carries all three.
      expect(
        _hasSemanticsNodeWithAll(tester, ['영업중', '11:00 · 12°', '외부 대기질 나쁨']),
        isTrue,
      );
    });
  });

  group('C6 single-language (no mixed-language label)', () {
    testWidgets('KO renders all markers in Korean, no English leak',
        (tester) async {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        indoorOutdoor: 'outdoor',
        closureState: 'closed',
        forecastWindow:
            const LalaForecastItem(time: '11:00', temp: '12°', icon: 'clear'),
        airQualityBad: true,
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );
      expect(find.text('영업종료'), findsOneWidget);
      expect(find.text('외부 대기질 나쁨'), findsOneWidget);
      expect(find.text('Open'), findsNothing);
      expect(find.text('Closed'), findsNothing);
      expect(find.text('Outdoor air quality poor'), findsNothing);
    });

    testWidgets('EN renders all markers in English, no Korean leak',
        (tester) async {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: 'Lunch',
        place: _place(name: 'Cafe'),
        indoorOutdoor: 'outdoor',
        closureState: 'closed',
        forecastWindow:
            const LalaForecastItem(time: '11:00', temp: '12°', icon: 'clear'),
        airQualityBad: true,
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'en', onSelectPlace: (_) {})),
      );
      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('Outdoor air quality poor'), findsOneWidget);
      expect(find.text('영업종료'), findsNothing);
      expect(find.text('외부 대기질 나쁨'), findsNothing);
    });
  });

  group('C7 honesty marker preserved', () {
    testWidgets('estimated hours still show (추정)/(est.) with V3 markers',
        (tester) async {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        closureState: 'open',
        estimatedOpeningHours: '11:00-22:00',
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );
      expect(find.textContaining('(추정)'), findsOneWidget);
      expect(find.text('영업중'), findsOneWidget);
    });
  });

  group('C8 existing fields unchanged', () {
    testWidgets('weatherHint / indoor-outdoor / travel still render',
        (tester) async {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        weatherHint: '맑음',
        indoorOutdoor: 'outdoor',
        travelTimeFromPreviousMinutes: 8,
        closureState: 'open',
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );
      expect(find.text('맑음'), findsOneWidget); // weatherHint
      expect(find.text('야외'), findsOneWidget); // indoor/outdoor
      expect(find.textContaining('도보 8분'), findsOneWidget); // travel
      expect(find.text('영업중'), findsOneWidget); // new D4 alongside
    });
  });

  group('C4 overflow-safety + honest-empty', () {
    testWidgets('no overflow at 393dp with all V3-C markers present',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final slot = LalaPlanSlot(
        period: 'afternoon',
        title: '그레이브릭스커피 고덕점',
        place: _place(name: '그레이브릭스커피 고덕점'),
        weatherHint: '오후 한때 소나기',
        indoorOutdoor: 'outdoor',
        travelTimeFromPreviousMinutes: 123,
        estimatedOpeningHours: '07:30-23:30',
        closureState: 'closed',
        forecastWindow: const LalaForecastItem(
          time: '14:00',
          temp: '31°',
          icon: 'rain',
        ),
        airQualityBad: true,
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull); // no RenderFlex overflow
      expect(find.text('영업종료'), findsOneWidget);
      expect(find.text('14:00 · 31°'), findsOneWidget);
      expect(find.text('외부 대기질 나쁨'), findsOneWidget);
    });

    testWidgets('all V3 null → unknown badge, no forecast, no AQ (honest-empty)',
        (tester) async {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        // All V3 additive fields null (PLAN_FULL_SLOTS off path).
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );
      expect(find.text('미확인'), findsOneWidget); // null → unknown honestly
      expect(find.textContaining('·'), findsNothing); // no forecast
      expect(find.textContaining('대기질'), findsNothing); // no AQ
    });
  });
}
