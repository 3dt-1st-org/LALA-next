import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/features/settings/data/privacy_settings_store.dart';

void main() {
  test('location recommendation choice survives a store restart', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final first = PrivacySettingsStore();
    await first.ensureLoaded();

    expect(first.locationRecommendationsEnabled, isTrue);
    await first.setLocationRecommendationsEnabled(false);

    final restored = PrivacySettingsStore();
    await restored.ensureLoaded();
    expect(restored.locationRecommendationsEnabled, isFalse);
  });
}
