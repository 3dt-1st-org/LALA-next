import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/core/config/app_config.dart';

void main() {
  // String.fromEnvironment is a compile-time constant, so dart-define override
  // behavior can only be proven by compiling the test binary with the value
  // baked in. test/verification/override_test.sh compiles this file twice —
  // once with no override (static public fallback) and once with an explicit
  // LALA_API_BASE_URL — and this single data-driven test asserts the value the
  // compiler wired into config.baseUri in each compilation.
  group('LalaAppConfig.fromEnvironment compiled dart-define contract', () {
    test('baseUri equals the dart-define compiled into the test', () {
      final config = const LalaAppConfig.fromEnvironment();
      const String expectedBaseUri = String.fromEnvironment(
        'TEST_EXPECTED_API_BASE_URL',
        defaultValue: 'https://api.lala-next.cloud',
      );
      expect(
        config.baseUri,
        expectedBaseUri,
        reason:
            'config.baseUri must equal the dart-define compiled into this test',
      );
    });

    // NAVER_MAP_CLIENT_ID has no static default, so an iOS build that forgets
    // the dart-define silently leaves the key empty and the map degrades to the
    // honest unavailable state with no build-time signal. This compiled assertion
    // proves the dart-define flows into config.naverMapClientId; the
    // verification script also compiles the default (no-define → empty) case.
    test('naverMapClientId equals the dart-define compiled into the test', () {
      final config = const LalaAppConfig.fromEnvironment();
      const String expectedKey = String.fromEnvironment(
        'TEST_EXPECTED_NAVER_MAP_CLIENT_ID',
        defaultValue: '',
      );
      expect(
        config.naverMapClientId,
        expectedKey,
        reason:
            'config.naverMapClientId must equal the NAVER_MAP_CLIENT_ID '
            'dart-define compiled into this test',
      );
    });
  });

  // The defaults below are not wired to LALA_API_BASE_URL, so they hold under
  // every dart-define compilation and never assert a specific base URI value.
  group('LalaAppConfig.fromEnvironment static defaults', () {
    test('location and search parameters keep their static defaults', () {
      final config = const LalaAppConfig.fromEnvironment();
      expect(config.lat, 37.2636);
      expect(config.lng, 127.0286);
      expect(config.radiusM, 3000);
      expect(config.placeLimit, 60);
      expect(config.category, 'all');
      expect(config.lang, 'ko');
      expect(config.requireLocationStartConfirmation, isFalse);
    });

    // bearerToken and apiKey are real secrets with no dart-define wiring, so they
    // stay empty under every compilation. naverMapClientId is also empty by
    // default but IS dart-define-wired; its empty-vs-overridden boundary is
    // proven by the compiled test above, so it is not re-asserted here (the
    // override compilation deliberately sets it to a non-empty placeholder).
    test('credential fields default to empty (no bundled secrets)', () {
      final config = const LalaAppConfig.fromEnvironment();
      expect(config.bearerToken, isEmpty);
      expect(config.apiKey, isEmpty);
    });

    test('base URI is always an absolute http(s) URI', () {
      final config = const LalaAppConfig.fromEnvironment();
      expect(config.baseUri, isNotEmpty);
      expect(
        Uri.tryParse(config.baseUri)?.isAbsolute,
        isTrue,
        reason: 'baseUri must parse as an absolute URI under any dart-define',
      );
    });
  });

  // Unit helpers below manually construct LalaAppConfig to exercise value-object
  // behavior (hasAuth, copyWith). They do NOT read String.fromEnvironment and
  // therefore do not prove dart-define override behavior; that contract is
  // covered exclusively by the compiled-define test above.
  group('LalaAppConfig value-object behavior', () {
    test('hasAuth returns true when bearer token or API key is provided', () {
      final configWithBearer = const LalaAppConfig(
        baseUri: 'https://api.lala-next.cloud',
        bearerToken: 'test-token',
      );
      final configWithApiKey = const LalaAppConfig(
        baseUri: 'https://api.lala-next.cloud',
        // Non-secret test fixture exercising the apiKey branch of hasAuth.
        apiKey: 'test-key', // pragma: allowlist secret
      );
      final configNoAuth = const LalaAppConfig(
        baseUri: 'https://api.lala-next.cloud',
      );

      expect(configWithBearer.hasAuth, isTrue);
      expect(configWithApiKey.hasAuth, isTrue);
      expect(configNoAuth.hasAuth, isFalse);
    });

    test('copyWith creates new instance with overridden values', () {
      final config = const LalaAppConfig(
        baseUri: 'https://api.lala-next.cloud',
        lat: 37.5,
        lng: 127.1,
      );

      final copied = config.copyWith(
        baseUri: 'http://127.0.0.1:8080',
        lat: 38.0,
      );

      expect(copied.baseUri, 'http://127.0.0.1:8080');
      expect(copied.lat, 38.0);
      expect(copied.lng, 127.1); // Original value preserved.
      expect(
        config.baseUri,
        'https://api.lala-next.cloud',
      ); // Original unchanged.
    });
  });
}
