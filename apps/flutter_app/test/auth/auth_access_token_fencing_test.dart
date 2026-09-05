import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';

// P1 transport-fencing coverage: a token request that begins under one
// account session must never hand back a token belonging to a later session.
// This is the seam that keeps a delayed account request (for example a
// preferences PUT racing sign-out or an A -> B switch) from being authorized
// as the wrong account.
void main() {
  const config = LalaAuthConfig(
    endpoint: 'https://auth.example.com',
    appId: 'public-client-id',
    apiAudience: 'https://api.example.com',
    redirectUri: 'cloud.lalanext.lala://callback',
  );
  const me = LalaMe(
    userId: 'account-123',
    createdAt: '2026-07-10T00:00:00Z',
    authenticated: true,
  );

  test(
    'an in-flight token resolution is fenced by sign-out instead of '
    'returning the old session token',
    () async {
      final gateway = _SwitchableGateway()..staticToken = 'account-a-token';
      final controller = LalaAuthController(
        config: config,
        gateway: gateway,
        accountApi: _AccountApi(me: me),
      );
      await controller.initialize();
      expect(controller.state.status, LalaAuthStatus.signedIn);

      gateway.holdNextAccessToken();
      final tokenFuture = controller.accessToken();
      await controller.signOut();
      expect(controller.state.status, LalaAuthStatus.signedOut);

      gateway.resolveHeldAccessToken('account-a-token');
      // The request began under account A's session; sign-out invalidated that
      // session, so it must resolve to no token rather than authorize a
      // pending write after logout.
      expect(await tokenFuture, isNull);
      expect(await controller.accessToken(), isNull);
    },
  );

  test(
    'a stale token request never receives the next account\'s token after an '
    'A -> B switch',
    () async {
      final gateway = _SwitchableGateway()..staticToken = 'account-a-token';
      final controller = LalaAuthController(
        config: config,
        gateway: gateway,
        accountApi: _AccountApi(me: me),
      );
      await controller.initialize();
      expect(controller.state.status, LalaAuthStatus.signedIn);

      gateway.holdNextAccessToken();
      final staleTokenFuture = controller.accessToken();
      await controller.signOut();
      gateway.staticToken = 'account-b-token';
      await controller.signIn();
      expect(controller.state.status, LalaAuthStatus.signedIn);
      expect(controller.state.accountSyncStatus, LalaAccountSyncStatus.ready);

      gateway.resolveHeldAccessToken('account-b-token');
      // The SDK now holds account B's session; resolving the old request with
      // B's token would authorize an A-era write against B's account.
      expect(await staleTokenFuture, isNull);
      // A fresh request under the established session still resolves.
      expect(await controller.accessToken(), 'account-b-token');
    },
  );

  test(
    'a token request begun after a session is established resolves normally '
    'across async suspension',
    () async {
      final gateway = _SwitchableGateway()..staticToken = 'account-a-token';
      final controller = LalaAuthController(
        config: config,
        gateway: gateway,
        accountApi: _AccountApi(me: me),
      );
      await controller.initialize();

      gateway.holdNextAccessToken();
      final tokenFuture = controller.accessToken();
      // Ordinary async work interleaves, but no session invalidation occurs.
      await Future<void>.value();
      await Future<void>.value();
      gateway.resolveHeldAccessToken('account-a-token');

      expect(await tokenFuture, 'account-a-token');
    },
  );
}

/// Gateway whose access-token resolution is explicitly controllable so tests
/// can suspend one request across a full session switch.
class _SwitchableGateway implements LalaSessionGateway {
  bool authenticated = true;
  String? staticToken;
  Completer<String?>? _heldAccessToken;

  void holdNextAccessToken() => _heldAccessToken = Completer<String?>();

  void resolveHeldAccessToken(String? token) =>
      _heldAccessToken!.complete(token);

  @override
  Future<bool> get isAuthenticated async => authenticated;

  @override
  Future<LalaAuthProfile?> get profile async => null;

  @override
  Future<bool> validateSession(String resource) async => true;

  @override
  Future<String?> accessToken(String resource) async {
    final held = _heldAccessToken;
    if (held != null) {
      return held.future;
    }
    return staticToken;
  }

  @override
  Future<void> signIn() async {
    authenticated = true;
  }

  @override
  Future<void> signOut() async {
    authenticated = false;
  }
}

class _AccountApi implements LalaAccountApi {
  _AccountApi({required this.me});

  final LalaMe me;

  @override
  Future<LalaMe> getMe() async => me;

  @override
  Future<void> deleteMe({required String confirmation}) async {}
}
