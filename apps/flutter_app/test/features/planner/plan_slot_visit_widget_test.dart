// V5-B VISIT + SPEND widget tests:
//  - B4: tapping the visit badge flips planned ↔ visited and the state persists
//    in SlotVisitStore across a rebuild.
//  - B5: a slot with no estimate renders the honest-unavailable band, and a known
//    category renders the estimate band with the (예산 구간) marker.
//  - Backward-compat: a PlanSlotTile built without V5-B params renders the legacy
//    shape (no visit/spend rows), proving the existing golden is unbroken.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/state/slot_visit_store.dart';
import 'package:lala_next_app/features/planner/spend_band_helpers.dart';
import 'package:lala_next_app/features/planner/widgets/plan_slot_tile.dart';

const String _date = '2026-08-14';
const String _period = 'morning';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

LalaPlace _place({String category = 'restaurant'}) => LalaPlace(
      placeId: 'p1',
      name: '카페',
      category: category,
      lat: 37.5,
      lng: 127.0,
      address: '서울',
      distanceM: 100,
      source: 'db',
    );

LalaPlanSlot _slot({String? category = 'restaurant'}) => LalaPlanSlot(
      period: _period,
      title: '오전',
      place: category == null ? null : _place(category: category),
    );

void main() {
  setUp(() {
    SlotVisitStore.clear();
  });

  tearDown(() {
    SlotVisitStore.clear();
  });

  group('B4 VISIT check-in widget', () {
    testWidgets('tap flips planned → visited and persists in SlotVisitStore',
        (tester) async {
      await tester.pumpWidget(_wrap(
        PlanSlotTile(
          slot: _slot(),
          language: 'ko',
          onSelectPlace: (_) {},
          visitStatus: SlotVisitStore.statusFor(_date, _period),
          onToggleVisit: () => SlotVisitStore.toggle(_date, _period),
        ),
      ));

      // Initially planned.
      expect(find.text('예정'), findsOneWidget);
      expect(SlotVisitStore.statusFor(_date, _period), 'planned');

      // Tap the badge.
      await tester.tap(find.text('예정'));
      await tester.pump();

      // The store flipped; rebuild with the new status to simulate plan_page.
      await tester.pumpWidget(_wrap(
        PlanSlotTile(
          slot: _slot(),
          language: 'ko',
          onSelectPlace: (_) {},
          visitStatus: SlotVisitStore.statusFor(_date, _period),
          onToggleVisit: () => SlotVisitStore.toggle(_date, _period),
        ),
      ));
      await tester.pumpAndSettle();

      expect(SlotVisitStore.statusFor(_date, _period), 'visited');
      expect(find.text('방문함'), findsOneWidget);
    });

    testWidgets('tap visited → back to planned', (tester) async {
      SlotVisitStore.toggle(_date, _period); // seed visited

      Future<void> buildTile() async {
        await tester.pumpWidget(_wrap(
          PlanSlotTile(
            slot: _slot(),
            language: 'ko',
            onSelectPlace: (_) {},
            visitStatus: SlotVisitStore.statusFor(_date, _period),
            onToggleVisit: () => SlotVisitStore.toggle(_date, _period),
          ),
        ));
        await tester.pumpAndSettle();
      }

      await buildTile();
      expect(find.text('방문함'), findsOneWidget);

      await tester.tap(find.text('방문함'));
      await buildTile();

      expect(SlotVisitStore.statusFor(_date, _period), 'planned');
      expect(find.text('예정'), findsOneWidget);
    });
  });

  group('B5 SPEND band widget', () {
    testWidgets('known category renders the estimate band with marker',
        (tester) async {
      final band = spendBandFor(_slot(category: 'restaurant'), 'ko');
      await tester.pumpWidget(_wrap(
        PlanSlotTile(
          slot: _slot(),
          language: 'ko',
          onSelectPlace: (_) {},
          visitStatus: 'planned',
          onToggleVisit: () {},
          spendBand: band,
          spendUnavailable: band == null,
        ),
      ));
      expect(find.textContaining('예산 구간'), findsWidgets);
      expect(find.textContaining('맛집'), findsOneWidget);
    });

    testWidgets('B5: absent estimate renders honest-unavailable band (no number)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        PlanSlotTile(
          slot: _slot(category: 'mystery_cat'),
          language: 'ko',
          onSelectPlace: (_) {},
          visitStatus: 'planned',
          onToggleVisit: () {},
          spendBand: null,
          spendUnavailable: true,
        ),
      ));
      expect(find.text('예산 구간 미확정'), findsOneWidget);
    });
  });

  group('backward-compat (B9)', () {
    testWidgets('PlanSlotTile without V5-B params renders the legacy shape',
        (tester) async {
      await tester.pumpWidget(_wrap(
        PlanSlotTile(
          slot: _slot(),
          language: 'ko',
          onSelectPlace: (_) {},
        ),
      ));
      // No visit/spend rows when params are omitted.
      expect(find.text('예정'), findsNothing);
      expect(find.text('방문함'), findsNothing);
      expect(find.text('예산 구간 미확정'), findsNothing);
    });
  });
}
