// Author display-name privacy contract: internal user UUIDs (raw or
// truncated) must never render as author names on the community feed, post
// detail, comments, or chat. No profile display name exists on the wire, so
// every surface shows the neutral localized traveler label — never an
// invented name or identity claim — in all five supported locales.
//
// The internal UUID itself stays available as an action identifier (follow,
// report) — only the rendered label changes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/features/community/presentation/pages/chat_room_page.dart';
import 'package:lala_next_app/features/community/presentation/pages/community_feed_page.dart';
import 'package:lala_next_app/features/community/presentation/pages/community_post_detail_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';

const String _authorUuid = '9f8c7b6a-5e4d-4c3b-8a2f-112233445566';
const List<String> _uuidFragments = <String>[
  '9f8c7b6a',
  '112233445566',
  '0a1b2c3d',
  '998877665544',
];

/// Neutral label per locale — must stay a non-identity claim.
const Map<String, String> _expectedLabel = <String, String>{
  'ko': '여행자',
  'en': 'Traveler',
  'ja': '旅行者',
  'zh-Hans': '旅行者',
  'zh-Hant': '旅行者',
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    OnboardingState.applySnapshot(
      const OnboardingSnapshot(completed: true, language: 'en'),
    );
  });

  tearDown(OnboardingState.reset);

  for (final entry in _expectedLabel.entries) {
    testWidgets('feed shows the neutral author label, never a UUID fragment '
        '(${entry.key})', (tester) async {
      OnboardingState.applySnapshot(
        OnboardingSnapshot(completed: true, language: entry.key),
      );
      final client = _LabelScriptedClient();
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityFeedPage(
            initialConfig: _offlineAppConfig,
            client: client,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(entry.value), findsWidgets);
      for (final fragment in _uuidFragments) {
        expect(find.textContaining(fragment), findsNothing);
      }
    });
  }

  for (final entry in _expectedLabel.entries) {
    testWidgets(
      'post detail and comments show the neutral author label, never a UUID '
      'fragment (${entry.key})',
      (tester) async {
        OnboardingState.applySnapshot(
          OnboardingSnapshot(completed: true, language: entry.key),
        );
        final client = _LabelScriptedClient();
        await tester.pumpWidget(
          MaterialApp(
            home: CommunityPostDetailPage(
              postId: 'p1',
              initialConfig: _offlineAppConfig,
              client: client,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // One label for the post author, one for the comment author.
        expect(find.text(entry.value), findsNWidgets(2));
        for (final fragment in _uuidFragments) {
          expect(find.textContaining(fragment), findsNothing);
        }
      },
    );
  }

  for (final entry in _expectedLabel.entries) {
    testWidgets(
      'chat bubbles show the neutral author label, never a UUID fragment '
      '(${entry.key})',
      (tester) async {
        OnboardingState.applySnapshot(
          OnboardingSnapshot(completed: true, language: entry.key),
        );
        final controller = await _authenticatedController();
        final client = _LabelScriptedClient();
        await tester.pumpWidget(
          MaterialApp(
            home: ChatRoomPage(
              roomId: 'room-1',
              initialConfig: _offlineAppConfig,
              authController: controller,
              client: client,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Two incoming messages from different internal UUIDs → two labels.
        expect(find.text(entry.value), findsNWidgets(2));
        for (final fragment in _uuidFragments) {
          expect(find.textContaining(fragment), findsNothing);
        }
      },
    );
  }
}

const LalaAppConfig _offlineAppConfig = LalaAppConfig(
  baseUri: 'https://api.example.invalid',
);

Future<LalaAuthController> _authenticatedController() async {
  final controller = LalaAuthController(
    config: _enabledAuthConfig,
    gateway: _AuthenticatedGateway(),
    accountApi: const _FakeAccountApi(),
  );
  await controller.initialize();
  return controller;
}

const LalaAuthConfig _enabledAuthConfig = LalaAuthConfig(
  endpoint: 'https://auth.example.invalid',
  appId: 'public-test-client',
  apiAudience: 'https://api.example.invalid',
  redirectUri: 'cloud.lalanext.lala://callback',
);

class _AuthenticatedGateway implements LalaAuthGateway {
  @override
  Future<String?> accessToken(String resource) async => null;

  @override
  Future<bool> get isAuthenticated async => true;

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
  Future<LalaMe> getMe() async => const LalaMe(
    userId: 'viewer-internal-id',
    createdAt: '2026-09-03T00:00:00Z',
    authenticated: true,
  );
}

/// Scripted community endpoints with UUID authors on every surface. The
/// viewer's own id differs so chat bubbles render as incoming. WebSocket
/// token resolution returns empty so no socket is ever opened.
class _LabelScriptedClient extends LalaApiClient {
  _LabelScriptedClient() : super(baseUri: Uri.parse('https://api.label.test'));

  LalaEnvelope<T> _ok<T>(T? data) => LalaEnvelope<T>(
    ok: true,
    data: data,
    meta: const <String, dynamic>{'request_id': 'label-test'},
    error: null,
    statusCode: 200,
    requestId: 'label-test',
  );

  Map<String, Object?> _post(String id) => <String, Object?>{
    'id': id,
    'author_user_id': _authorUuid,
    'title': 'A public conversation',
    'body': 'A public traveler conversation body.',
    'tags': <String>['tips'],
    'like_count': 0,
    'comment_count': 1,
    'viewer_liked': false,
    'viewer_following': false,
    'created_at': '2026-09-03T00:00:00Z',
  };

  @override
  Future<LalaEnvelope<CommunityPostsResponse>> getCommunityPosts({
    int limit = 20,
    int offset = 0,
    String? requestId,
    Duration? timeout,
  }) async => _ok(
    CommunityPostsResponse.fromJsonObject(<String, Object?>{
      'posts': <Object?>[_post('p1')],
      'total': 1,
    }),
  );

  @override
  Future<LalaEnvelope<CommunityPost>> getCommunityPost({
    required String postId,
    String? requestId,
    Duration? timeout,
  }) async => _ok(CommunityPost.fromJsonObject(_post(postId)));

  @override
  Future<LalaEnvelope<CommunityCommentsResponse>> getCommunityComments({
    required String postId,
    int limit = 50,
    int offset = 0,
    String? requestId,
    Duration? timeout,
  }) async => _ok(
    CommunityCommentsResponse.fromJsonObject(<String, Object?>{
      'comments': <Object?>[
        <String, Object?>{
          'id': 'c1',
          'post_id': postId,
          'author_user_id': _authorUuid,
          'body': 'A public comment body.',
          'created_at': '2026-09-03T01:00:00Z',
        },
      ],
      'total': 1,
    }),
  );

  @override
  Future<LalaEnvelope<ChatMessagesResponse>> getChatMessages({
    required String roomId,
    int limit = 50,
    int offset = 0,
    String? requestId,
    Duration? timeout,
  }) async => _ok(
    ChatMessagesResponse.fromJsonObject(<String, Object?>{
      'messages': <Object?>[
        <String, Object?>{
          'id': 'm1',
          'room_id': roomId,
          'author_user_id': _authorUuid,
          'body': 'A public chat message.',
          'created_at': '2026-09-03T02:00:00Z',
        },
        <String, Object?>{
          'id': 'm2',
          'room_id': roomId,
          'author_user_id': '0a1b2c3d-4e5f-4a6b-8c7d-998877665544',
          'body': 'Another public chat message.',
          'created_at': '2026-09-03T02:01:00Z',
        },
      ],
      'total': 2,
    }),
  );

  @override
  Future<LalaEnvelope<ChatWsTicket>> createChatWsTicket({
    required String roomId,
    String? requestId,
    Duration? timeout,
  }) async => throw const LalaApiException(
    code: 'HTTP_404',
    message: 'room not accessible',
    statusCode: 404,
    retryable: false,
  );

  @override
  Future<void> close() async {}
}
