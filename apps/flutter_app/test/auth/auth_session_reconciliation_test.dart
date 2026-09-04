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

  test(
    'cold-start isAuthenticated read failure recovers to a guest-usable state',
    () async {
      final gateway = _SessionGateway(
        authenticatedError: StateError('keychain restore leaked-detail'),
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
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.profile, isNull);
      expect(controller.state.me, isNull);
      // The probe short-circuits before audience validation or any sync.
      expect(gateway.validatedResources, isEmpty);
      expect(gateway.profileReads, 0);
      expect(accountApi.getMeCalls, 0);

      // Recovery must not wedge sign-in: the next user-initiated attempt on
      // healthy storage completes normally (and replaces the stale storage).
      gateway.authenticatedError = null;
      await controller.signIn();

      expect(gateway.signInCalls, 1);
      expect(controller.state.status, LalaAuthStatus.signedIn);
      expect(controller.state.accountSyncStatus, LalaAccountSyncStatus.ready);
      expect(controller.state.me, same(me));
      expect(accountApi.getMeCalls, 1);
    },
  );

  test(
    'cold-start stored-session validation failure recovers to a guest state',
    () async {
      final gateway = _SessionGateway(
        authenticated: true,
        sessionError: StateError('jwt audience check leaked-detail'),
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
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.profile, isNull);
      expect(controller.state.me, isNull);
      expect(gateway.validatedResources, [config.apiAudience]);
      expect(gateway.profileReads, 0);
      expect(accountApi.getMeCalls, 0);
    },
  );

  test(
    'sign-in probe failure keeps the safe error state, not a silent sign-out',
    () async {
      final gateway = _SessionGateway(
        authenticatedError: StateError('malformed id token leaked-detail'),
      );
      final accountApi = _AccountApi(me: me);
      final controller = LalaAuthController(
        config: config,
        gateway: gateway,
        accountApi: accountApi,
      );
      await controller.initialize();

      await controller.signIn();

      expect(gateway.signInCalls, 1);
      expect(controller.state.status, LalaAuthStatus.error);
      expect(controller.state.authenticated, isFalse);
      expect(
        controller.state.errorMessage,
        LalaAuthController.safeErrorMessage,
      );
      expect(controller.state.errorMessage, isNot(contains('leaked-detail')));
      expect(accountApi.getMeCalls, 0);
    },
  );

  test('valid restored session still syncs through the audience gate', () async {
    final gateway = _SessionGateway(
      authenticated: true,
      profileValue: profile,
      token: 'usable-access-token',
    );
    final accountApi = _AccountApi(me: me);
    final controller = LalaAuthController(
      config: config,
      gateway: gateway,
      accountApi: accountApi,
    );

    await controller.initialize();

    expect(controller.state.status, LalaAuthStatus.signedIn);
    expect(controller.state.authenticated, isTrue);
    expect(controller.state.profile, same(profile));
    expect(controller.state.me, same(me));
    expect(controller.state.accountSyncStatus, LalaAccountSyncStatus.ready);
    expect(gateway.validatedResources, [config.apiAudience]);
    expect(gateway.profileReads, 1);
    expect(accountApi.getMeCalls, 1);
  });

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
    this.authenticatedError,
    this.sessionError,
  });

  bool authenticated;
  final bool sessionValid;
  final LalaAuthProfile? profileValue;
  final String? token;

  /// Thrown by [isAuthenticated] to emulate the Logto SDK reading malformed
  /// restored keychain storage at cold start.
  Object? authenticatedError;

  /// Thrown by [validateSession] to emulate an audience probe failure.
  Object? sessionError;

  int profileReads = 0;
  int signInCalls = 0;
  final List<String> validatedResources = <String>[];

  @override
  Future<bool> get isAuthenticated async {
    if (authenticatedError != null) {
      throw authenticatedError!;
    }
    return authenticated;
  }

  @override
  Future<LalaAuthProfile?> get profile async {
    profileReads += 1;
    return profileValue;
  }

  @override
  Future<bool> validateSession(String resource) async {
    validatedResources.add(resource);
    if (sessionError != null) {
      throw sessionError!;
    }
    return sessionValid;
  }

  @override
  Future<void> signIn() async {
    signInCalls += 1;
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
