import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/onboarding/local_onboarding_page.dart';
import '../features/onboarding/onboarding_state.dart';
import '../features/preferences/data/travel_preferences_store.dart';
import '../features/settings/data/privacy_settings_store.dart';
import '../manual_location_options.dart';
import '../onboarding_screen.dart';

/// Read the old device document once without removing it or replacing newer data.
Future<void> migrateLocalPreferences() async {
  if (OnboardingState.isCompleted) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('lala.preferences.v1');
    if (raw == null || prefs.containsKey(kTravelPreferencesStorageKey)) return;
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> || value['completed'] != true) return;
    final regions = manualLocationOptions.where(
      (region) => region.id == value['region'],
    );
    final speed = value['speed'];
    await completeLocalOnboarding(
      OnboardingResult(
        isGuest: true,
        country: value['country'] is String
            ? value['country'] as String
            : 'OTHER',
        language: value['locale'] is String ? value['locale'] as String : 'en',
        travelStyles: value['styles'] is List
            ? (value['styles'] as List).whereType<String>().toList()
            : [],
        travelMode: value['mode'] == 'plan_trip' ? 'plan_trip' : 'explore_now',
        autoDocent: value['auto'] == true,
        playbackSpeed:
            speed is num && [0.8, 1.0, 1.2].contains(speed.toDouble())
            ? speed.toDouble()
            : 1.0,
        requestLocation: false,
        destination: regions.isEmpty ? null : regions.first,
      ),
    );
    await PrivacySettingsStore.instance.setLocationRecommendationsEnabled(
      value['location'] == true,
    );
  } on Object {
    // Keep the original document for retry/recovery; a storage failure must not prevent startup.
  }
}
