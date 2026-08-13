// V5-B SAVE (B1 store side): the saved-place set toggles cleanly and survives a
// simulated cold-start restore(). Mirrors the V1 SelectedPlaceStore holder test.
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/core/state/saved_place_store.dart';

void main() {
  setUp(SavedPlaceStore.clear);
  tearDown(SavedPlaceStore.clear);

  test('toggle adds then removes (returns new saved state)', () {
    expect(SavedPlaceStore.toggle('a'), isTrue);
    expect(SavedPlaceStore.isSaved('a'), isTrue);
    expect(SavedPlaceStore.toggle('a'), isFalse);
    expect(SavedPlaceStore.isSaved('a'), isFalse);
  });

  test('B1: set survives a simulated cold-start restore()', () {
    SavedPlaceStore.toggle('seed-cafe');
    SavedPlaceStore.toggle('seed-museum');
    final persisted = Set<String>.of(SavedPlaceStore.current);

    SavedPlaceStore.clear();
    expect(SavedPlaceStore.current, isEmpty);
    SavedPlaceStore.restore(persisted);
    expect(SavedPlaceStore.current, {'seed-cafe', 'seed-museum'});
  });

  test('add/remove are idempotent', () {
    SavedPlaceStore.add('a');
    SavedPlaceStore.add('a'); // no duplicate, no double-notify crash
    expect(SavedPlaceStore.current.length, 1);
    SavedPlaceStore.remove('a');
    SavedPlaceStore.remove('a');
    expect(SavedPlaceStore.current, isEmpty);
  });
}
