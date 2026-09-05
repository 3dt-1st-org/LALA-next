import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/features/preferences/data/travel_preferences_remote.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';

// P1 deterministic account-race coverage for the preferences store seam.
// Every interleaving below is produced with Completers/gated factory calls —
// no timers, no sleeps — mirroring the Logto-success -> token -> /api/v1/me ->
// server-default lifecycle where account scope can change under a pending
// local write or remote response.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const devicePrefs = TravelPreferences(
    interests: {TravelInterest.localFood},
  );
  const guestEdit = TravelPreferences(
    interests: {TravelInterest.history},
    pace: TravelPace.relaxed,
  );
  const accountAPrefs = TravelPreferences(
    interests: {TravelInterest.nature},
  );
  const accountBPrefs = TravelPreferences(
    interests: {TravelInterest.localFood},
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('delayed local saves race an account switch', () {
    test(
      'a guest-era edit completing after connect must not silently upload '
      'to the newly connected account',
      () async {
        final remoteB = _AccountRemote('B', account: accountBPrefs);
        final factory = _GatedFactory();
        final store = TravelPreferencesStore(
          preferencesFactory: factory.call,
        );
        await store.ensureLoaded();
        // Device copy equals B's account copy, so the connect below would
        // legitimately reach `synced`.
        await store.save(devicePrefs);

        factory.arm();
        final editFuture = store.save(guestEdit);
        await store.connectAccount(remoteB);

        factory.open();
        await editFuture;

        // The non-racing oracle: an edit made before connecting compares as a
        // conflict on connect; it is never uploaded without an explicit choice.
        expect(remoteB.putCalls, 0);
        expect(store.value, guestEdit);
        expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);
        expect(store.serverRevision, 1);
      },
    );

    test(
      'a pending first save completing after server adoption must not leak '
      'the guest value into the account or fake a synced state',
      () async {
        final remoteB = _AccountRemote('B', account: accountBPrefs);
        final factory = _GatedFactory();
        final store = TravelPreferencesStore(
          preferencesFactory: factory.call,
        );

        // The only local write in flight is the guest's first save; the store
        // has no committed document yet.
        factory.arm();
        final guestFuture = store.save(guestEdit);
        // Connect + GET + adoption all settle while the guest save is pending.
        await store.connectAccount(remoteB);

        factory.open();
        await guestFuture;

        expect(remoteB.putCalls, 0);
        expect(store.value, guestEdit);
        expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);
        expect(store.serverRevision, 1);
      },
    );

    test(
      '"use account" resolving after disconnect keeps an honest local-only '
      'status instead of claiming synced',
      () async {
        final remoteA = _AccountRemote('A', account: accountAPrefs);
        final factory = _GatedFactory();
        final store = TravelPreferencesStore(
          preferencesFactory: factory.call,
        );
        await store.ensureLoaded();
        await store.save(devicePrefs);
        await store.connectAccount(remoteA);
        expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);

        factory.arm();
        final useFuture = store.useAccountPreferences();
        store.disconnectAccount();

        factory.open();
        await useFuture;

        // The explicit user choice still lands locally, but the store must not
        // report `synced` while no account is connected.
        expect(store.value, accountAPrefs);
        expect(store.syncStatus, TravelPreferencesSyncStatus.localOnly);
        expect(store.accountPreferences, isNull);
      },
    );
  });

  group('late responses from an old account scope', () {
    test(
      'a late GET completing after disconnect changes no account state',
      () async {
        final remoteA = _AccountRemote('A');
        remoteA.holdNextGet();
        final store = TravelPreferencesStore();
        await store.ensureLoaded();
        await store.save(devicePrefs);

        final connectFuture = store.connectAccount(remoteA);
        expect(store.syncStatus, TravelPreferencesSyncStatus.checking);
        store.disconnectAccount();
        remoteA.completeHeldGet(
          TravelPreferencesRemoteDocument(
            preferences: accountAPrefs,
            revision: 7,
            updatedAt: '2026-09-05T00:00:00Z',
          ),
        );
        await connectFuture;

        expect(store.syncStatus, TravelPreferencesSyncStatus.localOnly);
        expect(store.serverRevision, isNull);
        expect(store.accountPreferences, isNull);
        expect(store.value, devicePrefs);
      },
    );

    test(
      'a late GET from account A cannot overwrite account B\'s fresh state',
      () async {
        final remoteA = _AccountRemote('A');
        remoteA.holdNextGet();
        final remoteB = _AccountRemote('B', account: accountBPrefs);
        final store = TravelPreferencesStore();
        await store.ensureLoaded();
        await store.save(devicePrefs);

        final aFuture = store.connectAccount(remoteA);
        // Rapid A -> B switch: B fully synchronizes while A's GET is pending.
        await store.connectAccount(remoteB);
        expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
        expect(store.serverRevision, 1);

        remoteA.completeHeldGet(
          TravelPreferencesRemoteDocument(
            preferences: accountAPrefs,
            revision: 9,
            updatedAt: '2026-09-05T00:00:00Z',
          ),
        );
        await aFuture;

        expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
        expect(store.serverRevision, 1);
        expect(store.accountPreferences, accountBPrefs);
        expect(store.value, devicePrefs);
      },
    );

    test(
      'a late PUT response completing after disconnect cannot restore server '
      'state',
      () async {
        final remoteA = _AccountRemote('A', account: accountBPrefs);
        final store = TravelPreferencesStore();
        await store.ensureLoaded();
        await store.save(devicePrefs);
        await store.connectAccount(remoteA);
        expect(store.syncStatus, TravelPreferencesSyncStatus.synced);

        remoteA.holdNextPut();
        final saveFuture = store.save(guestEdit);
        store.disconnectAccount();
        remoteA.completeHeldPut(
          TravelPreferencesRemoteDocument(
            preferences: guestEdit,
            revision: 2,
            updatedAt: '2026-09-05T00:02:00Z',
          ),
        );
        await saveFuture;

        expect(store.syncStatus, TravelPreferencesSyncStatus.localOnly);
        expect(store.serverRevision, isNull);
        expect(store.accountPreferences, isNull);
        expect(store.value, guestEdit);
      },
    );
  });

  group('conflict and recovery paths', () {
    test(
      'a revision-conflicted PUT refetches and reports an honest conflict '
      'with the newer server version',
      () async {
        final remote = _AccountRemote('A', account: accountAPrefs);
        final store = TravelPreferencesStore();
        await store.ensureLoaded();
        await store.save(devicePrefs);
        await store.connectAccount(remote);
        expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);
        expect(store.serverRevision, 1);

        // Another device saved first: the server document moves to revision 2
        // before this device's explicit upload arrives with revision 1.
        remote.revision = 2;
        await store.saveDevicePreferencesToAccount();

        expect(remote.putCalls, 1);
        expect(remote.lastExpectedRevision, 1);
        expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);
        expect(store.serverRevision, 2);
        expect(store.accountPreferences, accountAPrefs);
        expect(store.value, devicePrefs);
      },
    );

    test(
      'an expired-token GET lands in a recoverable error without touching '
      'the device copy, and retry recovers',
      () async {
        final remote = _AccountRemote('A', account: accountAPrefs);
        final store = TravelPreferencesStore();
        await store.ensureLoaded();
        await store.save(devicePrefs);

        remote.getError = const LalaApiException(
          code: 'HTTP_401',
          message: 'LALA API request failed.',
          statusCode: 401,
          retryable: false,
        );
        await store.connectAccount(remote);

        expect(store.syncStatus, TravelPreferencesSyncStatus.error);
        expect(store.serverRevision, isNull);
        expect(store.value, devicePrefs);

        remote.getError = null;
        await store.retryAccountSync();

        expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);
        expect(store.serverRevision, 1);
        expect(store.value, devicePrefs);
      },
    );

    test(
      'device edits during a sync error stay local and are not uploaded '
      'behind the error',
      () async {
        final remote = _AccountRemote('A', account: accountAPrefs);
        remote.getError = const LalaApiException(
          code: 'HTTP_503',
          message: 'LALA API request failed.',
          statusCode: 503,
          retryable: true,
        );
        final store = TravelPreferencesStore();
        await store.ensureLoaded();
        await store.save(devicePrefs);
        await store.connectAccount(remote);
        expect(store.syncStatus, TravelPreferencesSyncStatus.error);

        await store.save(guestEdit);

        expect(remote.putCalls, 0);
        expect(store.value, guestEdit);
        expect(store.syncStatus, TravelPreferencesSyncStatus.error);
      },
    );
  });
}

/// SharedPreferences factory whose next call can be held until the test
/// releases it, putting a store write in flight at a deterministic point.
class _GatedFactory {
  Completer<void>? _pending;
  bool _armed = false;

  void arm() {
    _armed = true;
    _pending = Completer<void>();
  }

  void open() => _pending!.complete();

  Future<SharedPreferences> call() async {
    if (_armed) {
      _armed = false;
      await _pending!.future;
    }
    return SharedPreferences.getInstance();
  }
}

/// Scripted remote owned by one account scope. Holds are explicit so tests
/// interleave deterministically instead of relying on timing.
class _AccountRemote implements TravelPreferencesRemote {
  _AccountRemote(this.label, {this.account}) : revision = 1;

  final String label;
  TravelPreferences? account;
  int revision;
  Object? getError;
  int getCalls = 0;
  int putCalls = 0;
  int? lastExpectedRevision;
  TravelPreferences? lastPutValue;
  Completer<TravelPreferencesRemoteDocument?>? _heldGet;
  Completer<TravelPreferencesRemoteDocument>? _heldPut;

  void holdNextGet() => _heldGet = Completer<TravelPreferencesRemoteDocument?>();

  void completeHeldGet(TravelPreferencesRemoteDocument? document) =>
      _heldGet!.complete(document);

  void holdNextPut() =>
      _heldPut = Completer<TravelPreferencesRemoteDocument>();

  void completeHeldPut(TravelPreferencesRemoteDocument document) =>
      _heldPut!.complete(document);

  @override
  Future<TravelPreferencesRemoteDocument?> get() async {
    getCalls += 1;
    final held = _heldGet;
    if (held != null) {
      return held.future;
    }
    if (getError != null) {
      throw getError!;
    }
    final value = account;
    if (value == null) {
      return null;
    }
    return TravelPreferencesRemoteDocument(
      preferences: value,
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
    if (held != null) {
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
