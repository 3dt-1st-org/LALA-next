import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';

const String kTravelPreferencesStorageKey = 'lala.travel_preferences.v1';

typedef SharedPreferencesFactory = Future<SharedPreferences> Function();

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

  TravelPreferences get value => _value;
  bool get isLoaded => _loaded;

  Future<void> ensureLoaded() => _loadFuture ??= _load();

  Future<void> _load() async {
    try {
      final preferences = await _preferencesFactory();
      final raw = preferences.getString(kTravelPreferencesStorageKey);
      if (raw != null) {
        _value = TravelPreferences.fromJson(jsonDecode(raw));
      }
    } on Object {
      _value = const TravelPreferences();
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> save(TravelPreferences next) async {
    final preferences = await _preferencesFactory();
    await preferences.setString(
      kTravelPreferencesStorageKey,
      jsonEncode(next.toJson()),
    );
    _value = next;
    _loaded = true;
    notifyListeners();
  }

  Future<void> clear() async {
    final preferences = await _preferencesFactory();
    await preferences.remove(kTravelPreferencesStorageKey);
    _value = const TravelPreferences();
    _loaded = true;
    notifyListeners();
  }
}
