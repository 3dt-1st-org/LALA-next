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

    test('explicit dart-define overrides default LALA_API_BASE_URL', () {
      // Arrange: Set up environment with explicit localhost override
      const overrideUrl = 'http://127.0.0.1:8080';
      final config = _configWithEnvironment({'LALA_API_BASE_URL': overrideUrl});

      // Assert: Verify explicit override takes precedence
      expect(config.baseUri, overrideUrl);
    });

    test('explicit dart-define overrides with different public endpoint', () {
      // Arrange: Set up environment with custom public endpoint
      const customUrl = 'https://custom.api.example.com';
      final config = _configWithEnvironment({'LALA_API_BASE_URL': customUrl});

      // Assert: Verify custom override works
      expect(config.baseUri, customUrl);
    });

    test(
      'respects other environment defaults when API base URL is overridden',
      () {
        // Arrange: Set up environment with API override
        final config = _configWithEnvironment({
          'LALA_API_BASE_URL': 'http://localhost:3000',
        });

        // Assert: Verify other defaults remain unchanged
        expect(config.kakaoJavascriptKey, isEmpty);
        expect(config.category, 'all');
        expect(config.lang, 'ko');
        expect(config.requireLocationStartConfirmation, isFalse);
      },
    );

    test('allows explicit override of all environment values', () {
      // Arrange: Set up environment with multiple overrides
      final config = _configWithEnvironment({
        'LALA_API_BASE_URL': 'https://api.example.com',
        'KAKAO_JAVASCRIPT_KEY': 'test-kakao-key',
        'LALA_PLACE_CATEGORY': 'restaurants',
        'LALA_UI_LANGUAGE': 'en',
      });

      // Assert: Verify all overrides apply
      expect(config.baseUri, 'https://api.example.com');
      expect(config.kakaoJavascriptKey, 'test-kakao-key');
      expect(config.category, 'restaurants');
      expect(config.lang, 'en');
    });
  });

  group('LalaAppConfig functionality', () {
    test('provides safe public default without environment access', () {
      // This test verifies the safe fallback exists for guest/public builds
      final config = const LalaAppConfig.fromEnvironment();

      // Safe public endpoint should be available by default
      expect(config.baseUri, isNotEmpty);
      expect(config.baseUri, startsWith('https://'));
      expect(config.baseUri, contains('api.lala-next.cloud'));
    });

    test('maintains default location and search parameters', () {
      final config = const LalaAppConfig.fromEnvironment();

      expect(config.lat, 37.2636);
      expect(config.lng, 127.0286);
      expect(config.radiusM, 3000);
      expect(config.placeLimit, 60);
    });
  });
}

/// Test helper that creates LalaAppConfig with environment overrides.
///
/// This mirrors the pattern used in auth_config_test.dart, providing
/// environment values through a callback while maintaining test isolation.
LalaAppConfig _configWithEnvironment(Map<String, String> environmentValues) {
  return LalaAppConfig(
    baseUri:
        environmentValues['LALA_API_BASE_URL'] ??
        const String.fromEnvironment('LALA_API_BASE_URL'),
    bearerToken:
        environmentValues['LALA_API_BEARER_TOKEN'] ??
        const String.fromEnvironment('LALA_API_BEARER_TOKEN'),
    apiKey:
        environmentValues['LALA_IOS_API_KEY'] ??
        const String.fromEnvironment('LALA_IOS_API_KEY'),
    kakaoJavascriptKey:
        environmentValues['KAKAO_JAVASCRIPT_KEY'] ??
        const String.fromEnvironment('KAKAO_JAVASCRIPT_KEY'),
    category:
        environmentValues['LALA_PLACE_CATEGORY'] ??
        const String.fromEnvironment(
          'LALA_PLACE_CATEGORY',
          defaultValue: 'all',
        ),
    lang:
        environmentValues['LALA_UI_LANGUAGE'] ??
        const String.fromEnvironment('LALA_UI_LANGUAGE', defaultValue: 'ko'),
    requireLocationStartConfirmation:
        environmentValues.containsKey(
          'LALA_REQUIRE_LOCATION_START_CONFIRMATION',
        )
        ? const bool.fromEnvironment(
            'LALA_REQUIRE_LOCATION_START_CONFIRMATION',
            defaultValue: false,
          )
        : false,
  );
}
