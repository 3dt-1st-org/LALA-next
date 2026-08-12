import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/planner/widgets/plan_slot_tile.dart';
import 'package:lala_next_app/features/planner/planner_helpers.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

LalaPlace _place({String id = 'p1', String name = '카페', String category = 'restaurant'}) {
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

void main() {
  group('planSlotTravelTimeLabel', () {
    test('KO formats "도보 N분" when present', () {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        travelTimeFromPreviousMinutes: 7,
      );
      expect(planSlotTravelTimeLabel(slot, 'ko'), '도보 7분');
    });

    test('EN formats "N min walk" when present', () {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: 'Lunch',
        place: _place(),
        travelTimeFromPreviousMinutes: 12,
      );
      expect(planSlotTravelTimeLabel(slot, 'en'), '12 min walk');
    });

    test('returns null when travel time is null (first slot)', () {
      final slot = LalaPlanSlot(
        period: 'morning',
        title: '오전',
        place: _place(),
        travelTimeFromPreviousMinutes: null,
      );
      expect(planSlotTravelTimeLabel(slot, 'ko'), isNull);
    });
  });

  group('planSlotEstimatedHoursLabel', () {
    test('KO shows hours WITH (추정) marker, never authoritative', () {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        estimatedOpeningHours: '11:00-22:00',
      );
      final label = planSlotEstimatedHoursLabel(slot, 'ko')!;
      expect(label, contains('11:00-22:00'));
      expect(label, contains('(추정)'));
      expect(label.startsWith('영업 '), isTrue);
    });

    test('EN shows hours WITH (est.) marker, never authoritative', () {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: 'Lunch',
        place: _place(),
        estimatedOpeningHours: '11:00-22:00',
      );
      final label = planSlotEstimatedHoursLabel(slot, 'en')!;
      expect(label, contains('11:00-22:00'));
      expect(label, contains('(est.)'));
      expect(label.startsWith('Open '), isTrue);
    });

    test('returns null when hours absent', () {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        estimatedOpeningHours: null,
      );
      expect(planSlotEstimatedHoursLabel(slot, 'ko'), isNull);
    });

    test('returns null for blank/whitespace hours', () {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        estimatedOpeningHours: '   ',
      );
      expect(planSlotEstimatedHoursLabel(slot, 'ko'), isNull);
    });

    test('does not render opening_hours_valid as authoritative when null', () {
      // openingHoursValid null must not produce an authoritative label;
      // the only hours line is the estimated one with its marker.
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        estimatedOpeningHours: '09:00-18:00',
        openingHoursValid: null,
      );
      final label = planSlotEstimatedHoursLabel(slot, 'ko')!;
      expect(label, contains('(추정)'));
    });
  });

  group('PlanSlotTile meta rendering', () {
    testWidgets('shows travel time and estimated hours when present (KO)',
        (tester) async {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(),
        travelTimeFromPreviousMinutes: 9,
        estimatedOpeningHours: '11:00-22:00',
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );

      expect(find.text('도보 9분'), findsOneWidget);
      expect(find.text('영업 11:00-22:00 (추정)'), findsOneWidget);
      // No English leaks into KO mode.
      expect(find.text('9 min walk'), findsNothing);
      expect(find.textContaining('(est.)'), findsNothing);
    });

    testWidgets('shows EN strings and no Korean leak (EN)', (tester) async {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: 'Lunch',
        place: _place(name: 'Cafe'),
        travelTimeFromPreviousMinutes: 15,
        estimatedOpeningHours: '11:00-22:00',
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'en', onSelectPlace: (_) {})),
      );

      expect(find.text('15 min walk'), findsOneWidget);
      expect(find.text('Open 11:00-22:00 (est.)'), findsOneWidget);
      expect(find.textContaining('도보'), findsNothing);
      expect(find.textContaining('(추정)'), findsNothing);
    });

    testWidgets('hides travel time when null (first slot) but shows hours',
        (tester) async {
      final slot = LalaPlanSlot(
        period: 'morning',
        title: '오전',
        place: _place(),
        travelTimeFromPreviousMinutes: null, // first slot
        estimatedOpeningHours: '09:00-18:00',
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );

      expect(find.textContaining('도보'), findsNothing);
      expect(find.text('영업 09:00-18:00 (추정)'), findsOneWidget);
    });

    testWidgets('hides both meta lines when both null', (tester) async {
      final slot = LalaPlanSlot(
        period: 'morning',
        title: '오전',
        place: _place(),
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );

      expect(find.textContaining('도보'), findsNothing);
      expect(find.textContaining('영업'), findsNothing);
    });

    testWidgets('no overflow at 393dp width with both meta chips', (tester) async {
      // iPhone 17 Pro logical width is 393.
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: '점심',
        place: _place(name: '그레이브릭스커피 고덕점'),
        travelTimeFromPreviousMinutes: 123,
        estimatedOpeningHours: '07:30-23:30',
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );
      // A Flex overflow assertion would fail the test; just pumping+settling
      // without throwing confirms no RenderFlex overflow at 393dp.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('도보 123분'), findsOneWidget);
      expect(find.textContaining('07:30-23:30'), findsOneWidget);
    });
  });
}
