import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

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
  const profile = LalaAuthProfile(
    name: 'Ada Lovelace',
    email: 'ada@example.com',
    emailVerified: true,
  );

  test('restored session requires a usable API-audience token', () async {
    final gateway = _SessionGateway(
      authenticated: true,
      sessionValid: false,
      profileValue: profile,
    );
    final accountApi = _AccountApi(me: me);
    final controller = LalaAuthController(
      config: config,
      gateway: gateway,
      accountApi: accountApi,
    );

    await controller.initialize();

    expect(controller.state.status, LalaAuthStatus.signedOut);
    expect(controller.state.authenticated, isFalse);
    expect(gateway.validatedResources, [config.apiAudience]);
    expect(gateway.profileReads, 0);
    expect(accountApi.getMeCalls, 0);
  });

  test(
    'account sync failure preserves the provider session and profile',
    () async {
      final gateway = _SessionGateway(
        authenticated: true,
        profileValue: profile,
        token: 'usable-access-token',
      );
      final controller = LalaAuthController(
        config: config,
        gateway: gateway,
        accountApi: _AccountApi(
          getMeError: StateError('private backend detail'),
        ),
      );

      await controller.initialize();

      expect(controller.state.status, LalaAuthStatus.signedIn);
      expect(controller.state.authenticated, isTrue);
      expect(controller.state.profile, same(profile));
      expect(controller.state.me, isNull);
      expect(controller.state.accountSyncStatus, LalaAccountSyncStatus.error);
      expect(controller.state.errorMessage, isNot(contains('private')));
      expect(await controller.accessToken(), 'usable-access-token');
    },
  );

  test('failed account sync can be retried without hosted sign-in', () async {
    final accountApi = _AccountApi(
      me: me,
      getMeError: StateError('temporary failure'),
    );
    final controller = LalaAuthController(
      config: config,
      gateway: _SessionGateway(authenticated: true, profileValue: profile),
      accountApi: accountApi,
    );
    await controller.initialize();
    accountApi.getMeError = null;

    await controller.retryAccountSync();

    expect(controller.state.accountSyncStatus, LalaAccountSyncStatus.ready);
    expect(controller.state.me, same(me));
    expect(accountApi.getMeCalls, 2);
  });

  test('new sign-in also requires a usable API-audience token', () async {
    final gateway = _SessionGateway(sessionValid: false);
    final accountApi = _AccountApi(me: me);
    final controller = LalaAuthController(
      config: config,
      gateway: gateway,
      accountApi: accountApi,
    );
    await controller.initialize();

    await controller.signIn();

    expect(controller.state.status, LalaAuthStatus.error);
    expect(controller.state.authenticated, isFalse);
    expect(gateway.validatedResources, [config.apiAudience]);
    expect(accountApi.getMeCalls, 0);
  });

  test('late account response cannot restore a signed-out session', () async {
    final gateway = _SessionGateway(profileValue: profile);
    final accountApi = _PendingAccountApi();
    final controller = LalaAuthController(
      config: config,
      gateway: gateway,
      accountApi: accountApi,
    );
    await controller.initialize();

    final signIn = controller.signIn();
    await accountApi.requested;
    await controller.signOut();
    accountApi.complete(me);
    await signIn;

    expect(controller.state.status, LalaAuthStatus.signedOut);
    expect(controller.state.authenticated, isFalse);
    expect(controller.state.me, isNull);
  });
}

class _SessionGateway implements LalaSessionGateway {
  _SessionGateway({
    this.authenticated = false,
    this.sessionValid = true,
    this.profileValue,
    this.token,
  });

  bool authenticated;
  final bool sessionValid;
  final LalaAuthProfile? profileValue;
  final String? token;
  int profileReads = 0;
  final List<String> validatedResources = <String>[];

  @override
  Future<bool> get isAuthenticated async => authenticated;

  @override
  Future<LalaAuthProfile?> get profile async {
    profileReads += 1;
    return profileValue;
  }

  @override
  Future<bool> validateSession(String resource) async {
    validatedResources.add(resource);
    return sessionValid;
  }

  @override
  Future<void> signIn() async {
    authenticated = true;
  }

  @override
  Future<void> signOut() async {
    authenticated = false;
  }

  @override
  Future<String?> accessToken(String resource) async => token;
}

class _AccountApi implements LalaAccountApi {
  _AccountApi({this.me, this.getMeError});

  final LalaMe? me;
  Object? getMeError;
  int getMeCalls = 0;

  @override
  Future<LalaMe> getMe() async {
    getMeCalls += 1;
    if (getMeError != null) {
      throw getMeError!;
    }
    return me!;
  }

  @override
  Future<void> deleteMe({required String confirmation}) async {}
}

class _PendingAccountApi implements LalaAccountApi {
  final Completer<void> _requested = Completer<void>();
  final Completer<LalaMe> _response = Completer<LalaMe>();

  Future<void> get requested => _requested.future;

  void complete(LalaMe me) => _response.complete(me);

  @override
  Future<LalaMe> getMe() {
    if (!_requested.isCompleted) {
      _requested.complete();
    }
    return _response.future;
  }

  @override
  Future<void> deleteMe({required String confirmation}) async {}
}
