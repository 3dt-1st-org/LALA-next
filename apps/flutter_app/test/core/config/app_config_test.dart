import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/core/config/app_config.dart';

void main() {
  group('LalaAppConfig.fromEnvironment', () {
    test(
      'uses public API endpoint as safe default when no dart-define provided',
      () {
        // Act: Test default behavior without explicit environment override
        final config = const LalaAppConfig.fromEnvironment();

        // Assert: Verify safe public default
        expect(config.baseUri, 'https://api.lala-next.cloud');
      },
    );

    test('maintains default location and search parameters', () {
      // This test verifies the safe fallback exists for guest/public builds
      final config = const LalaAppConfig.fromEnvironment();

      // Check if we're in override testing mode
      const bool testingOverride = bool.fromEnvironment('TEST_OVERRIDE_LOCALHOST', defaultValue: false) ||
                                  bool.fromEnvironment('TEST_OVERRIDE_CUSTOM', defaultValue: false);

      if (testingOverride) {
        // Skip this test during override testing since baseUri will be different
        return;
      }

      // Safe public endpoint should be available by default
      expect(config.baseUri, isNotEmpty);
      expect(config.baseUri, startsWith('https://'));
      expect(config.baseUri, contains('api.lala-next.cloud'));

      // Default location and search parameters should be preserved
      expect(config.lat, 37.2636);
      expect(config.lng, 127.0286);
      expect(config.radiusM, 3000);
      expect(config.placeLimit, 60);
    });

    test(
      'respects other environment defaults when no explicit overrides provided',
      () {
        // Test that other defaults work correctly when only baseUri is changed
        final config = const LalaAppConfig.fromEnvironment();

        // Check if we're in override testing mode
        const bool testingOverride = bool.fromEnvironment('TEST_OVERRIDE_LOCALHOST', defaultValue: false) ||
                                    bool.fromEnvironment('TEST_OVERRIDE_CUSTOM', defaultValue: false);

        if (testingOverride) {
          // Skip this test during override testing
          return;
        }

        expect(config.kakaoJavascriptKey, isEmpty);
        expect(config.category, 'all');
        expect(config.lang, 'ko');
        expect(config.requireLocationStartConfirmation, isFalse);
      },
    );
  });

  group('LalaAppConfig override behavior', () {
    test(
      'verifies compile-time localhost override when TEST_OVERRIDE_LOCALHOST is defined',
      () {
        // This test is only run when TEST_OVERRIDE_LOCALHOST is defined at compile time
        // It verifies that String.fromEnvironment actually uses the dart-define value
        // Run with: --dart-define LALA_API_BASE_URL=http://127.0.0.1:8080 --dart-define TEST_OVERRIDE_LOCALHOST=true
        final config = const LalaAppConfig.fromEnvironment();

        // When TEST_OVERRIDE_LOCALHOST is true, we expect localhost override
        const bool testOverrideLocalhost = bool.fromEnvironment(
          'TEST_OVERRIDE_LOCALHOST',
          defaultValue: false,
        );
        if (testOverrideLocalhost) {
          expect(config.baseUri, 'http://127.0.0.1:8080');
        } else {
          // Normal default behavior
          expect(config.baseUri, 'https://api.lala-next.cloud');
        }
      },
    );

    test(
      'verifies compile-time custom override when TEST_OVERRIDE_CUSTOM is defined',
      () {
        // This test is only run when TEST_OVERRIDE_CUSTOM is defined at compile time
        // It verifies that String.fromEnvironment actually uses the dart-define value
        // Run with: --dart-define LALA_API_BASE_URL=https://custom.api.example.com --dart-define TEST_OVERRIDE_CUSTOM=true
        final config = const LalaAppConfig.fromEnvironment();

        // When TEST_OVERRIDE_CUSTOM is true, we expect custom override
        const bool testOverrideCustom = bool.fromEnvironment(
          'TEST_OVERRIDE_CUSTOM',
          defaultValue: false,
        );
        if (testOverrideCustom) {
          expect(config.baseUri, 'https://custom.api.example.com');
        } else {
          // Normal default behavior
          expect(config.baseUri, 'https://api.lala-next.cloud');
        }
      },
    );

    test('documents compile-time dart-define override mechanism', () {
      // This test documents how String.fromEnvironment works:
      // When LALA_API_BASE_URL is provided at compile time via --dart-define,
      // String.fromEnvironment returns that value instead of the default.
      //
      // To test actual override behavior, run:
      // flutter test test/core/config/app_config_test.dart \
      //   --dart-define LALA_API_BASE_URL=http://127.0.0.1:8080 \
      //   --dart-define TEST_EXPECTED_API_BASE_URL=http://127.0.0.1:8080 \
      //   --dart-define TEST_OVERRIDE_LOCALHOST=true
      //
      // See test/verification/override_test.sh for automated verification.

      // Check if we're in override testing mode
      const bool testingOverride = bool.fromEnvironment('TEST_OVERRIDE_LOCALHOST', defaultValue: false) ||
                                  bool.fromEnvironment('TEST_OVERRIDE_CUSTOM', defaultValue: false);

      if (testingOverride) {
        // During override testing, verify the override mechanism works
        final config = const LalaAppConfig.fromEnvironment();
        expect(config.baseUri, isNotEmpty);
        expect(config.baseUri, startsWith('http'));
      } else {
        // Default behavior without dart-define
        final defaultConfig = const LalaAppConfig.fromEnvironment();
        expect(defaultConfig.baseUri, 'https://api.lala-next.cloud');
      }

      // The override mechanism is provided by Flutter's String.fromEnvironment:
      // - If LALA_API_BASE_URL is defined at compile time, that value is used
      // - If not defined, the defaultValue ('https://api.lala-next.cloud') is used
      // - Explicit dart-define values always override the default
      //
      // This contract is verified separately via compile-time override tests.
    });
  });

  group('LalaAppConfig functionality', () {
    test('provides safe public default for guest builds', () {
      // Verify the safe public API default exists for guest/public builds
      final config = const LalaAppConfig.fromEnvironment();

      // Check if we're in override testing mode
      const bool testingOverride = bool.fromEnvironment('TEST_OVERRIDE_LOCALHOST', defaultValue: false) ||
                                  bool.fromEnvironment('TEST_OVERRIDE_CUSTOM', defaultValue: false);

      if (testingOverride) {
        // During override testing, the baseUri will be different
        expect(config.baseUri, isNotEmpty);
        expect(config.baseUri, startsWith('http'));
      } else {
        // Normal default behavior
        expect(config.baseUri, isNotEmpty);
        expect(config.baseUri, startsWith('https://'));
        expect(config.baseUri, contains('api.lala-next.cloud'));
      }
    });

    test('supports explicit dart-define for local development', () {
      // Document that explicit dart-define values override the default:
      // flutter run --dart-define LALA_API_BASE_URL=http://127.0.0.1:8080
      // This is verified separately via compile-time override mechanism.
      final config = const LalaAppConfig.fromEnvironment();

      // Check if we're in override testing mode
      const bool testingOverride = bool.fromEnvironment('TEST_OVERRIDE_LOCALHOST', defaultValue: false) ||
                                  bool.fromEnvironment('TEST_OVERRIDE_CUSTOM', defaultValue: false);

      if (testingOverride) {
        // During override testing, verify the override works
        expect(config.baseUri, isNotEmpty);
        expect(config.baseUri, startsWith('http'));
      } else {
        // Default should point to public API
        expect(config.baseUri, 'https://api.lala-next.cloud');
      }

      // Local development override example (documented, not executed here):
      // When LALA_API_BASE_URL=http://127.0.0.1:8080 is provided as dart-define,
      // config.baseUri would return 'http://127.0.0.1:8080' instead.
    });

    test('hasAuth returns true when bearer token or API key is provided', () {
      // Test authentication detection logic
      final configWithBearer = const LalaAppConfig(
        baseUri: 'https://api.lala-next.cloud',
        bearerToken: 'test-token',
      );
      final configWithApiKey = const LalaAppConfig(
        baseUri: 'https://api.lala-next.cloud',
        apiKey: 'test-key',
      );
      final configNoAuth = const LalaAppConfig(
        baseUri: 'https://api.lala-next.cloud',
      );

      expect(configWithBearer.hasAuth, isTrue);
      expect(configWithApiKey.hasAuth, isTrue);
      expect(configNoAuth.hasAuth, isFalse);
    });

    test('copyWith creates new instance with overridden values', () {
      // Test immutability and copyWith functionality
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
      expect(copied.lng, 127.1); // Original value preserved
      expect(
        config.baseUri,
        'https://api.lala-next.cloud',
      ); // Original unchanged
    });
  });
}
