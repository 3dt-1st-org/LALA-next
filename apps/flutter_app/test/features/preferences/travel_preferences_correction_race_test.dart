import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/features/preferences/data/travel_preferences_remote.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';

// PR199 correction regressions: each test converts an independently
// reproduced defect probe (Q1/Q2a/Q3/Q4) into its expected-correct outcome,
// plus initial-load and explicit use-account concurrency coverage. Every
// interleaving is produced with Completers and a gated preferences factory —
// no timers, no sleeps.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const devicePrefs = TravelPreferences(interests: {TravelInterest.localFood});
  const editV2 = TravelPreferences(
    interests: {TravelInterest.history},
    pace: TravelPace.relaxed,
  );
  const editV3 = TravelPreferences(
    interests: {TravelInterest.nature},
    pace: TravelPace.packed,
  );
  const accountAPrefs = TravelPreferences(interests: {TravelInterest.nature});
  const accountBPrefs = TravelPreferences(interests: {TravelInterest.localFood});

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Q1: stale conflict refetch across account switch', () {
    test(
      'a late refetch from account A cannot install its document into '
      'account B or arm a cross-revision PUT',
      () async {
        final remoteA = _AccountRemote('A', account: accountAPrefs);
        final remoteB = _AccountRemote('B', account: devicePrefs);
        final store = TravelPreferencesStore();
        await store.ensureLoaded();
        await store.save(devicePrefs);
        await store.connectAccount(remoteA);
        expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);

        remoteA.revision = 2; // The explicit PUT with revision 1 must fail.
        remoteA.holdNextGet(); // The catch-path refetch.
        final putFuture = store.saveDevicePreferencesToAccount();
        await remoteA.getEntered;

        store.disconnectAccount();
        await store.connectAccount(remoteB);
        expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
        expect(store.serverRevision, 1);
        expect(store.accountPreferences, devicePrefs);

        remoteA.completeHeldGet(
          TravelPreferencesRemoteDocument(
            preferences: accountAPrefs,
            revision: 9,
            updatedAt: '2026-09-05T00:00:00Z',
          ),
        );
        await putFuture;

        // B's document/revision survive A's late refetch untouched.
        expect(store.accountPreferences, devicePrefs);
        expect(store.serverRevision, 1);
        expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
        expect(store.accountConnected, isTrue);

        // The next ordinary save uploads to B with B's own revision, not A's.
        await store.save(editV2);
        expect(remoteB.putCalls, 1);
        expect(remoteB.lastExpectedRevision, 1);
        expect(remoteB.lastPutValue, editV2);
        expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
      },
    );
  });

  group('Q2a: stale adoption across account switch', () {
    test(
      "A's late adoption is discarded; B's accepted local value and stored "
      'JSON stay intact with an honest synced pairing',
      () async {
        final remoteA = _AccountRemote('A', account: accountAPrefs);
        final remoteB = _AccountRemote('B', account: accountBPrefs);
        final factory = _GatedFactory();
        final store = TravelPreferencesStore(preferencesFactory: factory.call);
        await store.ensureLoaded(); // No local document yet.

        factory.arm();
        final aConnect = store.connectAccount(remoteA);
        await factory.entered; // A's adoption write parks at the gate.

        await store.connectAccount(remoteB); // B adopts and commits first.
        expect(store.value, accountBPrefs);
        expect(store.syncStatus, TravelPreferencesSyncStatus.synced);

        factory.open();
        await aConnect;

        expect(store.value, accountBPrefs);
        final prefs = await SharedPreferences.getInstance();
        final stored = jsonDecode(
          prefs.getString(kTravelPreferencesStorageKey)!,
        ) as Map<String, Object?>;
        final soft = stored['soft']! as Map<String, Object?>;
        expect(soft['interests'], contains('localFood')); // B's data, not A's.
        expect(store.accountPreferences, accountBPrefs);
        expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
      },
    );
  });

  group('Q2b: documented use-account boundary', () {
    test(
      'an A-era "use account" landing after a B switch surfaces a conflict '
      'marker (documented boundary: surfaces, does not isolate)',
      () async {
        final remoteA = _AccountRemote('A', account: accountAPrefs);
        final remoteB = _AccountRemote('B', account: devicePrefs);
        final factory = _GatedFactory();
        final store = TravelPreferencesStore(preferencesFactory: factory.call);
        await store.ensureLoaded();
        await store.save(devicePrefs);
        await store.connectAccount(remoteA);
        expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);

        factory.arm();
        final useFuture = store.useAccountPreferences();
        await factory.entered;

        store.disconnectAccount();
        await store.connectAccount(remoteB);
        expect(store.value, devicePrefs);
        expect(store.syncStatus, TravelPreferencesSyncStatus.synced);

        factory.open();
        await useFuture;

        // The explicit A-era choice still lands on the device copy, but it is
        // labeled as a conflict against B's account document — never `synced`.
        expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);
        expect(store.value, accountAPrefs);
        expect(store.accountPreferences, devicePrefs);
        final prefs = await SharedPreferences.getInstance();
        final stored = jsonDecode(
          prefs.getString(kTravelPreferencesStorageKey)!,
        ) as Map<String, Object?>;
        final soft = stored['soft']! as Map<String, Object?>;
        expect(soft['interests'], contains('nature'));
      },
    );

    test(
      'a newer committed user edit supersedes an in-flight "use account" '
      'choice instead of being overwritten by it',
      () async {
        final remoteA = _AccountRemote('A', account: accountAPrefs);
        final factory = _GatedFactory();
        final store = TravelPreferencesStore(preferencesFactory: factory.call);
        await store.ensureLoaded();
        await store.save(devicePrefs);
        await store.connectAccount(remoteA);
        expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);

        factory.arm();
        final useFuture = store.useAccountPreferences();
        await factory.entered;

        // The user keeps editing before the explicit choice lands.
        await store.save(editV2);
        expect(store.value, editV2);

        factory.open();
        await useFuture;

        // Newest explicit intent wins: the older choice is discarded.
        expect(store.value, editV2);
        expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);
        expect(remoteA.putCalls, 0);
      },
    );
  });

  group('Q3: clear fencing', () {
    test(
      'a paused pre-clear save cannot resurrect the cleared document or '
      'upload it after deletion',
      () async {
        final remoteA = _AccountRemote('A', account: devicePrefs);
        final factory = _GatedFactory();
        final store = TravelPreferencesStore(preferencesFactory: factory.call);
        await store.ensureLoaded();
        await store.save(devicePrefs);
        await store.connectAccount(remoteA);
        expect(store.syncStatus, TravelPreferencesSyncStatus.synced);

        factory.arm();
        final saveFuture = store.save(editV2);
        await factory.entered;

        await store.clear();
        expect(store.value, const TravelPreferences());
        final mid = await SharedPreferences.getInstance();
        expect(mid.getString(kTravelPreferencesStorageKey), isNull);

        factory.open();
        await saveFuture;

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(kTravelPreferencesStorageKey), isNull);
        expect(store.value, const TravelPreferences());
        expect(store.hasLocalDocument, isFalse);
        // The device copy is gone while the account document remains: the
        // honest pairing is a conflict, never a resurrected synced claim.
        expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);
        expect(remoteA.putCalls, 0);
      },
    );

    test(
      'a paused pre-clear server adoption cannot resurrect the cleared '
      'document',
      () async {
        final remoteA = _AccountRemote('A', account: accountAPrefs);
        final factory = _GatedFactory();
        final store = TravelPreferencesStore(preferencesFactory: factory.call);
        await store.ensureLoaded();

        factory.arm();
        final connectFuture = store.connectAccount(remoteA);
        await factory.entered; // A's adoption parks at the gate.

        await store.clear();
        final mid = await SharedPreferences.getInstance();
        expect(mid.getString(kTravelPreferencesStorageKey), isNull);

        factory.open();
        await connectFuture;

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(kTravelPreferencesStorageKey), isNull);
        expect(store.value, const TravelPreferences());
        expect(store.hasLocalDocument, isFalse);
        expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);
      },
    );

    test(
      'a save started after clear commits normally (deletion does not fence '
      'future intent)',
      () async {
        final store = TravelPreferencesStore();
        await store.ensureLoaded();
        await store.save(devicePrefs);

        await store.clear();
        await store.save(editV2);

        expect(store.value, editV2);
        expect(store.hasLocalDocument, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(kTravelPreferencesStorageKey), isNotNull);
      },
    );
  });

  group('Q4: save racing an in-flight successful PUT', () {
    test(
      'a local edit landing during the PUT is reported as a pending '
      'conflict, not a synced equality',
      () async {
        final remoteA = _AccountRemote('A', account: devicePrefs);
        final store = TravelPreferencesStore();
        await store.ensureLoaded();
        await store.save(devicePrefs);
        await store.connectAccount(remoteA);
        expect(store.syncStatus, TravelPreferencesSyncStatus.synced);

        remoteA.holdNextPut();
        final save2 = store.save(editV2);
        await remoteA.putEntered;

        await store.save(editV3); // Lands locally while the PUT is in flight.
        expect(store.value, editV3);

        // The server accepts the in-flight PUT of editV2 at revision 2.
        remoteA
          ..account = editV2
          ..revision = 2;
        remoteA.completeHeldPut(
          TravelPreferencesRemoteDocument(
            preferences: editV2,
            revision: 2,
            updatedAt: '2026-09-05T00:02:00Z',
          ),
        );
        await save2;

        expect(store.accountPreferences, editV2);
        expect(store.serverRevision, 2);
        expect(store.value, editV3);
        // Honest pending-conflict: the unsent edit is visible, and the next
        // explicit upload pairs with revision 2.
        expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);
        expect(remoteA.putCalls, 1);

        await store.saveDevicePreferencesToAccount();
        expect(remoteA.lastExpectedRevision, 2);
        expect(remoteA.lastPutValue, editV3);
        expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
      },
    );
  });

  group('initial load concurrency', () {
    test(
      'a stale stored document cannot overwrite a fresh edit that committed '
      'while the load was in flight',
      () async {
        const storedPrefs = TravelPreferences(
          interests: {TravelInterest.history},
        );
        SharedPreferences.setMockInitialValues(<String, Object>{
          kTravelPreferencesStorageKey: jsonEncode(storedPrefs.toJson()),
          kTravelPreferencesUpdatedAtKey: '2026-09-01T00:00:00Z',
        });
        final factory = _GatedFactory();
        final store = TravelPreferencesStore(preferencesFactory: factory.call);

        factory.arm();
        final loadFuture = store.ensureLoaded();
        await factory.entered; // The load parks at the storage seam.

        // An explicit edit commits while the load is parked.
        await store.save(editV3);
        expect(store.value, editV3);

        factory.open();
        await loadFuture;

        // The stale stored document must not resurrect over the fresh edit.
        expect(store.value, editV3);
        expect(store.hasLocalDocument, isTrue);
        final prefs = await SharedPreferences.getInstance();
        final stored = jsonDecode(
          prefs.getString(kTravelPreferencesStorageKey)!,
        ) as Map<String, Object?>;
        final soft = stored['soft']! as Map<String, Object?>;
        expect(soft['interests'], contains('nature')); // editV3, not history.
      },
    );
  });
}

/// Preferences factory whose next call parks until released; `entered` lets a
/// test await the exact moment the write suspends at the storage seam.
class _GatedFactory {
  Completer<void>? _pending;
  Completer<void>? _entered;
  bool _armed = false;

  void arm() {
    _armed = true;
    _pending = Completer<void>();
    _entered = Completer<void>();
  }

  void open() => _pending!.complete();

  Future<void> get entered => _entered!.future;

  Future<SharedPreferences> call() async {
    if (_armed) {
      _armed = false;
      _entered!.complete();
      await _pending!.future;
    }
    return SharedPreferences.getInstance();
  }
}

/// Scripted remote owned by one account scope, with holdable GET/PUT.
class _AccountRemote implements TravelPreferencesRemote {
  _AccountRemote(this.label, {required this.account}) : revision = 1;

  final String label;
  TravelPreferences account;
  int revision;
  int putCalls = 0;
  int? lastExpectedRevision;
  TravelPreferences? lastPutValue;
  Completer<TravelPreferencesRemoteDocument?>? _heldGet;
  bool _heldGetConsumed = false;
  Completer<void>? _getEntered;
  Completer<TravelPreferencesRemoteDocument>? _heldPut;
  bool _heldPutConsumed = false;
  Completer<void>? _putEntered;

  void holdNextGet() {
    _heldGet = Completer<TravelPreferencesRemoteDocument?>();
    _heldGetConsumed = false;
    _getEntered = Completer<void>();
  }

  void completeHeldGet(TravelPreferencesRemoteDocument? document) =>
      _heldGet!.complete(document);

  Future<void> get getEntered => _getEntered!.future;

  void holdNextPut() {
    _heldPut = Completer<TravelPreferencesRemoteDocument>();
    _heldPutConsumed = false;
    _putEntered = Completer<void>();
  }

  void completeHeldPut(TravelPreferencesRemoteDocument document) =>
      _heldPut!.complete(document);

  Future<void> get putEntered => _putEntered!.future;

  @override
  Future<TravelPreferencesRemoteDocument?> get() async {
    final entered = _getEntered;
    if (entered != null) {
      _getEntered = null;
      entered.complete();
    }
    final held = _heldGet;
    if (held != null && !_heldGetConsumed) {
      _heldGetConsumed = true;
      return held.future;
    }
    return TravelPreferencesRemoteDocument(
      preferences: account,
      revision: revision,
      updatedAt: '2026-09-05T00:00:00Z',
    );
  }

  @override
  Future<TravelPreferencesRemoteDocument> put({
    required TravelPreferences preferences,
    required int expectedRevision,
  }) async {
    putCalls += 1;
    lastExpectedRevision = expectedRevision;
    lastPutValue = preferences;
    final held = _heldPut;
    if (held != null && !_heldPutConsumed) {
      _heldPutConsumed = true;
      _putEntered!.complete();
      return held.future;
    }
    if (expectedRevision != revision) {
      throw StateError('revision conflict');
    }
    account = preferences;
    revision += 1;
    return TravelPreferencesRemoteDocument(
      preferences: preferences,
      revision: revision,
      updatedAt: '2026-09-05T00:01:00Z',
    );
  }
}
