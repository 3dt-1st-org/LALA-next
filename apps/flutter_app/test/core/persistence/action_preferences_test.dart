// V5-B action persistence: cold-start hydrate (B1), corrupt→empty (B2),
// stale-version→ignored (B3), and the epoch guard (a fresh change during the
// load window is not clobbered). Mirrors the cross_tab cold-start test shape.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/core/persistence/action_preferences.dart';
import 'package:lala_next_app/core/state/saved_place_store.dart';
import 'package:lala_next_app/core/state/slot_visit_store.dart';

void main() {
  // The holders + persistence gateway are process-local singletons; reset between
  // cases so a prior attach/restore never leaks.
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ActionPersistence.detach();
    SavedPlaceStore.clear();
    SlotVisitStore.clear();
  });

  tearDown(() {
    ActionPersistence.detach();
    SavedPlaceStore.clear();
    SlotVisitStore.clear();
  });

  group('ActionPreferences.load (B1/B2/B3)', () {
    test('B1: cold-start restores a previously persisted saved-place set', () async {
      final prefs = await ActionPreferences.createDefault();
      await prefs.writeSavedPlaces(<String>{'seed-cafe', 'seed-museum'});

      // A fresh instance over the same SharedPreferences hydrates the set.
      final reloaded = await ActionPreferences.createDefault();
      final snapshot = await reloaded.load();
      expect(snapshot.savedPlaceIds, {'seed-cafe', 'seed-museum'});
    });

    test('B1: cold-start restores a previously persisted slot-visit map', () async {
      final prefs = await ActionPreferences.createDefault();
      await prefs.writeSlotVisits(<String, String>{'2026-08-14:morning': 'visited'});

      final reloaded = await ActionPreferences.createDefault();
      final snapshot = await reloaded.load();
      expect(snapshot.slotVisits, {'2026-08-14:morning': 'visited'});
    });

    test('B1: empty store hydrates empty (honest empty, no throw)', () async {
      final prefs = await ActionPreferences.createDefault();
      final snapshot = await prefs.load();
      expect(snapshot.savedPlaceIds, isEmpty);
      expect(snapshot.slotVisits, isEmpty);
    });

    test('B2: corrupt saved-places JSON → empty set, no crash', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _kSavedPlacesKey: '{not valid json',
      });
      final prefs = await ActionPreferences.createDefault();
      final snapshot = await prefs.load();
      expect(snapshot.savedPlaceIds, isEmpty);
    });

    test('B2: corrupt slot-visits JSON → empty map, no crash', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _kSlotVisitsKey: '}}} totally broken',
      });
      final prefs = await ActionPreferences.createDefault();
      final snapshot = await prefs.load();
      expect(snapshot.slotVisits, isEmpty);
    });

    test('B2: saved-places envelope with non-List ids → empty', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _kSavedPlacesKey: '{"v":1,"ids":"not-a-list"}',
      });
      final prefs = await ActionPreferences.createDefault();
      final snapshot = await prefs.load();
      expect(snapshot.savedPlaceIds, isEmpty);
    });

    test('B3: older envelope version is ignored (stale → empty)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _kSavedPlacesKey: '{"v":0,"ids":["seed-cafe"]}',
        _kSlotVisitsKey: '{"v":0,"visits":{"2026-08-14:morning":"visited"}}',
      });
      final prefs = await ActionPreferences.createDefault();
      final snapshot = await prefs.load();
      expect(snapshot.savedPlaceIds, isEmpty);
      expect(snapshot.slotVisits, isEmpty);
    });

    test('B3: future envelope version is also ignored (forward-compat)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _kSavedPlacesKey: '{"v":999,"ids":["seed-cafe"]}',
      });
      final prefs = await ActionPreferences.createDefault();
      final snapshot = await prefs.load();
      expect(snapshot.savedPlaceIds, isEmpty);
    });

    test('round-trip: write → clearAll → empty', () async {
      final prefs = await ActionPreferences.createDefault();
      await prefs.writeSavedPlaces(<String>{'a', 'b'});
      await prefs.writeSlotVisits(<String, String>{'d:p': 'visited'});
      await prefs.clearAll();
      final snapshot = await prefs.load();
      expect(snapshot.savedPlaceIds, isEmpty);
      expect(snapshot.slotVisits, isEmpty);
    });

    test('writeSavedPlaces([]) removes the key (no orphan envelope)', () async {
      final prefs = await ActionPreferences.createDefault();
      await prefs.writeSavedPlaces(<String>{'a'});
      await prefs.writeSavedPlaces(<String>{});
      final snapshot = await prefs.load();
      expect(snapshot.savedPlaceIds, isEmpty);
    });
  });

  group('ActionPersistence.attachAndHydrate (cold-start hydration gateway)', () {
    test('B1: hydrates SavedPlaceStore + SlotVisitStore from persisted prefs',
        () async {
      // Seed persisted state as if a prior session wrote it.
      final seeding = await ActionPreferences.createDefault();
      await seeding.writeSavedPlaces(<String>{'seed-cafe'});
      await seeding.writeSlotVisits(<String, String>{'2026-08-14:lunch': 'visited'});

      final prefs = await ActionPreferences.createDefault();
      await ActionPersistence.attachAndHydrate(prefs);

      expect(SavedPlaceStore.current, {'seed-cafe'});
      expect(SlotVisitStore.statusFor('2026-08-14', 'lunch'), 'visited');
    });

    test('B3 epoch guard: a fresh change during the load window is not clobbered',
        () async {
      // Seed a stale persisted value.
      final seeding = await ActionPreferences.createDefault();
      await seeding.writeSavedPlaces(<String>{'stale-id'});

      // Use a slow backend so we can race a fresh set() into the load window.
      final slow = ActionPreferences(await _seededSlowBackend());
      final hydrate = ActionPersistence.attachAndHydrate(slow);
      // While load is in flight, a fresh selection lands.
      SavedPlaceStore.restore(<String>{'fresh-id'});
      await hydrate;

      // The fresh value wins; the stale persisted 'stale-id' did NOT clobber it.
      expect(SavedPlaceStore.current, {'fresh-id'});
    });

    test('write-through: a toggle after attach persists to prefs', () async {
      final prefs = await ActionPreferences.createDefault();
      await ActionPersistence.attachAndHydrate(prefs);

      SavedPlaceStore.toggle('seed-cafe');
      // Let the write-through listener's unawaited future resolve.
      await Future<void>.delayed(Duration.zero);

      final reloaded = await ActionPreferences.createDefault();
      final snapshot = await reloaded.load();
      expect(snapshot.savedPlaceIds, {'seed-cafe'});
    });
  });
}

const String _kSavedPlacesKey = '${kActionStoragePrefix}savedPlaces';
const String _kSlotVisitsKey = '${kActionStoragePrefix}slotVisits';

/// Seeds SharedPreferences with a single saved-places envelope and returns a
/// slow backend over it so the epoch-guard test can race the load window.
Future<_SlowBackend> _seededSlowBackend() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _kSavedPlacesKey,
    '{"v":1,"ids":["stale-id"]}',
  );
  return _SlowBackend(prefs);
}

/// Backend that delays reads so tests can race the hydration load window.
class _SlowBackend implements ActionPreferencesBackend {
  _SlowBackend(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<String?> getString(String key) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return _prefs.getString(key);
  }

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}
