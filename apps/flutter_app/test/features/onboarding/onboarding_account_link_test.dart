import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/onboarding/presentation/pages/account_link_page.dart';
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

  setUp(() {
    OnboardingState.detachPersistence();
    OnboardingState.reset();
    OnboardingState.selectLanguage('ko');
  });

  tearDown(OnboardingState.reset);

  testWidgets('guest escape completes onboarding without signing in', (
    tester,
  ) async {
    final gateway = _OnboardingGateway();
    final controller = LalaAuthController(
      config: config,
      gateway: gateway,
      accountApi: _OnboardingAccountApi(me: me),
    );
    await controller.initialize();
    await _pumpAccountRouter(tester, controller);

    expect(find.text('게스트로 둘러보기'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding-account-skip')));
    await tester.pumpAndSettle();

    expect(find.text('map-ready'), findsOneWidget);
    expect(OnboardingState.isCompleted, isTrue);
    expect(gateway.signInCalls, 0);
  });

  testWidgets('successful sign-in sync completes onboarding', (tester) async {
    final gateway = _OnboardingGateway(
      profileValue: const LalaAuthProfile(
        name: 'Ada',
        email: 'ada@example.com',
      ),
    );
    final controller = LalaAuthController(
      config: config,
      gateway: gateway,
      accountApi: _OnboardingAccountApi(me: me),
    );
    await controller.initialize();
    await _pumpAccountRouter(tester, controller);

    await tester.tap(find.byKey(const Key('onboarding-account-primary')));
    await tester.pumpAndSettle();

    expect(gateway.signInCalls, 1);
    expect(controller.state.authenticated, isTrue);
    expect(controller.state.accountSyncStatus, LalaAccountSyncStatus.ready);
    expect(find.text('map-ready'), findsOneWidget);
    expect(OnboardingState.isCompleted, isTrue);
  });

  testWidgets('account sync failure remains recoverable and skippable', (
    tester,
  ) async {
    final gateway = _OnboardingGateway();
    final controller = LalaAuthController(
      config: config,
      gateway: gateway,
      accountApi: _OnboardingAccountApi(
        getMeError: StateError('backend details'),
      ),
    );
    await controller.initialize();
    await _pumpAccountRouter(tester, controller);

    await tester.tap(find.byKey(const Key('onboarding-account-primary')));
    await tester.pumpAndSettle();

    expect(controller.state.authenticated, isTrue);
    expect(controller.state.accountSyncStatus, LalaAccountSyncStatus.error);
    expect(find.text('계정 연결 다시 시도'), findsOneWidget);
    expect(OnboardingState.isCompleted, isFalse);

    await tester.tap(find.byKey(const Key('onboarding-account-skip')));
    await tester.pumpAndSettle();
    expect(find.text('map-ready'), findsOneWidget);
    expect(OnboardingState.isCompleted, isTrue);
  });

  testWidgets(
    'cold-start stored-session failure shows the guest page, not a sign-in failure',
    (tester) async {
      final gateway = _OnboardingGateway(
        authenticatedError: StateError('keychain restore leaked-detail'),
      );
      final controller = LalaAuthController(
        config: config,
        gateway: gateway,
        accountApi: _OnboardingAccountApi(me: me),
      );

      await controller.initialize();
      await _pumpAccountRouter(tester, controller);

      expect(controller.state.status, LalaAuthStatus.signedOut);
      // The reproduced S-06 defect rendered this failure copy before the user
      // ever attempted sign-in; a cold-start recovery must not.
      expect(
        find.text(
          '로그인을 완료하지 못했어요. 다시 시도하거나 게스트로 계속할 수 있어요.',
        ),
        findsNothing,
      );
      expect(find.text('로그인'), findsOneWidget);
      expect(find.text('게스트로 둘러보기'), findsOneWidget);
      expect(gateway.signInCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('guest escape stays reachable at 320dp and 200 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = LalaAuthController(
      config: config,
      gateway: _OnboardingGateway(),
      accountApi: _OnboardingAccountApi(me: me),
    );
    await controller.initialize();
    await _pumpAccountRouter(
      tester,
      controller,
      textScaler: const TextScaler.linear(2),
    );

    expect(find.byKey(const Key('onboarding-account-primary')), findsOneWidget);
    expect(find.byKey(const Key('onboarding-account-skip')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpAccountRouter(
  WidgetTester tester,
  LalaAuthController controller, {
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final router = GoRouter(
    initialLocation: '/account',
    routes: <RouteBase>[
      GoRoute(
        path: '/account',
        builder: (_, _) =>
            OnboardingAccountLinkPage(authController: controller),
      ),
      GoRoute(
        path: '/map-route',
        builder: (_, _) => const Scaffold(body: Text('map-ready')),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
    ),
  );
  await tester.pump();
}

class _OnboardingGateway implements LalaSessionGateway {
  _OnboardingGateway({this.profileValue, this.authenticatedError});

  bool authenticated = false;
  final LalaAuthProfile? profileValue;

  /// Thrown by [isAuthenticated] to emulate the Logto SDK reading malformed
  /// restored keychain storage at cold start.
  final Object? authenticatedError;
  int signInCalls = 0;

  @override
  Future<bool> get isAuthenticated async {
    if (authenticatedError != null) {
      throw authenticatedError!;
    }
    return authenticated;
  }

  @override
  Future<LalaAuthProfile?> get profile async => profileValue;

  @override
  Future<bool> validateSession(String resource) async => authenticated;

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
  Future<String?> accessToken(String resource) async =>
      authenticated ? 'access-token' : null;
}

class _OnboardingAccountApi implements LalaAccountApi {
  _OnboardingAccountApi({this.me, this.getMeError});

  final LalaMe? me;
  final Object? getMeError;

  @override
  Future<LalaMe> getMe() async {
    if (getMeError != null) {
      throw getMeError!;
    }
    return me!;
  }

  @override
  Future<void> deleteMe({required String confirmation}) async {}
}
