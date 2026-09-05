import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_remote.dart';

const String kTravelPreferencesStorageKey = 'lala.travel_preferences.v1';
const String kTravelPreferencesUpdatedAtKey =
    'lala.travel_preferences.v1.updated_at';

typedef SharedPreferencesFactory = Future<SharedPreferences> Function();

enum TravelPreferencesSyncStatus {
  localOnly,
  checking,
  serverEmpty,
  synced,
  conflict,
  error,
}

/// Failure-safe local preferences store.
///
/// Guest and signed-in users can keep editing when account sync is unavailable.
/// A future server repository can observe [value] without changing the local
/// contract or placing preferences in Logto claims.
class TravelPreferencesStore extends ChangeNotifier {
  TravelPreferencesStore({SharedPreferencesFactory? preferencesFactory})
    : _preferencesFactory = preferencesFactory ?? SharedPreferences.getInstance;

  static final TravelPreferencesStore instance = TravelPreferencesStore();

  final SharedPreferencesFactory _preferencesFactory;
  TravelPreferences _value = const TravelPreferences();
  Future<void>? _loadFuture;
  bool _loaded = false;
  bool _hasLocalDocument = false;
  TravelPreferencesRemote? _remote;
  TravelPreferencesRemoteDocument? _serverDocument;
  String? _deviceUpdatedAt;
  TravelPreferencesSyncStatus _syncStatus =
      TravelPreferencesSyncStatus.localOnly;
  int _syncEpoch = 0;

  /// Generation of the newest committed local document state. Every committed
  /// `_saveLocal`/`_load` apply/`clear` bumps it, so a *derived* write (server
  /// adoption, initial-load apply, use-account echo) that was suspended at the
  /// storage seam can detect that a newer document already landed and discard
  /// itself instead of overwriting it.
  int _localWriteGeneration = 0;

  /// Generation of the newest `clear()`. Only a deliberate document deletion
  /// supersedes an in-flight *user* edit; ordinary writes must not discard
  /// explicit user intent, and a cleared document must not be resurrected.
  int _clearGeneration = 0;

  TravelPreferences get value => _value;
  bool get isLoaded => _loaded;
  bool get hasLocalDocument => _hasLocalDocument;
  TravelPreferencesSyncStatus get syncStatus => _syncStatus;
  int? get serverRevision => _serverDocument?.revision;
  TravelPreferences? get accountPreferences => _serverDocument?.preferences;
  String? get accountUpdatedAt => _serverDocument?.updatedAt;
  String? get deviceUpdatedAt => _deviceUpdatedAt;
  bool get accountConnected => _remote != null;

  /// Zone-safe load gate (CP1). When already loaded, hand out a *fresh*
  /// completed future created in the caller's zone — awaiting a future that
  /// completed inside an earlier Flutter test zone can hang that later zone's
  /// fake async (the cached `_loadFuture` belongs to a dead zone). Concurrent
  /// first-load deduplication (`_loadFuture ??=`) is unchanged.
  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    // The stored document is only authoritative if no newer local write
    // committed while the storage read was in flight; otherwise applying it
    // would resurrect stale storage over a fresh in-memory edit.
    final generation = _localWriteGeneration;
    try {
      final preferences = await _preferencesFactory();
      final raw = preferences.getString(kTravelPreferencesStorageKey);
      if (raw != null && _localWriteGeneration == generation) {
        _value = TravelPreferences.fromJson(jsonDecode(raw));
        _hasLocalDocument = true;
        _deviceUpdatedAt = preferences.getString(
          kTravelPreferencesUpdatedAtKey,
        );
        _localWriteGeneration += 1;
      }
    } on Object {
      if (_localWriteGeneration == generation) {
        _value = const TravelPreferences();
        _hasLocalDocument = false;
      }
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> save(TravelPreferences next) async {
    // Fence the save to the account scope it was made under. If the account
    // disconnected or switched while the local write was in flight, the edit
    // stays local — it must never silently upload to a different account.
    final epoch = _syncEpoch;
    // An explicit edit survives every interleaving except a newer deliberate
    // document deletion, which must not be resurrected by a pre-clear write.
    final clearGeneration = _clearGeneration;
    await _saveLocal(next, requireClearGeneration: clearGeneration);
    if (epoch != _syncEpoch) {
      _reconcileAfterOutOfBandLocalWrite();
      return;
    }
    if (_syncStatus == TravelPreferencesSyncStatus.synced &&
        _serverDocument != null &&
        _remote != null) {
      await _saveToAccount(next, expectedRevision: _serverDocument!.revision);
    }
  }

  /// Re-derives an honest sync status after a local write raced an
  /// account-scope change. A `synced` pairing can no longer be true once the
  /// device copy differs from the account document, so surface the conflict
  /// instead of leaving a stale synced claim that the next save would trust.
  void _reconcileAfterOutOfBandLocalWrite() {
    if (_remote == null) {
      return;
    }
    final server = _serverDocument;
    if (server == null) {
      return;
    }
    if (_syncStatus == TravelPreferencesSyncStatus.synced &&
        _value != server.preferences) {
      _syncStatus = TravelPreferencesSyncStatus.conflict;
      notifyListeners();
    }
  }

  /// Commits [next] unless a newer committed state superseded this write's
  /// basis while it was suspended at the storage seam. Derived writes pass
  /// [requireGeneration] (discard when any newer write landed); explicit user
  /// edits pass [requireClearGeneration] (discard only when a newer `clear()`
  /// landed). Returns whether the write actually committed.
  Future<bool> _saveLocal(
    TravelPreferences next, {
    String? updatedAt,
    int? requireGeneration,
    int? requireClearGeneration,
  }) async {
    final preferences = await _preferencesFactory();
    if (requireGeneration != null &&
        requireGeneration != _localWriteGeneration) {
      return false;
    }
    if (requireClearGeneration != null &&
        requireClearGeneration != _clearGeneration) {
      return false;
    }
    final resolvedUpdatedAt =
        updatedAt ?? DateTime.now().toUtc().toIso8601String();
    await preferences.setString(
      kTravelPreferencesStorageKey,
      jsonEncode(next.toJson()),
    );
    await preferences.setString(
      kTravelPreferencesUpdatedAtKey,
      resolvedUpdatedAt,
    );
    _value = next;
    _deviceUpdatedAt = resolvedUpdatedAt;
    _loaded = true;
    _hasLocalDocument = true;
    _localWriteGeneration += 1;
    notifyListeners();
    return true;
  }

  Future<void> connectAccount(TravelPreferencesRemote remote) {
    _remote = remote;
    final epoch = ++_syncEpoch;
    _syncStatus = TravelPreferencesSyncStatus.checking;
    notifyListeners();
    return _synchronizeAccount(epoch, remote);
  }

  void disconnectAccount() {
    _syncEpoch += 1;
    _remote = null;
    _serverDocument = null;
    _syncStatus = TravelPreferencesSyncStatus.localOnly;
    notifyListeners();
  }

  Future<void> retryAccountSync() async {
    final remote = _remote;
    if (remote == null || _syncStatus == TravelPreferencesSyncStatus.checking) {
      return;
    }
    await connectAccount(remote);
  }

  Future<void> useAccountPreferences() async {
    final server = _serverDocument;
    if (server == null) {
      return;
    }
    // The explicit user choice lands locally, but a `synced` claim is only
    // honest while the same account scope is still connected, and the chosen
    // document must not overwrite a newer committed local edit that landed
    // while this choice was in flight.
    final epoch = _syncEpoch;
    final generation = _localWriteGeneration;
    final landed = await _saveLocal(
      server.preferences,
      updatedAt: server.updatedAt,
      requireGeneration: generation,
    );
    if (!landed || epoch != _syncEpoch) {
      _reconcileAfterOutOfBandLocalWrite();
      return;
    }
    _syncStatus = TravelPreferencesSyncStatus.synced;
    notifyListeners();
  }

  Future<void> saveDevicePreferencesToAccount() async {
    final remote = _remote;
    if (remote == null || _syncStatus == TravelPreferencesSyncStatus.checking) {
      return;
    }
    await _saveToAccount(
      _value,
      expectedRevision: _serverDocument?.revision ?? 0,
    );
  }

  Future<void> _synchronizeAccount(
    int epoch,
    TravelPreferencesRemote remote,
  ) async {
    await ensureLoaded();
    // Adoption may only land while it is still the newest local write; a
    // stale account's adoption must never overwrite a successor account's
    // adopted value or a committed user edit.
    final generation = _localWriteGeneration;
    try {
      final document = await remote.get();
      if (epoch != _syncEpoch) {
        return;
      }
      _serverDocument = document;
      if (document != null && !_hasLocalDocument) {
        await _saveLocal(
          document.preferences,
          updatedAt: document.updatedAt,
          requireGeneration: generation,
        );
        if (epoch != _syncEpoch) {
          return;
        }
      }
      // Derive the pairing from the *current* device copy: a discarded
      // adoption (superseded write) or a racing user edit still compares
      // honestly instead of assuming the adopted document equals `_value`.
      _syncStatus = document == null
          ? TravelPreferencesSyncStatus.serverEmpty
          : (_value == document.preferences
                ? TravelPreferencesSyncStatus.synced
                : TravelPreferencesSyncStatus.conflict);
    } on Object {
      if (epoch != _syncEpoch) {
        return;
      }
      _syncStatus = TravelPreferencesSyncStatus.error;
    }
    if (epoch == _syncEpoch) {
      notifyListeners();
    }
  }

  Future<void> _saveToAccount(
    TravelPreferences next, {
    required int expectedRevision,
  }) async {
    final remote = _remote;
    if (remote == null) {
      return;
    }
    final epoch = _syncEpoch;
    _syncStatus = TravelPreferencesSyncStatus.checking;
    notifyListeners();
    try {
      final saved = await remote.put(
        preferences: next,
        expectedRevision: expectedRevision,
      );
      if (epoch != _syncEpoch) {
        return;
      }
      _serverDocument = saved;
      // A user edit may have landed locally while the PUT was in flight (it
      // correctly skipped uploading because this PUT held `checking`).
      // Claiming `synced` would pair the next save with a revision that does
      // not include that edit, so derive the pairing from the current value.
      _syncStatus = saved.preferences == _value
          ? TravelPreferencesSyncStatus.synced
          : TravelPreferencesSyncStatus.conflict;
    } on Object {
      if (epoch != _syncEpoch) {
        return;
      }
      try {
        final document = await remote.get();
        if (epoch != _syncEpoch) {
          return;
        }
        _serverDocument = document;
        _syncStatus = document == null
            ? TravelPreferencesSyncStatus.error
            : TravelPreferencesSyncStatus.conflict;
      } on Object {
        if (epoch == _syncEpoch) {
          _syncStatus = TravelPreferencesSyncStatus.error;
        }
      }
    }
    if (epoch == _syncEpoch) {
      notifyListeners();
    }
  }

  Future<void> clear() async {
    // Deletion is the newest local intent: fence pending remote work, discard
    // pre-clear local writes still parked at the storage seam (both derived
    // adoption/echo writes and explicit edits), and only then remove storage.
    _syncEpoch += 1;
    _clearGeneration += 1;
    _localWriteGeneration += 1;
    final preferences = await _preferencesFactory();
    await preferences.remove(kTravelPreferencesStorageKey);
    await preferences.remove(kTravelPreferencesUpdatedAtKey);
    _value = const TravelPreferences();
    _deviceUpdatedAt = null;
    _loaded = true;
    _hasLocalDocument = false;
    // The device copy is gone but the account document (if any) still exists;
    // report the honest pairing instead of a stale claim.
    _syncStatus = _statusAfterLocalReset();
    notifyListeners();
  }

  TravelPreferencesSyncStatus _statusAfterLocalReset() {
    if (_remote == null) {
      return TravelPreferencesSyncStatus.localOnly;
    }
    final server = _serverDocument;
    if (server == null) {
      return TravelPreferencesSyncStatus.serverEmpty;
    }
    return _value == server.preferences
        ? TravelPreferencesSyncStatus.synced
        : TravelPreferencesSyncStatus.conflict;
  }
}
