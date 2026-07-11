import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:logto_dart_sdk/logto_dart_sdk.dart';

void main() {
  const config = LalaAuthConfig(
    endpoint: 'https://auth.example.com',
    appId: 'native-client-id',
    apiAudience: 'https://api.example.com',
    redirectUri: 'cloud.lalanext.lala://callback',
    postLogoutRedirectUri: 'cloud.lalanext.lala://signed-out',
  );

  group('LogtoAuthGateway', () {
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

    test('does not ask the SDK for a token while signed out', () async {
      final client = FakeLogtoClient(authenticated: false);
      final gateway = LogtoAuthGateway(client, config: config);

      expect(await gateway.accessToken(config.apiAudience), isNull);
      expect(client.accessTokenResources, isEmpty);
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
  final bool clearSessionOnSignOut;
  final Object? signOutError;
  final List<String> signInRedirects = [];
  final List<String> signOutRedirects = [];
  final List<String?> accessTokenResources = [];

  @override
  Future<bool> get isAuthenticated async => authenticated;

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
