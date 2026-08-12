// App-wiring regression: locks the Logto/guest coexistence invariant at the
// LalaHomePage boundary — the seam NOT covered by auth_controller_test.dart
// (which proves the controller in isolation) or auth_config_test.dart (which
// proves config parsing).
//
// The invariant: LalaHomePage wires the auth controller's `accessToken` tear-off
// into the main backend config's `accessTokenProvider` such that:
//  (a) a disabled / not-configured Logto controller resolves to null — the
//      contest/guest build wires a null token provider so no bearer token is
//      attached; and
//  (b) an authenticated Logto controller resolves to the SDK access token.
//
// The provider is a method tear-off, so it reflects the controller's live state
// at call time; the assertions invoke the wired provider after initialization
// settles to prove the value the main backend (LalaApiBackend → LalaApiClient)
// would attach to outgoing requests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/features/home/home_page.dart';

void main() {
  const disabledConfig = LalaAuthConfig(
    endpoint: '',
    appId: '',
    apiAudience: '',
    redirectUri: 'cloud.lalanext.lala://callback',
  );
  const enabledConfig = LalaAuthConfig(
    endpoint: 'https://auth.example.com',
    appId: 'native-client-id',
    apiAudience: 'https://api.example.com',
    redirectUri: 'cloud.lalanext.lala://callback',
  );
  const me = LalaMe(
    userId: 'account-123',
    createdAt: '2026-07-10T00:00:00Z',
    authenticated: true,
  );

  group('LalaHomePage auth token-provider wiring', () {
    testWidgets(
      'disabled Logto config keeps the guest token provider null '
      '(contest/guest build attaches no bearer token)',
      (tester) async {
        final configs = <LalaAppConfig>[];
        await tester.pumpWidget(
          MaterialApp(
            home: LalaHomePage(
              backendFactory: (config) {
                configs.add(config);
                return _RecordingBackend();
              },
              initialConfig: const LalaAppConfig(
                baseUri: 'http://api.test',
                // Skip the location/refresh post-frame path so the assertion is
                // about the auth wiring, not recommendation loading.
                requireLocationStartConfirmation: true,
              ),
              locationProvider: _DenyLocationProvider(),
              recommendationRecoveryDelays: const <Duration>[],
              authControllerFactory: (_) => LalaAuthController(
                config: disabledConfig,
                gateway: _StubAuthGateway(),
                accountApi: _StubAccountApi(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));

        // The home page built a backend from a config carrying the controller's
        // accessToken tear-off; calling it must resolve to null for a disabled
        // controller — the guest/contest path.
        expect(configs, isNotEmpty);
        final provider = configs.last.accessTokenProvider;
        expect(provider, isNotNull);
        expect(await provider!(), isNull);

        // Dispose Home/auth state so no controller keeps the test process alive.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));
      },
    );

    testWidgets(
      'signed-in Logto controller attaches the SDK token via the provider',
      (tester) async {
        final configs = <LalaAppConfig>[];
        await tester.pumpWidget(
          MaterialApp(
            home: LalaHomePage(
              backendFactory: (config) {
                configs.add(config);
                return _RecordingBackend();
              },
              initialConfig: const LalaAppConfig(
                baseUri: 'http://api.test',
                requireLocationStartConfirmation: true,
              ),
              locationProvider: _DenyLocationProvider(),
              recommendationRecoveryDelays: const <Duration>[],
              authControllerFactory: (_) => LalaAuthController(
                config: enabledConfig,
                gateway: _StubAuthGateway(
                  authenticated: true,
                  token: 'logto-access-token',
                ),
                accountApi: _StubAccountApi(me: me),
              ),
            ),
          ),
        );
        await tester.pump();
        // Let _initializeAuth settle: the controller moves busy → signedIn via
        // the fake gateway/account (both resolve on the microtask queue).
        await tester.pump(const Duration(milliseconds: 50));

        expect(configs, isNotEmpty);
        final provider = configs.last.accessTokenProvider;
        expect(provider, isNotNull);
        // The wired provider reflects the signed-in state and returns the Logto
        // token the main backend attaches to outgoing requests.
        expect(await provider!(), 'logto-access-token');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));
      },
    );
  });
}

/// LalaBackend that only records its construction; no methods are exercised
/// because the location/refresh path is skipped. Keeps the test focused on the
/// auth wiring without standing up recommendation data.
class _RecordingBackend implements LalaBackend {
  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'auth wiring test does not call ${invocation.memberName}',
  );
}

class _DenyLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() async =>
      const LalaLocationResult.denied();
}

class _StubAuthGateway implements LalaAuthGateway {
  _StubAuthGateway({this.authenticated = false, this.token});

  final bool authenticated;
  final String? token;

  @override
  Future<bool> get isAuthenticated async => authenticated;

  @override
  Future<String?> accessToken(String resource) async => token;

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async {}
}

class _StubAccountApi implements LalaAccountApi {
  _StubAccountApi({this.me});

  final LalaMe? me;

  @override
  Future<LalaMe> getMe() async => me!;

  @override
  Future<void> deleteMe({required String confirmation}) async {}
}
