import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/features/settings/data/privacy_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PrivacySettingsStore.instance.resetForTesting();
  });
  await testMain();
}
