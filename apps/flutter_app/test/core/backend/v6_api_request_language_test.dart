// V6 foreign-visitor UX: API language contract tests (contract §10).
//
// The API is a two-language surface (normalize_language → ko/en). Visitor
// locales must request `en` so server-composed strings (place reasons, docent
// scripts, Local Signals bodies) never surface Korean on a JA/ZH screen, while
// ko keeps requesting `ko`.
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/core/config/app_config.dart';

void main() {
  group('LalaAppConfig.lang round-trips the UI locale', () {
    test('accepts every canonical V6 language', () {
      for (final code in <String>[
        'ko',
        'en',
        'ja',
        'zh-Hans',
        'zh-Hant',
      ]) {
        final config = LalaAppConfig(baseUri: 'http://api.test', lang: code);
        expect(config.lang, code, reason: code);
        expect(config.copyWith(lang: code).lang, code);
      }
    });

    test('default remains ko (existing behavior)', () {
      expect(const LalaAppConfig(baseUri: 'http://api.test').lang, 'ko');
    });
  });
}
