// Lane 1 (§13.4) — unit tests for SelectedPlaceStore, the cross-tab selected-place
// SSOT. Verifies the reactive surface Lane 2 will persist against: current/listenable/
// set/clear, and ValueNotifier's own unchanged-value suppression (D4 no-op-skip).
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/core/state/selected_place_store.dart';

void main() {
  // The holder is a process-local singleton; reset before each case so a
  // selection made in one test cannot leak into another.
  setUp(SelectedPlaceStore.clear);

  group('SelectedPlaceStore', () {
    test('current is null after clear', () {
      expect(SelectedPlaceStore.current, isNull);
    });

    test('set publishes the id and current reflects it', () {
      SelectedPlaceStore.set('seed-test-cafe');
      expect(SelectedPlaceStore.current, 'seed-test-cafe');
    });

    test('set(null) / clear reverts to honest empty', () {
      SelectedPlaceStore.set('seed-test-cafe');
      SelectedPlaceStore.clear();
      expect(SelectedPlaceStore.current, isNull);

      SelectedPlaceStore.set('seed-test-cafe');
      SelectedPlaceStore.set(null);
      expect(SelectedPlaceStore.current, isNull);
    });

    test('listenable fires once per distinct value', () {
      final notifications = <String?>[];
      SelectedPlaceStore.listenable.addListener(() {
        notifications.add(SelectedPlaceStore.current);
      });

      SelectedPlaceStore.set('a');
      SelectedPlaceStore.set('b');

      expect(notifications, ['a', 'b']);
    });

    test('ValueNotifier suppresses a redundant write of the same id (D4)', () {
      var calls = 0;
      SelectedPlaceStore.listenable.addListener(() => calls++);

      SelectedPlaceStore.set('same');
      final firstCallCount = calls;
      // Re-publishing the identical id must not notify consumers.
      SelectedPlaceStore.set('same');

      expect(calls, firstCallCount);
    });

    test('multiple tabs (listeners) all observe a cross-tab write', () {
      final tabA = <String?>[];
      final tabB = <String?>[];
      SelectedPlaceStore.listenable.addListener(
        () => tabA.add(SelectedPlaceStore.current),
      );
      SelectedPlaceStore.listenable.addListener(
        () => tabB.add(SelectedPlaceStore.current),
      );

      SelectedPlaceStore.set('shared-id');

      expect(tabA, ['shared-id']);
      expect(tabB, ['shared-id']);
    });
  });
}
