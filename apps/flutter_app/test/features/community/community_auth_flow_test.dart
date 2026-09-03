import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/features/community/presentation/pages/chat_room_list_page.dart';
import 'package:lala_next_app/features/community/presentation/pages/community_create_post_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    OnboardingState.applySnapshot(
      const OnboardingSnapshot(completed: true, language: 'ko'),
    );
  });

  tearDown(OnboardingState.reset);

  testWidgets('S-42 keeps the draft when sign-in is cancelled', (tester) async {
    final gateway = _FakeAuthGateway();
    final controller = LalaAuthController(
      config: _enabledAuthConfig,
      gateway: gateway,
      accountApi: const _FakeAccountApi(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: CommunityCreatePostPage(
          initialConfig: _offlineAppConfig,
          authController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '제목'), '성수 현지 팁');
    await tester.enterText(
      find.widgetWithText(TextField, '본문'),
      '오후에 가기 좋았어요.',
    );
    await tester.pump();
    final submitFinder = find.byKey(const ValueKey('community-post-submit'));
    expect(tester.widget<FilledButton>(submitFinder).onPressed, isNotNull);
    await tester.tap(submitFinder);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('로그인이 필요해요'), findsOneWidget);
    expect(gateway.signInCalls, 0);

    await tester.tap(find.text('나중에'));
    await tester.pumpAndSettle();

    expect(find.text('성수 현지 팁'), findsOneWidget);
    expect(find.text('오후에 가기 좋았어요.'), findsOneWidget);
    expect(gateway.signInCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('S-43 signed-out state requests Logto before loading rooms', (
    tester,
  ) async {
    final gateway = _FakeAuthGateway();
    final controller = LalaAuthController(
      config: _enabledAuthConfig,
      gateway: gateway,
      accountApi: const _FakeAccountApi(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: ChatRoomListPage(
          initialConfig: _offlineAppConfig,
          authController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('계정을 연결해 대화를 이어가세요'), findsOneWidget);
    expect(find.textContaining('공개 커뮤니티 글'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(gateway.signInCalls, 0);
    expect(tester.takeException(), isNull);
  });
}

const LalaAuthConfig _enabledAuthConfig = LalaAuthConfig(
  endpoint: 'https://auth.example.invalid',
  appId: 'public-test-client',
  apiAudience: 'https://api.example.invalid',
  redirectUri: 'cloud.lalanext.lala://callback',
);

const LalaAppConfig _offlineAppConfig = LalaAppConfig(
  baseUri: 'https://api.example.invalid',
);

class _FakeAuthGateway implements LalaAuthGateway {
  bool authenticated = false;
  int signInCalls = 0;

  @override
  Future<String?> accessToken(String resource) async => null;

  @override
  Future<bool> get isAuthenticated async => authenticated;

  @override
  Future<void> signIn() async {
    signInCalls += 1;
    authenticated = true;
  }

  @override
  Future<void> signOut() async {
    authenticated = false;
  }
}

class _FakeAccountApi implements LalaAccountApi {
  const _FakeAccountApi();

  @override
  Future<void> deleteMe({required String confirmation}) async {}

  @override
  Future<LalaMe> getMe() async => const LalaMe(
    userId: 'test-user',
    createdAt: '2026-09-03T00:00:00Z',
    authenticated: true,
  );
}
