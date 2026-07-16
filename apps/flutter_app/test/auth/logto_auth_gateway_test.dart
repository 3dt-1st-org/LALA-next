import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:logto_dart_sdk/logto_dart_sdk.dart';
// ignore: implementation_imports
import 'package:logto_dart_sdk/src/modules/id_token.dart';

void main() {
  const config = LalaAuthConfig(
    endpoint: 'https://auth.example.com',
    appId: 'native-client-id',
    apiAudience: 'https://api.example.com',
    redirectUri: 'cloud.lalanext.lala://callback',
    postLogoutRedirectUri: 'cloud.lalanext.lala://signed-out',
  );

  group('LogtoAuthGateway', () {
    test('SDK configuration requests the API resource and email scope', () {
      final sdkConfig = createLogtoSdkConfig(config);

      expect(sdkConfig.endpoint, config.endpoint);
      expect(sdkConfig.appId, config.appId);
      expect(sdkConfig.resources, [config.apiAudience]);
      expect(sdkConfig.scopes, contains(LogtoUserScope.email.value));
    });

    test('forwards sign-in and access-token values to the SDK', () async {
      final client = FakeLogtoClient(
        authenticated: true,
        accessToken: AccessToken(
          token: 'access-token',
          scope: '',
          expiresAt: DateTime.utc(2030),
        ),
      );
      final gateway = LogtoAuthGateway(client, config: config);

      await gateway.signIn();
      final token = await gateway.accessToken(config.apiAudience);

      expect(client.signInRedirects, [config.redirectUri]);
      expect(client.accessTokenResources, [config.apiAudience]);
      expect(token, 'access-token');
    });

    test('maps normalized profile values from ID token claims', () async {
      final client = FakeLogtoClient(
        authenticated: true,
        idTokenClaimsValue: OpenIdClaims.fromJson({
          'iss': 'https://auth.example.com/oidc',
          'sub': 'user-123',
          'aud': 'native-client-id',
          'exp': 1893456000,
          'iat': 1767225600,
          'name': '  Ada Lovelace  ',
          'email': '  ada@example.com  ',
          'picture': 'https://images.example.com/ada.png',
          'email_verified': true,
        }),
      );
      final gateway = LogtoAuthGateway(client, config: config);

      final profile = await gateway.profile;

      expect(profile?.name, 'Ada Lovelace');
      expect(profile?.email, 'ada@example.com');
      expect(profile?.picture, 'https://images.example.com/ada.png');
      expect(profile?.emailVerified, isTrue);
    });

    test('does not ask the SDK for a token while signed out', () async {
      final client = FakeLogtoClient(authenticated: false);
      final gateway = LogtoAuthGateway(client, config: config);

      expect(await gateway.accessToken(config.apiAudience), isNull);
      expect(client.accessTokenResources, isEmpty);
    });

    test('validates a restored session with an API access token', () async {
      final client = FakeLogtoClient(
        authenticated: true,
        accessToken: AccessToken(
          token: 'access-token',
          scope: '',
          expiresAt: DateTime.utc(2030),
        ),
      );
      final gateway = LogtoAuthGateway(client, config: config);

      expect(await gateway.validateSession(config.apiAudience), isTrue);
      expect(client.accessTokenResources, [config.apiAudience]);
    });

    test(
      'accepts hosted logout cancellation after local session clearing',
      () async {
        final client = FakeLogtoClient(
          authenticated: true,
          clearSessionOnSignOut: true,
          signOutError: StateError('hosted logout cancelled'),
        );
        final gateway = LogtoAuthGateway(client, config: config);

        await expectLater(gateway.signOut(), completes);

        expect(client.signOutRedirects, [config.postLogoutRedirectUri]);
        expect(client.authenticated, isFalse);
      },
    );

    test('rethrows sign-out failures while the SDK session remains', () async {
      final error = StateError('session retained');
      final client = FakeLogtoClient(authenticated: true, signOutError: error);
      final gateway = LogtoAuthGateway(client, config: config);

      await expectLater(gateway.signOut(), throwsA(same(error)));

      expect(client.authenticated, isTrue);
    });
  });
}

class FakeLogtoClient extends LogtoClient {
  FakeLogtoClient({
    required this.authenticated,
    this.accessToken,
    this.idTokenClaimsValue,
    this.clearSessionOnSignOut = false,
    this.signOutError,
  }) : super(
         config: const LogtoConfig(
           endpoint: 'https://auth.example.com',
           appId: 'native-client-id',
         ),
       );

  bool authenticated;
  final AccessToken? accessToken;
  final OpenIdClaims? idTokenClaimsValue;
  final bool clearSessionOnSignOut;
  final Object? signOutError;
  final List<String> signInRedirects = [];
  final List<String> signOutRedirects = [];
  final List<String?> accessTokenResources = [];

  @override
  Future<bool> get isAuthenticated async => authenticated;

  @override
  Future<OpenIdClaims?> get idTokenClaims async => idTokenClaimsValue;

  @override
  Future<void> signIn(
    String redirectUri, {
    InteractionMode? interactionMode,
    String? loginHint,
    String? directSignIn,
    FirstScreen? firstScreen,
    List<IdentifierType>? identifiers,
    Map<String, String>? extraParams,
  }) async {
    signInRedirects.add(redirectUri);
  }

  @override
  Future<AccessToken?> getAccessToken({
    String? resource,
    String? organizationId,
  }) async {
    accessTokenResources.add(resource);
    return accessToken;
  }

  @override
  Future<void> signOut(String redirectUri) async {
    signOutRedirects.add(redirectUri);
    if (clearSessionOnSignOut) {
      authenticated = false;
    }
    if (signOutError != null) {
      throw signOutError!;
    }
  }
}
