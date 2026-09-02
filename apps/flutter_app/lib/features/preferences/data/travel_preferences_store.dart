import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_remote.dart';

const String kTravelPreferencesStorageKey = 'lala.travel_preferences.v1';

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
  TravelPreferencesSyncStatus _syncStatus =
      TravelPreferencesSyncStatus.localOnly;
  int _syncEpoch = 0;

  TravelPreferences get value => _value;
  bool get isLoaded => _loaded;
  bool get hasLocalDocument => _hasLocalDocument;
  TravelPreferencesSyncStatus get syncStatus => _syncStatus;
  int? get serverRevision => _serverDocument?.revision;

  Future<void> ensureLoaded() => _loadFuture ??= _load();

  Future<void> _load() async {
    try {
      final preferences = await _preferencesFactory();
      final raw = preferences.getString(kTravelPreferencesStorageKey);
      if (raw != null) {
        _value = TravelPreferences.fromJson(jsonDecode(raw));
        _hasLocalDocument = true;
      }
    } on Object {
      _value = const TravelPreferences();
      _hasLocalDocument = false;
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> save(TravelPreferences next) async {
    await _saveLocal(next);
    if (_syncStatus == TravelPreferencesSyncStatus.synced &&
        _serverDocument != null &&
        _remote != null) {
      await _saveToAccount(next, expectedRevision: _serverDocument!.revision);
    }
  }

  Future<void> _saveLocal(TravelPreferences next) async {
    final preferences = await _preferencesFactory();
    await preferences.setString(
      kTravelPreferencesStorageKey,
      jsonEncode(next.toJson()),
    );
    _value = next;
    _loaded = true;
    _hasLocalDocument = true;
    notifyListeners();
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
    await _saveLocal(server.preferences);
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
    try {
      final document = await remote.get();
      if (epoch != _syncEpoch) {
        return;
      }
      _serverDocument = document;
      if (document == null) {
        _syncStatus = TravelPreferencesSyncStatus.serverEmpty;
      } else if (!_hasLocalDocument) {
        await _saveLocal(document.preferences);
        if (epoch != _syncEpoch) {
          return;
        }
        _syncStatus = TravelPreferencesSyncStatus.synced;
      } else if (_value == document.preferences) {
        _syncStatus = TravelPreferencesSyncStatus.synced;
      } else {
        _syncStatus = TravelPreferencesSyncStatus.conflict;
      }
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
      _syncStatus = TravelPreferencesSyncStatus.synced;
    } on Object {
      if (epoch != _syncEpoch) {
        return;
      }
      try {
        _serverDocument = await remote.get();
        if (epoch != _syncEpoch) {
          return;
        }
        _syncStatus = _serverDocument == null
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
    final preferences = await _preferencesFactory();
    await preferences.remove(kTravelPreferencesStorageKey);
    _value = const TravelPreferences();
    _loaded = true;
    _hasLocalDocument = false;
    notifyListeners();
  }
}
