import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';

void main() {
  group('LalaAuthConfig.fromEnvironment', () {
    test(
      'normalizes platform-specific Web values and selects the Web app ID',
      () {
        final config = _config(
          isWeb: true,
          values: {
            'LOGTO_ENDPOINT': '  https://auth.example.com  ',
            'LOGTO_WEB_APP_ID': '  web-client-id  ',
            'LOGTO_NATIVE_APP_ID': 'native-client-id',
            'LOGTO_API_AUDIENCE': '  https://api.example.com  ',
            'LOGTO_WEB_REDIRECT_URI':
                '  https://app.example.com/auth-callback.html  ',
            'LOGTO_WEB_POST_LOGOUT_REDIRECT_URI':
                '  https://app.example.com/signed-out  ',
          },
        );

        expect(config.endpoint, 'https://auth.example.com');
        expect(config.appId, 'web-client-id');
        expect(config.apiAudience, 'https://api.example.com');
        expect(
          config.redirectUri,
          'https://app.example.com/auth-callback.html',
        );
        expect(
          config.postLogoutRedirectUri,
          'https://app.example.com/signed-out',
        );
        expect(config.enabled, isTrue);
      },
    );

    test('selects the native app ID and native callback default', () {
      final config = _config(
        isWeb: false,
        values: _requiredValues(
          webAppId: 'web-client-id',
          nativeAppId: '  native-client-id  ',
        ),
      );

      expect(config.appId, 'native-client-id');
      expect(config.redirectUri, 'cloud.lalanext.lala://callback');
      expect(config.enabled, isTrue);
    });

    test('uses the current Web origin when redirect override is blank', () {
      final config = _config(
        isWeb: true,
        baseUri: Uri.parse('https://app.example.com/map?lang=ko'),
        values: {
          ..._requiredValues(webAppId: 'web-client-id'),
          'LOGTO_REDIRECT_URI': '   ',
          'LOGTO_POST_LOGOUT_REDIRECT_URI': '   ',
        },
      );

      expect(config.redirectUri, 'https://app.example.com/auth-callback.html');
      expect(config.postLogoutRedirectUri, isNull);
      expect(config.enabled, isTrue);
    });

    test('rejects malformed Web redirect URIs', () {
      final malformed = _config(
        isWeb: true,
        values: {
          ..._requiredValues(webAppId: 'web-client-id'),
          'LOGTO_REDIRECT_URI': 'not a uri',
        },
      );

      expect(malformed.enabled, isFalse);
    });

    test('ignores a legacy redirect that belongs to the other platform', () {
      final webConfig = _config(
        isWeb: true,
        baseUri: Uri.parse('https://app.example.com/start'),
        values: {
          ..._requiredValues(webAppId: 'web-client-id'),
          'LOGTO_REDIRECT_URI': 'cloud.lalanext.lala://callback',
        },
      );
      final nativeConfig = _config(
        isWeb: false,
        values: {
          ..._requiredValues(nativeAppId: 'native-client-id'),
          'LOGTO_REDIRECT_URI': 'https://app.example.com/auth-callback.html',
          'LOGTO_POST_LOGOUT_REDIRECT_URI':
              'https://app.example.com/signed-out',
        },
      );

      expect(
        webConfig.redirectUri,
        'https://app.example.com/auth-callback.html',
      );
      expect(webConfig.enabled, isTrue);
      expect(nativeConfig.redirectUri, 'cloud.lalanext.lala://callback');
      expect(nativeConfig.postLogoutRedirectUri, isNull);
      expect(nativeConfig.enabled, isTrue);
    });

    test('rejects an invalid platform-specific post-logout URI', () {
      final config = _config(
        isWeb: true,
        values: {
          ..._requiredValues(webAppId: 'web-client-id'),
          'LOGTO_WEB_POST_LOGOUT_REDIRECT_URI':
              'cloud.lalanext.lala://signed-out',
        },
      );

      expect(config.enabled, isFalse);
    });

    test('does not fall back to the other platform app ID', () {
      final webConfig = _config(
        isWeb: true,
        values: _requiredValues(nativeAppId: 'native-client-id'),
      );
      final nativeConfig = _config(
        isWeb: false,
        values: _requiredValues(webAppId: 'web-client-id'),
      );

      expect(webConfig.appId, isEmpty);
      expect(webConfig.enabled, isFalse);
      expect(nativeConfig.appId, isEmpty);
      expect(nativeConfig.enabled, isFalse);
    });
  });
}

LalaAuthConfig _config({
  required bool isWeb,
  required Map<String, String> values,
  Uri? baseUri,
}) {
  return LalaAuthConfig.fromEnvironment(
    isWeb: isWeb,
    baseUri: baseUri ?? Uri.parse('https://default.example.com/start'),
    environmentValue: (name) => values[name] ?? '',
  );
}

Map<String, String> _requiredValues({
  String webAppId = '',
  String nativeAppId = '',
}) {
  return {
    'LOGTO_ENDPOINT': 'https://auth.example.com',
    'LOGTO_WEB_APP_ID': webAppId,
    'LOGTO_NATIVE_APP_ID': nativeAppId,
    'LOGTO_API_AUDIENCE': 'https://api.example.com',
  };
}
