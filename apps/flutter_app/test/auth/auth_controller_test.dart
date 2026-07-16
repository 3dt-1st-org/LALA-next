import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

void main() {
  const enabledConfig = LalaAuthConfig(
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
    picture: 'https://images.example.com/ada.png',
    emailVerified: true,
  );

  group('LalaAuthController', () {
    test('disabled initialization does not touch auth dependencies', () async {
      final gateway = FakeAuthGateway();
      final accountApi = FakeAccountApi();
      final controller = LalaAuthController(
        config: const LalaAuthConfig(
          endpoint: '',
          appId: '',
          apiAudience: '',
          redirectUri: 'cloud.lalanext.lala://callback',
        ),
        gateway: gateway,
        accountApi: accountApi,
      );

      await controller.initialize();

      expect(controller.state.status, LalaAuthStatus.disabled);
      expect(gateway.isAuthenticatedCalls, 0);
      expect(accountApi.getMeCalls, 0);
    });

    test(
      'pending initialization can finish after controller disposal',
      () async {
        final authenticated = Completer<bool>();
        final controller = LalaAuthController(
          config: enabledConfig,
          gateway: PendingAuthGateway(authenticated.future),
          accountApi: FakeAccountApi(),
        );

        final initialization = controller.initialize();
        controller.dispose();
        authenticated.complete(false);

        await expectLater(initialization, completes);
      },
    );

    test('restored session loads the current account', () async {
      final gateway = FakeAuthGateway(
        authenticated: true,
        profileValue: profile,
      );
      final accountApi = FakeAccountApi(me: me);
      final controller = LalaAuthController(
        config: enabledConfig,
        gateway: gateway,
        accountApi: accountApi,
      );

      await controller.initialize();

      expect(controller.state.status, LalaAuthStatus.signedIn);
      expect(controller.state.authenticated, isTrue);
      expect(controller.state.profile, same(profile));
      expect(controller.state.me, same(me));
      expect(controller.state.accountSyncStatus, LalaAccountSyncStatus.ready);
      expect(accountApi.getMeCalls, 1);
    });

    test('restored session requires a usable Logto API token', () async {
      final gateway = FakeAuthGateway(
        authenticated: true,
        sessionValid: false,
        profileValue: profile,
      );
      final accountApi = FakeAccountApi(me: me);
      final controller = LalaAuthController(
        config: enabledConfig,
        gateway: gateway,
        accountApi: accountApi,
      );

      await controller.initialize();

      expect(controller.state.status, LalaAuthStatus.signedOut);
      expect(controller.state.authenticated, isFalse);
      expect(controller.state.profile, isNull);
      expect(gateway.validateSessionResources, [enabledConfig.apiAudience]);
      expect(gateway.profileCalls, 0);
      expect(accountApi.getMeCalls, 0);
    });

    test(
      'restored session stays signed in when account synchronization fails',
      () async {
        final gateway = FakeAuthGateway(
          authenticated: true,
          profileValue: profile,
        );
        final accountApi = FakeAccountApi(
          getMeError: StateError('api response contained sensitive details'),
        );
        final controller = LalaAuthController(
          config: enabledConfig,
          gateway: gateway,
          accountApi: accountApi,
        );

        await controller.initialize();

        expect(controller.state.status, LalaAuthStatus.signedIn);
        expect(controller.state.authenticated, isTrue);
        expect(controller.state.profile, same(profile));
        expect(controller.state.me, isNull);
        expect(controller.state.accountSyncStatus, LalaAccountSyncStatus.error);
        expect(
          controller.state.errorMessage,
          LalaAuthController.safeAccountSyncErrorMessage,
        );
        expect(
          controller.state.errorMessage,
          isNot(contains('sensitive details')),
        );
      },
    );

    test('signed-out initialization leaves guest mode usable', () async {
      final accountApi = FakeAccountApi(me: me);
      final controller = LalaAuthController(
        config: enabledConfig,
        gateway: FakeAuthGateway(),
        accountApi: accountApi,
      );

      await controller.initialize();

      expect(controller.state.status, LalaAuthStatus.signedOut);
      expect(controller.state.me, isNull);
      expect(accountApi.getMeCalls, 0);
    });

    test('successful sign-in loads the current account', () async {
      final gateway = FakeAuthGateway(profileValue: profile);
      final controller = LalaAuthController(
        config: enabledConfig,
        gateway: gateway,
        accountApi: FakeAccountApi(me: me),
      );
      await controller.initialize();

      await controller.signIn();

      expect(gateway.signInCalls, 1);
      expect(controller.state.status, LalaAuthStatus.signedIn);
      expect(controller.state.authenticated, isTrue);
      expect(controller.state.profile, same(profile));
      expect(controller.state.me, same(me));
    });

    test(
      'completed sign-in stays authenticated when account synchronization fails',
      () async {
        final gateway = FakeAuthGateway(
          profileValue: profile,
          tokens: ['fresh-access-token'],
        );
        final accountApi = FakeAccountApi(
          getMeError: StateError('backend leaked details'),
        );
        final controller = LalaAuthController(
          config: enabledConfig,
          gateway: gateway,
          accountApi: accountApi,
        );
        await controller.initialize();

        await controller.signIn();

        expect(controller.state.status, LalaAuthStatus.signedIn);
        expect(controller.state.authenticated, isTrue);
        expect(controller.state.profile, same(profile));
        expect(controller.state.me, isNull);
        expect(controller.state.accountSyncStatus, LalaAccountSyncStatus.error);
        expect(await controller.accessToken(), 'fresh-access-token');
      },
    );

    test('failed account synchronization can be retried', () async {
      final accountApi = FakeAccountApi(
        me: me,
        getMeError: StateError('temporary failure'),
      );
      final controller = LalaAuthController(
        config: enabledConfig,
        gateway: FakeAuthGateway(profileValue: profile),
        accountApi: accountApi,
      );
      await controller.initialize();
      await controller.signIn();
      expect(controller.state.accountSyncStatus, LalaAccountSyncStatus.error);
      accountApi.getMeError = null;

      await controller.retryAccountSync();

      expect(controller.state.status, LalaAuthStatus.signedIn);
      expect(controller.state.authenticated, isTrue);
      expect(controller.state.me, same(me));
      expect(controller.state.accountSyncStatus, LalaAccountSyncStatus.ready);
      expect(controller.state.errorMessage, isNull);
      expect(accountApi.getMeCalls, 2);
    });

    test(
      'late account synchronization cannot restore a signed-out session',
      () async {
        final gateway = FakeAuthGateway(profileValue: profile);
        final accountApi = PendingAccountApi();
        final controller = LalaAuthController(
          config: enabledConfig,
          gateway: gateway,
          accountApi: accountApi,
        );
        await controller.initialize();

        final signIn = controller.signIn();
        await accountApi.requested;
        expect(
          controller.state.accountSyncStatus,
          LalaAccountSyncStatus.syncing,
        );

        await controller.signOut();
        accountApi.complete(me);
        await signIn;

        expect(controller.state.status, LalaAuthStatus.signedOut);
        expect(controller.state.authenticated, isFalse);
        expect(controller.state.me, isNull);
      },
    );

    test(
      'failed sign-out during account synchronization remains retryable',
      () async {
        final gateway = FakeAuthGateway(
          profileValue: profile,
          signOutError: StateError('hosted logout failed'),
        );
        final accountApi = PendingAccountApi();
        final controller = LalaAuthController(
          config: enabledConfig,
          gateway: gateway,
          accountApi: accountApi,
        );
        await controller.initialize();

        final signIn = controller.signIn();
        await accountApi.requested;

        await controller.signOut();
        accountApi.complete(me);
        await signIn;

        expect(controller.state.status, LalaAuthStatus.error);
        expect(controller.state.authenticated, isTrue);
        expect(controller.state.accountSyncStatus, LalaAccountSyncStatus.error);
        expect(
          controller.state.errorMessage,
          LalaAuthController.safeErrorMessage,
        );

        await controller.retryAccountSync();

        expect(controller.state.status, LalaAuthStatus.signedIn);
        expect(controller.state.me, same(me));
        expect(controller.state.accountSyncStatus, LalaAccountSyncStatus.ready);
      },
    );

    test('failed sign-in exposes only a generic safe error', () async {
      final gateway = FakeAuthGateway(
        signInError: StateError('provider subject sub-secret-token'),
      );
      final controller = LalaAuthController(
        config: enabledConfig,
        gateway: gateway,
        accountApi: FakeAccountApi(me: me),
      );
      await controller.initialize();

      await controller.signIn();

      expect(controller.state.status, LalaAuthStatus.error);
      expect(controller.state.me, isNull);
      expect(
        controller.state.errorMessage,
        LalaAuthController.safeErrorMessage,
      );
      expect(
        controller.state.errorMessage,
        isNot(contains('sub-secret-token')),
      );
    });

    test('access token delegates the configured resource every time', () async {
      final gateway = FakeAuthGateway(tokens: ['token-1', 'token-2']);
      final controller = LalaAuthController(
        config: enabledConfig,
        gateway: gateway,
        accountApi: FakeAccountApi(),
      );

      expect(await controller.accessToken(), 'token-1');
      expect(await controller.accessToken(), 'token-2');
      expect(gateway.accessTokenResources, [
        'https://api.example.com',
        'https://api.example.com',
      ]);
    });

    test(
      'signed-out access token stays null without touching the gateway',
      () async {
        final gateway = FakeAuthGateway(tokens: ['unexpected-token']);
        final controller = LalaAuthController(
          config: enabledConfig,
          gateway: gateway,
          accountApi: FakeAccountApi(),
        );
        await controller.initialize();

        expect(await controller.accessToken(), isNull);
        expect(gateway.accessTokenResources, isEmpty);
      },
    );

    test('sign-out clears the account and returns to guest mode', () async {
      final gateway = FakeAuthGateway(authenticated: true);
      final controller = LalaAuthController(
        config: enabledConfig,
        gateway: gateway,
        accountApi: FakeAccountApi(me: me),
      );
      await controller.initialize();

      await controller.signOut();

      expect(gateway.signOutCalls, 1);
      expect(controller.state.status, LalaAuthStatus.signedOut);
      expect(controller.state.authenticated, isFalse);
      expect(controller.state.profile, isNull);
      expect(controller.state.me, isNull);
    });

    test(
      'account deletion confirms, signs out, and returns to guest mode',
      () async {
        final gateway = FakeAuthGateway(authenticated: true);
        final accountApi = FakeAccountApi(me: me);
        final controller = LalaAuthController(
          config: enabledConfig,
          gateway: gateway,
          accountApi: accountApi,
        );
        await controller.initialize();

        await controller.deleteAccount();

        expect(accountApi.deleteConfirmations, ['delete-my-account']);
        expect(gateway.signOutCalls, 1);
        expect(controller.state.status, LalaAuthStatus.signedOut);
        expect(controller.state.authenticated, isFalse);
        expect(controller.state.profile, isNull);
        expect(controller.state.me, isNull);
      },
    );

    test(
      'failed deletion retains the signed-in account with a safe error',
      () async {
        final gateway = FakeAuthGateway(authenticated: true);
        final accountApi = FakeAccountApi(
          me: me,
          deleteError: StateError('backend leaked details'),
        );
        final controller = LalaAuthController(
          config: enabledConfig,
          gateway: gateway,
          accountApi: accountApi,
        );
        await controller.initialize();

        await controller.deleteAccount();

        expect(gateway.signOutCalls, 0);
        expect(controller.state.status, LalaAuthStatus.error);
        expect(controller.state.me, same(me));
        expect(
          controller.state.errorMessage,
          LalaAuthController.safeErrorMessage,
        );
        expect(controller.state.errorMessage, isNot(contains('backend')));
      },
    );

    test('deleted account stays guest if hosted sign-out fails', () async {
      final gateway = FakeAuthGateway(
        authenticated: true,
        signOutError: StateError('hosted logout cancelled'),
      );
      final accountApi = FakeAccountApi(me: me);
      final controller = LalaAuthController(
        config: enabledConfig,
        gateway: gateway,
        accountApi: accountApi,
      );
      await controller.initialize();

      await controller.deleteAccount();

      expect(accountApi.deleteConfirmations, ['delete-my-account']);
      expect(gateway.signOutCalls, 1);
      expect(controller.state.status, LalaAuthStatus.signedOut);
      expect(controller.state.me, isNull);
    });
  });
}

class FakeAuthGateway implements LalaAuthGateway {
  FakeAuthGateway({
    this.authenticated = false,
    this.sessionValid = true,
    this.profileValue,
    this.profileError,
    this.signInError,
    this.signOutError,
    List<String?> tokens = const [],
  }) : _tokens = List<String?>.from(tokens);

  bool authenticated;
  final bool sessionValid;
  final LalaAuthProfile? profileValue;
  final Object? profileError;
  final Object? signInError;
  final Object? signOutError;
  final List<String?> _tokens;
  int isAuthenticatedCalls = 0;
  int signInCalls = 0;
  int signOutCalls = 0;
  int profileCalls = 0;
  final List<String> accessTokenResources = [];
  final List<String> validateSessionResources = [];

  @override
  Future<bool> get isAuthenticated async {
    isAuthenticatedCalls += 1;
    return authenticated;
  }

  @override
  Future<LalaAuthProfile?> get profile async {
    profileCalls += 1;
    if (profileError != null) {
      throw profileError!;
    }
    return profileValue;
  }

  @override
  Future<void> signIn() async {
    signInCalls += 1;
    if (signInError != null) {
      throw signInError!;
    }
    authenticated = true;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    if (signOutError != null) {
      throw signOutError!;
    }
    authenticated = false;
  }

  @override
  Future<bool> validateSession(String resource) async {
    validateSessionResources.add(resource);
    return sessionValid;
  }

  @override
  Future<String?> accessToken(String resource) async {
    accessTokenResources.add(resource);
    return _tokens.isEmpty ? null : _tokens.removeAt(0);
  }
}

class PendingAuthGateway implements LalaAuthGateway {
  PendingAuthGateway(this._authenticated);

  final Future<bool> _authenticated;

  @override
  Future<bool> get isAuthenticated => _authenticated;

  @override
  Future<LalaAuthProfile?> get profile async => null;

  @override
  Future<bool> validateSession(String resource) async => true;

  @override
  Future<String?> accessToken(String resource) async => null;

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async {}
}

class FakeAccountApi implements LalaAccountApi {
  FakeAccountApi({this.me, this.getMeError, this.deleteError});

  final LalaMe? me;
  Object? getMeError;
  final Object? deleteError;
  int getMeCalls = 0;
  final List<String> deleteConfirmations = [];

  @override
  Future<LalaMe> getMe() async {
    getMeCalls += 1;
    if (getMeError != null) {
      throw getMeError!;
    }
    return me!;
  }

  @override
  Future<void> deleteMe({required String confirmation}) async {
    deleteConfirmations.add(confirmation);
    if (deleteError != null) {
      throw deleteError!;
    }
  }
}

class PendingAccountApi implements LalaAccountApi {
  final Completer<void> _requested = Completer<void>();
  final Completer<LalaMe> _response = Completer<LalaMe>();

  Future<void> get requested => _requested.future;

  void complete(LalaMe me) => _response.complete(me);

  @override
  Future<void> deleteMe({required String confirmation}) async {}

  @override
  Future<LalaMe> getMe() {
    if (!_requested.isCompleted) {
      _requested.complete();
    }
    return _response.future;
  }
}
