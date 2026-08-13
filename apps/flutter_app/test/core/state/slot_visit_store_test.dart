// V5-B VISIT (B4 store side): toggle persists in the in-memory store and
// survives a simulate store reload via restore(). planned↔visited flips cleanly;
// unrecorded slots default to 'planned' (honest empty, contract A9).
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/core/state/slot_visit_store.dart';

void main() {
  setUp(SlotVisitStore.clear);
  tearDown(SlotVisitStore.clear);

  test('unrecorded slot defaults to planned (honest empty)', () {
    expect(SlotVisitStore.statusFor('2026-08-14', 'morning'), 'planned');
  });

  test('B4: toggle planned → visited and back', () {
    const date = '2026-08-14';
    expect(SlotVisitStore.toggle(date, 'morning'), 'visited');
    expect(SlotVisitStore.statusFor(date, 'morning'), 'visited');
    expect(SlotVisitStore.toggle(date, 'morning'), 'planned');
    expect(SlotVisitStore.statusFor(date, 'morning'), 'planned');
  });

  test('B4: status survives a simulated reload via restore()', () {
    const date = '2026-08-14';
    SlotVisitStore.toggle(date, 'lunch'); // visited
    final persisted = Map<String, String>.of(SlotVisitStore.current);

    // Simulate cold start: fresh store restored from persisted map.
    SlotVisitStore.clear();
    expect(SlotVisitStore.statusFor(date, 'lunch'), 'planned');
    SlotVisitStore.restore(persisted);
    expect(SlotVisitStore.statusFor(date, 'lunch'), 'visited');
  });

  test('toggling back to planned removes the entry (only non-defaults stored)',
      () {
    const date = '2026-08-14';
    SlotVisitStore.toggle(date, 'dinner'); // visited
    SlotVisitStore.toggle(date, 'dinner'); // back to planned
    expect(SlotVisitStore.current.containsKey(SlotVisitStore.key(date, 'dinner')),
        isFalse);
  });

  test('different dates/periods are independent', () {
    SlotVisitStore.toggle('2026-08-14', 'morning');
    expect(SlotVisitStore.statusFor('2026-08-14', 'morning'), 'visited');
    expect(SlotVisitStore.statusFor('2026-08-14', 'lunch'), 'planned');
    expect(SlotVisitStore.statusFor('2026-08-15', 'morning'), 'planned');
  });
}
