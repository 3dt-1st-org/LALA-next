import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_remote.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';

/// Keys as they arrive at the real platform store seam: `SharedPreferences`
/// prefixes every key with `flutter.` before calling the store platform.
const String _platformDocKey = 'flutter.$kTravelPreferencesStorageKey';
const String _platformTimestampKey =
    'flutter.$kTravelPreferencesUpdatedAtKey';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('round-trips soft, hard, mobility, and docent preferences', () {
    final original = TravelPreferences(
      pace: TravelPace.relaxed,
      crowdTolerance: CrowdTolerance.quiet,
      walkingBand: WalkingBand.short,
      interests: const {TravelInterest.localFood, TravelInterest.history},
      travelStyles: const {TravelStyle.hiddenLocal},
      indoorOutdoorPreference: IndoorOutdoorPreference.indoor,
      weatherSensitivity: WeatherSensitivity.high,
      cuisines: const {FoodCuisine.korean, FoodCuisine.marketFood},
      foodAdventure: FoodAdventure.adventurous,
      spiceLevel: SpicePreference.mild,
      orderRequests: const {
        RestaurantOrderRequest.quietTable,
        RestaurantOrderRequest.takeout,
      },
      dietaryModes: const {DietaryMode.halal},
      allergens: const {Allergen.shellfish},
      avoidIngredients: '고수',
      companions: const {TravelCompanion.friends},
      transportModes: const {TransportMode.transit, TransportMode.taxi},
      restFrequency: RestFrequency.frequent,
      maxOneWayMinutes: 60,
      maxTransfers: 1,
      avoidStairs: true,
      verifiedAccessibilityOnly: true,
      budgetBand: BudgetBand.special,
      maxWaitMinutes: 40,
      dayRhythm: DayRhythm.night,
      excludeClosingSoon: true,
      docentDepth: DocentDepth.deep,
      docentAutoplay: true,
      placeNameMode: PlaceNameMode.localized,
      narrationSpeed: 1.2,
      continueNarration: false,
      pronunciationHelp: true,
    );

    final decoded = TravelPreferences.fromJson(
      jsonDecode(jsonEncode(original.toJson())),
    );

    expect(decoded, original);
  });

  test('equal preference sets keep the same hash regardless of order', () {
    final first = TravelPreferences(
      interests: <TravelInterest>{
        TravelInterest.localFood,
        TravelInterest.history,
      },
      transportModes: <TransportMode>{
        TransportMode.walk,
        TransportMode.transit,
      },
      orderRequests: <RestaurantOrderRequest>{
        RestaurantOrderRequest.takeout,
        RestaurantOrderRequest.smallPortion,
      },
    );
    final second = TravelPreferences(
      interests: <TravelInterest>{
        TravelInterest.history,
        TravelInterest.localFood,
      },
      transportModes: <TransportMode>{
        TransportMode.transit,
        TransportMode.walk,
      },
      orderRequests: <RestaurantOrderRequest>{
        RestaurantOrderRequest.smallPortion,
        RestaurantOrderRequest.takeout,
      },
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test('spice and order requests round-trip and clear through copyWith', () {
    const base = TravelPreferences(
      spiceLevel: SpicePreference.spicy,
      orderRequests: {RestaurantOrderRequest.staffRecommendation},
    );

    final encoded = jsonEncode(base.toJson());
    expect(encoded, contains('"spice_level":"spicy"'));
    expect(encoded, contains('"order_requests":["staffRecommendation"]'));
    // Explicitly saved values survive the round trip.
    expect(TravelPreferences.fromJson(jsonDecode(encoded)), base);

    // The sentinel lets callers clear the saved value back to "not saved".
    final cleared = base.copyWith(spiceLevel: null);
    expect(cleared.spiceLevel, isNull);
    expect(cleared.orderRequests, base.orderRequests);
    expect(cleared, isNot(base));
  });

  test('old payloads default to not-saved spice and empty order requests', () {
    // CP1-era stored document: no CP2 keys at all.
    final decoded = TravelPreferences.fromJson(<String, Object>{
      'version': TravelPreferences.schemaVersion,
      'soft': <String, Object>{'food_cuisines': <String>['korean']},
      'hard': <String, Object>{},
      'locale': <String, Object>{},
    });

    expect(decoded.spiceLevel, isNull);
    expect(decoded.orderRequests, isEmpty);
    expect(decoded.cuisines, {FoodCuisine.korean});
    expect(decoded, isNot(const TravelPreferences(spiceLevel: null)));
  });

  test('malformed restaurant values are bounded honestly', () {
    final decoded = TravelPreferences.fromJson(<String, Object>{
      'version': TravelPreferences.schemaVersion,
      'soft': <String, Object>{
        // Unknown spice value falls back to "not saved" — never a guess.
        'spice_level': 'volcanic',
        // Unknown entries are dropped; the bounded cap keeps at most 4.
        'order_requests': <String>[
          'staffRecommendation',
          'smallPortion',
          'quietTable',
          'takeout',
          'extraNapkins',
        ],
      },
      'hard': <String, Object>{},
      'locale': <String, Object>{},
    });

    expect(decoded.spiceLevel, isNull);
    expect(decoded.orderRequests, {
      RestaurantOrderRequest.staffRecommendation,
      RestaurantOrderRequest.smallPortion,
      RestaurantOrderRequest.quietTable,
      RestaurantOrderRequest.takeout,
    });
    expect(decoded.orderRequests, hasLength(TravelPreferences.maxOrderRequests));
  });

  test('rejects unknown schema and safely bounds malformed values', () {
    expect(
      TravelPreferences.fromJson(<String, Object>{'version': 99}),
      const TravelPreferences(),
    );

    final decoded = TravelPreferences.fromJson(<String, Object>{
      'version': TravelPreferences.schemaVersion,
      'soft': <String, Object>{
        'interests': <String>[
          ...TravelInterest.values.map((value) => value.name),
          'unknown',
        ],
        'max_one_way_minutes': 999,
        'max_transfers': 99,
      },
      'hard': <String, Object>{
        'avoid_ingredients': 'a' * 200,
        'max_wait_minutes': 999,
      },
      'locale': <String, Object>{'narration_speed': 8.0},
    });

    expect(decoded.interests, hasLength(TravelPreferences.maxInterests));
    expect(
      decoded.avoidIngredients,
      hasLength(TravelPreferences.maxAvoidIngredientsLength),
    );
    expect(decoded.maxOneWayMinutes, 30);
    expect(decoded.maxTransfers, 2);
    expect(decoded.maxWaitMinutes, 20);
    expect(decoded.narrationSpeed, 1.0);
  });

  test('persists locally and hydrates a fresh store', () async {
    final first = TravelPreferencesStore();
    await first.ensureLoaded();
    final next = first.value.copyWith(
      interests: const {TravelInterest.localFood},
      avoidStairs: true,
    );

    await first.save(next);
    final second = TravelPreferencesStore();
    await second.ensureLoaded();

    expect(second.value, next);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(kTravelPreferencesStorageKey), isNotNull);
  });

  test('falls back to defaults when local JSON is corrupt', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kTravelPreferencesStorageKey: '{bad json',
    });
    final store = TravelPreferencesStore();

    await store.ensureLoaded();

    expect(store.value, const TravelPreferences());
    expect(store.isLoaded, isTrue);
  });

  test(
    'adopts account preferences when the device has no local document',
    () async {
      const account = TravelPreferences(
        interests: {TravelInterest.history},
        pace: TravelPace.relaxed,
      );
      final remote = _MemoryRemote(account: account, revision: 3);
      final store = TravelPreferencesStore();

      await store.connectAccount(remote);

      expect(store.value, account);
      expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
      expect(store.serverRevision, 3);
    },
  );

  test(
    'does not silently overwrite differing device and account values',
    () async {
      final store = TravelPreferencesStore();
      await store.ensureLoaded();
      await store.save(
        const TravelPreferences(interests: {TravelInterest.localFood}),
      );
      final remote = _MemoryRemote(
        account: const TravelPreferences(interests: {TravelInterest.history}),
        revision: 4,
      );

      await store.connectAccount(remote);

      expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);
      expect(store.value.interests, {TravelInterest.localFood});

      await store.useAccountPreferences();
      expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
      expect(store.value.interests, {TravelInterest.history});
    },
  );

  test('uploads the explicit device choice with optimistic revision', () async {
    final store = TravelPreferencesStore();
    await store.ensureLoaded();
    const device = TravelPreferences(interests: {TravelInterest.localFood});
    await store.save(device);
    final remote = _MemoryRemote(
      account: const TravelPreferences(interests: {TravelInterest.history}),
      revision: 5,
    );
    await store.connectAccount(remote);

    await store.saveDevicePreferencesToAccount();

    expect(remote.lastExpectedRevision, 5);
    expect(remote.account, device);
    expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
    expect(store.serverRevision, 6);
  });

  test('account sync round-trips spice and order requests honestly', () async {
    // A device with saved CP2 values vs an account without them is a real
    // conflict (nothing silently overwritten), and the explicit device
    // upload carries the values verbatim.
    final store = TravelPreferencesStore();
    await store.ensureLoaded();
    const device = TravelPreferences(
      spiceLevel: SpicePreference.medium,
      orderRequests: {RestaurantOrderRequest.quietTable},
    );
    await store.save(device);
    final remote = _MemoryRemote(
      account: const TravelPreferences(),
      revision: 2,
    );

    await store.connectAccount(remote);

    expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);
    expect(store.value.spiceLevel, SpicePreference.medium);
    expect(store.value.orderRequests, {RestaurantOrderRequest.quietTable});

    await store.saveDevicePreferencesToAccount();

    expect(remote.account?.spiceLevel, SpicePreference.medium);
    expect(remote.account?.orderRequests, {RestaurantOrderRequest.quietTable});
    expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
  });

  test('serializes competing account adoptions at the storage seam', () async {
    final preferences = _GatedSharedPreferencesStore();
    SharedPreferencesStorePlatform.instance = preferences;
    const accountA = TravelPreferences(interests: {TravelInterest.history});
    const accountB = TravelPreferences(
      interests: {TravelInterest.localFood},
      pace: TravelPace.relaxed,
    );
    final store = TravelPreferencesStore();
    final remoteA = _MemoryRemote(account: accountA, revision: 1);
    final remoteB = _MemoryRemote(
      account: accountB,
      revision: 7,
      updatedAt: '2026-09-03T00:00:00Z',
    );

    // Park the first account's adoption write mid-flight at the platform
    // seam, then start a second account connect while it is parked.
    preferences.blockKey(_platformDocKey);
    final firstConnect = store.connectAccount(remoteA);
    await preferences.nextStartOf(_platformDocKey);
    final secondConnect = store.connectAccount(remoteB);
    await pumpEventQueue();

    // Nothing has committed yet, so the device copy is still pristine and
    // the newest account document is the one the store is adopting toward.
    expect(store.value, const TravelPreferences());
    expect(store.hasLocalDocument, isFalse);
    expect(store.syncStatus, TravelPreferencesSyncStatus.checking);
    expect(store.accountPreferences, accountB);

    preferences.releaseKey(_platformDocKey);
    await firstConnect;
    await secondConnect;

    // The stale adoption still commits its (now-superseded) document first,
    // but the newer account's adoption commits last and wins — no torn pair,
    // no interleaved half-writes from the two connects.
    expect(store.value, accountB);
    expect(store.accountPreferences, accountB);
    expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
    expect(store.serverRevision, 7);
    expect(store.deviceUpdatedAt, '2026-09-03T00:00:00Z');
    final disk = await preferences.diskSnapshot();
    expect(disk[_platformDocKey], jsonEncode(accountB.toJson()));
    expect(disk[_platformTimestampKey], '2026-09-03T00:00:00Z');
    expect(preferences.operations, <String>[
      'set:$_platformDocKey',
      'set:$_platformTimestampKey',
      'set:$_platformDocKey',
      'set:$_platformTimestampKey',
    ]);
  });

  test('a clear after a parked save removes the persisted document last', () async {
    final preferences = _GatedSharedPreferencesStore();
    SharedPreferencesStorePlatform.instance = preferences;
    final store = TravelPreferencesStore();
    await store.ensureLoaded();
    const next = TravelPreferences(interests: {TravelInterest.localFood});

    // Park an explicit save mid-flight, then call clear() while it is parked.
    preferences.blockKey(_platformDocKey);
    final saveFuture = store.save(next);
    await preferences.nextStartOf(_platformDocKey);
    final clearFuture = store.clear();
    await pumpEventQueue();

    // The parked edit has not landed in memory yet ...
    expect(store.value, const TravelPreferences());
    expect(store.hasLocalDocument, isFalse);

    preferences.releaseKey(_platformDocKey);
    await saveFuture;
    await clearFuture;

    // The parked save commits its pair and the clear removes both keys
    // afterwards — the cleared state is never resurrected by the parked pair.
    expect(store.value, const TravelPreferences());
    expect(store.hasLocalDocument, isFalse);
    expect(store.deviceUpdatedAt, isNull);
    expect(store.syncStatus, TravelPreferencesSyncStatus.localOnly);
    final disk = await preferences.diskSnapshot();
    expect(disk, isEmpty);
    expect(preferences.operations, <String>[
      'set:$_platformDocKey',
      'set:$_platformTimestampKey',
      'remove:$_platformDocKey',
      'remove:$_platformTimestampKey',
    ]);
  });

  test('back-to-back saves commit whole documents without torn pairs', () async {
    final preferences = _GatedSharedPreferencesStore();
    SharedPreferencesStorePlatform.instance = preferences;
    final store = TravelPreferencesStore();
    const first = TravelPreferences(interests: {TravelInterest.history});
    const second = TravelPreferences(interests: {TravelInterest.localFood});
    const third = TravelPreferences(pace: TravelPace.relaxed);

    await store.save(first);

    // Park the second save at the seam, then queue a third save behind it.
    preferences.blockKey(_platformDocKey);
    final secondSave = store.save(second);
    await preferences.nextStartOf(_platformDocKey);
    final thirdSave = store.save(third);
    await pumpEventQueue();

    // Only the first save has committed; the queued ones have not applied.
    expect(store.value, first);
    final midDisk = await preferences.diskSnapshot();
    expect(midDisk[_platformDocKey], jsonEncode(first.toJson()));

    preferences.releaseKey(_platformDocKey);
    await secondSave;
    await thirdSave;

    // Commits are whole documents: doc + timestamp pairs in call order, the
    // last save wins, and the device timestamp always matches the stored one.
    final disk = await preferences.diskSnapshot();
    expect(disk[_platformDocKey], jsonEncode(third.toJson()));
    expect(store.value, third);
    expect(store.deviceUpdatedAt, disk[_platformTimestampKey] as String?);
    expect(preferences.operations, <String>[
      'set:$_platformDocKey',
      'set:$_platformTimestampKey',
      'set:$_platformDocKey',
      'set:$_platformTimestampKey',
      'set:$_platformDocKey',
      'set:$_platformTimestampKey',
    ]);
  });

  test('a failed persisted save throws without uploading and keeps saving', () async {
    final preferences = _GatedSharedPreferencesStore();
    SharedPreferencesStorePlatform.instance = preferences;
    final store = TravelPreferencesStore();
    final remote = _MemoryRemote(account: const TravelPreferences(), revision: 2);

    // Adoption lands the account defaults locally (no local document yet).
    await store.connectAccount(remote);
    expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
    expect(preferences.operations, <String>[
      'set:$_platformDocKey',
      'set:$_platformTimestampKey',
    ]);

    // The very next document write fails at the platform seam.
    preferences.failNextKey(_platformDocKey);
    const rejected = TravelPreferences(interests: {TravelInterest.localFood});
    await expectLater(store.save(rejected), throwsA(isA<StateError>()));

    // The failed save never reached the server and never applied its value.
    expect(remote.putCalls, isEmpty);
    expect(store.value, const TravelPreferences());
    expect(preferences.operations, <String>[
      'set:$_platformDocKey',
      'set:$_platformTimestampKey',
    ]);

    // The storage chain is intact: the next save commits and uploads.
    const accepted = TravelPreferences(interests: {TravelInterest.history});
    await store.save(accepted);

    expect(store.value, accepted);
    expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
    expect(remote.putCalls, <TravelPreferences>[accepted]);
    expect(remote.account, accepted);
    expect(remote.lastExpectedRevision, 2);
  });

  test('a save superseded by clear at the seam head discards itself', () async {
    final preferences = _GatedSharedPreferencesStore();
    SharedPreferencesStorePlatform.instance = preferences;
    final store = TravelPreferencesStore();
    const next = TravelPreferences(interests: {TravelInterest.localFood});

    // No await between the two calls: the save's critical section has not
    // started when clear() bumps the clear generation synchronously.
    final saveFuture = store.save(next);
    final clearFuture = store.clear();
    await saveFuture;
    await clearFuture;

    // The save discarded itself at the section head — only the clear's two
    // removes ever reach the platform, and nothing is written or uploaded.
    expect(preferences.operations, <String>[
      'remove:$_platformDocKey',
      'remove:$_platformTimestampKey',
    ]);
    expect(store.value, const TravelPreferences());
    expect(store.hasLocalDocument, isFalse);
    expect(store.deviceUpdatedAt, isNull);
    expect(store.syncStatus, TravelPreferencesSyncStatus.localOnly);
    final disk = await preferences.diskSnapshot();
    expect(disk, isEmpty);
  });
}

class _MemoryRemote implements TravelPreferencesRemote {
  _MemoryRemote({
    this.account,
    this.revision = 0,
    this.updatedAt = '2026-09-02T00:00:00Z',
  });

  TravelPreferences? account;
  int revision;
  int? lastExpectedRevision;
  final List<TravelPreferences> putCalls = <TravelPreferences>[];
  final String updatedAt;

  @override
  Future<TravelPreferencesRemoteDocument?> get() async {
    final value = account;
    if (value == null) return null;
    return TravelPreferencesRemoteDocument(
      preferences: value,
      revision: revision,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<TravelPreferencesRemoteDocument> put({
    required TravelPreferences preferences,
    required int expectedRevision,
  }) async {
    putCalls.add(preferences);
    lastExpectedRevision = expectedRevision;
    if (expectedRevision != revision) throw StateError('revision conflict');
    account = preferences;
    revision += 1;
    return TravelPreferencesRemoteDocument(
      preferences: preferences,
      revision: revision,
      updatedAt: '2026-09-02T00:01:00Z',
    );
  }
}

/// In-memory store platform that gates the real `setValue`/`remove` seam the
/// `SharedPreferences` legacy path actually calls, so tests can park a write
/// mid-flight exactly where the platform mutation happens.
class _GatedSharedPreferencesStore extends InMemorySharedPreferencesStore {
  _GatedSharedPreferencesStore() : super.empty();

  final List<String> operations = <String>[];
  final Map<String, Completer<void>> _gates = <String, Completer<void>>{};
  final Map<String, Completer<void>> _started = <String, Completer<void>>{};
  String? _failKey;

  void blockKey(String key) => _gates.putIfAbsent(key, Completer<void>.new);

  void releaseKey(String key) {
    final gate = _gates.remove(key);
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  void failNextKey(String key) => _failKey = key;

  /// Resolves once the first mutation of [key] has reached the seam (and is
  /// parked there if a gate is installed).
  Future<void> nextStartOf(String key) =>
      _started.putIfAbsent(key, Completer<void>.new).future;

  void _markStarted(String key) {
    final started = _started.putIfAbsent(key, Completer<void>.new);
    if (!started.isCompleted) {
      started.complete();
    }
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    _markStarted(key);
    final gate = _gates[key];
    if (gate != null) {
      await gate.future;
    }
    if (_failKey == key) {
      _failKey = null;
      throw StateError('storage failed for $key');
    }
    final result = await super.setValue(valueType, key, value);
    operations.add('set:$key');
    return result;
  }

  @override
  Future<bool> remove(String key) async {
    _markStarted(key);
    final gate = _gates[key];
    if (gate != null) {
      await gate.future;
    }
    final result = await super.remove(key);
    operations.add('remove:$key');
    return result;
  }

  /// Reads the persisted (prefixed) key/value pairs straight from the store.
  Future<Map<String, Object>> diskSnapshot() => getAll();
}
