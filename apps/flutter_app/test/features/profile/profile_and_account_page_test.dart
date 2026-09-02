import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/profile/presentation/pages/account_page.dart';
import 'package:lala_next_app/features/profile/presentation/pages/profile_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    OnboardingState.applySnapshot(
      const OnboardingSnapshot(completed: true, language: 'ko'),
    );
  });

  tearDown(OnboardingState.reset);

  testWidgets('S-50 exposes real account and preference routes at 393dp', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = TravelPreferencesStore();
    final router = GoRouter(
      initialLocation: LalaRoutePaths.profile,
      routes: <RouteBase>[
        GoRoute(
          path: LalaRoutePaths.profile,
          builder: (context, state) => ProfilePage(preferencesStore: store),
        ),
        GoRoute(
          path: LalaRoutePaths.travelPreferences,
          builder: (context, state) =>
              const Scaffold(body: Text('preferences-destination')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('profile-page')), findsOneWidget);
    expect(find.text('내 정보'), findsOneWidget);
    expect(find.text('게스트 여행자'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-travel-preferences-entry')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('profile-travel-preferences-entry')),
    );
    await tester.pumpAndSettle();
    expect(find.text('preferences-destination'), findsOneWidget);
  });

  testWidgets('S-50 language selection updates the page without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = TravelPreferencesStore();

    await tester.pumpWidget(
      MaterialApp(home: ProfilePage(preferencesStore: store)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-language-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('My Info'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'S-51 renders the safe disabled account state and privacy entry',
    (tester) async {
      final controller = LalaAuthController(
        config: _disabledConfig,
        gateway: const _FakeGateway(),
        accountApi: const _FakeAccountApi(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: AccountPage(authController: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('account-page')), findsOneWidget);
      expect(find.text('계정 로그인을 사용할 수 없어요'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('account-privacy-details')),
        findsOneWidget,
      );
      expect(find.textContaining('정확한 좌표'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

const LalaAuthConfig _disabledConfig = LalaAuthConfig(
  endpoint: '',
  appId: '',
  apiAudience: '',
  redirectUri: 'cloud.lalanext.lala://callback',
);

class _FakeGateway implements LalaAuthGateway {
  const _FakeGateway();

  @override
  Future<String?> accessToken(String resource) async => null;

  @override
  Future<bool> get isAuthenticated async => false;

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async {}
}

class _FakeAccountApi implements LalaAccountApi {
  const _FakeAccountApi();

  @override
  Future<void> deleteMe({required String confirmation}) async {}

  @override
  Future<LalaMe> getMe() async =>
      throw StateError('disabled account API must not be called');
}
