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
      final gateway = FakeAuthGateway(authenticated: true);
      final accountApi = FakeAccountApi(me: me);
      final controller = LalaAuthController(
        config: enabledConfig,
        gateway: gateway,
        accountApi: accountApi,
      );

      await controller.initialize();

      expect(controller.state.status, LalaAuthStatus.signedIn);
      expect(controller.state.me, same(me));
      expect(accountApi.getMeCalls, 1);
    });

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
      final gateway = FakeAuthGateway();
      final controller = LalaAuthController(
        config: enabledConfig,
        gateway: gateway,
        accountApi: FakeAccountApi(me: me),
      );
      await controller.initialize();

      await controller.signIn();

      expect(gateway.signInCalls, 1);
      expect(controller.state.status, LalaAuthStatus.signedIn);
      expect(controller.state.me, same(me));
    });

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
    this.signInError,
    this.signOutError,
    List<String?> tokens = const [],
  }) : _tokens = List<String?>.from(tokens);

  bool authenticated;
  final Object? signInError;
  final Object? signOutError;
  final List<String?> _tokens;
  int isAuthenticatedCalls = 0;
  int signInCalls = 0;
  int signOutCalls = 0;
  final List<String> accessTokenResources = [];

  @override
  Future<bool> get isAuthenticated async {
    isAuthenticatedCalls += 1;
    return authenticated;
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
    authenticated = false;
    if (signOutError != null) {
      throw signOutError!;
    }
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
  Future<String?> accessToken(String resource) async => null;

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async {}
}

class FakeAccountApi implements LalaAccountApi {
  FakeAccountApi({this.me, this.deleteError});

  final LalaMe? me;
  final Object? deleteError;
  int getMeCalls = 0;
  final List<String> deleteConfirmations = [];

  @override
  Future<LalaMe> getMe() async {
    getMeCalls += 1;
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
