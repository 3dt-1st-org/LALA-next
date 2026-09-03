import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kLocationRecommendationsEnabledKey =
    'lala.privacy.v1.locationRecommendationsEnabled';

typedef PrivacyPreferencesFactory = Future<SharedPreferences> Function();

/// Device-level privacy choices shared by settings and the map.
///
/// This store persists only the user's app-level choice. It never infers or
/// persists the operating-system permission state or precise coordinates.
class PrivacySettingsStore extends ChangeNotifier {
  PrivacySettingsStore({PrivacyPreferencesFactory? preferencesFactory})
    : _preferencesFactory = preferencesFactory ?? SharedPreferences.getInstance;

  static final PrivacySettingsStore instance = PrivacySettingsStore();

  final PrivacyPreferencesFactory _preferencesFactory;
  Future<void>? _loadFuture;
  bool _loaded = false;
  bool _locationRecommendationsEnabled = true;

  bool get isLoaded => _loaded;
  bool get locationRecommendationsEnabled => _locationRecommendationsEnabled;

  Future<void> ensureLoaded() => _loadFuture ??= _load();

  Future<void> _load() async {
    try {
      final preferences = await _preferencesFactory();
      _locationRecommendationsEnabled =
          preferences.getBool(kLocationRecommendationsEnabledKey) ?? true;
    } on Object {
      // Failure-safe default preserves the existing first-run behavior. The
      // onboarding flow still asks before requesting a location.
      _locationRecommendationsEnabled = true;
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> setLocationRecommendationsEnabled(bool enabled) async {
    await ensureLoaded();
    if (_locationRecommendationsEnabled == enabled) return;
    _locationRecommendationsEnabled = enabled;
    notifyListeners();
    try {
      final preferences = await _preferencesFactory();
      await preferences.setBool(kLocationRecommendationsEnabledKey, enabled);
    } on Object {
      // The in-memory choice remains authoritative for this session.
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _loadFuture = null;
    _loaded = false;
    _locationRecommendationsEnabled = true;
  }
}
