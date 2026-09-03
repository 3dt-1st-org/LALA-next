import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/features/community/presentation/pages/chat_room_list_page.dart';
import 'package:lala_next_app/features/community/presentation/pages/community_create_post_page.dart';
import 'package:lala_next_app/features/community/presentation/pages/community_feed_page.dart';
import 'package:lala_next_app/features/community/presentation/pages/community_post_detail_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    OnboardingState.applySnapshot(
      const OnboardingSnapshot(completed: true, language: 'en'),
    );
  });

  tearDown(OnboardingState.reset);

  testWidgets('S-40 loading copy follows the selected language', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CommunityFeedPage(
          initialConfig: LalaAppConfig(baseUri: 'http://127.0.0.1:9'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Loading posts…'), findsOneWidget);
    expect(find.textContaining('불러오는 중'), findsNothing);
    // Let the in-flight request settle so no timer outlives the test.
    await tester.pumpAndSettle();
  });

  testWidgets('S-40 error state offers a localized retry', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CommunityFeedPage(
          initialConfig: LalaAppConfig(baseUri: 'http://127.0.0.1:9'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not load posts'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('재시도'), findsNothing);
  });

  testWidgets(
    'S-40 load-more failure is visible and retryable, not a silent stop',
    (tester) async {
      final firstPage = List<Map<String, Object?>>.generate(
        12,
        (index) => _post('p$index', 'Post number $index'),
      );
      final adapter = _ScriptedAdapter()
        ..respondPosts(offset: 0, posts: firstPage, total: 14)
        ..failPostsAt(12);
      final client = _clientFor(adapter);

      await tester.pumpWidget(
        MaterialApp(
          home: CommunityFeedPage(
            initialConfig: _offlineAppConfig,
            client: client,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Post number 0'), findsOneWidget);

      // Scroll to the bottom so the pagination listener fires.
      await tester.fling(find.byType(ListView), const Offset(0, -6000), 2000);
      await tester.pumpAndSettle();

      final retryFinder = find.byKey(
        const ValueKey('community-feed-load-more-retry'),
      );
      expect(retryFinder, findsOneWidget);
      expect(find.text('Post number 11'), findsOneWidget);

      // The retry succeeds and appends the remaining page.
      adapter.respondPosts(
        offset: 12,
        posts: <Map<String, Object?>>[
          _post('p12', 'Post number 12'),
          _post('p13', 'Post number 13'),
        ],
        total: 14,
      );
      await tester.ensureVisible(retryFinder);
      await tester.pumpAndSettle();
      await tester.tap(retryFinder);
      await tester.pumpAndSettle();
      expect(find.text('Post number 12'), findsOneWidget);
      expect(find.text('Post number 13'), findsOneWidget);
      expect(retryFinder, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('S-41 like failure rolls back and states the failure honestly', (
    tester,
  ) async {
    final adapter = _ScriptedAdapter()
      ..respondPost(_post('p1', 'First post title', likeCount: 5))
      ..respondComments()
      ..failLikes = true;
    final client = _clientFor(adapter);
    final controller = await _authenticatedController();

    await tester.pumpWidget(
      MaterialApp(
        home: CommunityPostDetailPage(
          postId: 'p1',
          initialConfig: _offlineAppConfig,
          authController: controller,
          client: client,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('First post title'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();

    expect(adapter.likeCalls, 1);
    expect(
      find.text('Could not update your like. Please try again.'),
      findsOneWidget,
    );
    // The optimistic toggle was rolled back to the server value.
    expect(find.text('5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('S-43 loading copy follows the selected language', (
    tester,
  ) async {
    final controller = await _authenticatedController();

    await tester.pumpWidget(
      MaterialApp(
        home: ChatRoomListPage(
          initialConfig: const LalaAppConfig(baseUri: 'http://127.0.0.1:9'),
          authController: controller,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Loading chat rooms…'), findsOneWidget);
    expect(find.textContaining('불러오는 중'), findsNothing);
    // Let the in-flight request settle so no timer outlives the test.
    await tester.pumpAndSettle();
  });

  testWidgets('S-42 create form renders dedicated visitor copy', (
    tester,
  ) async {
    OnboardingState.applySnapshot(
      const OnboardingSnapshot(completed: true, language: 'ja'),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: CommunityCreatePostPage(initialConfig: _offlineAppConfig),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('新しい投稿'), findsOneWidget);
    expect(find.text('タイトル'), findsOneWidget);
    expect(find.text('本文'), findsOneWidget);
    expect(find.text('タグ'), findsOneWidget);
    // Korean must not leak onto the ja screen.
    expect(find.textContaining('새 게시글'), findsNothing);
    expect(find.textContaining('제목'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

const LalaAppConfig _offlineAppConfig = LalaAppConfig(
  baseUri: 'https://api.example.invalid',
);

Map<String, Object?> _post(String id, String title, {int likeCount = 0}) =>
    <String, Object?>{
      'id': id,
      'author_user_id': '11111111-1111-4111-8111-111111111111',
      'title': title,
      'body': 'A public traveler conversation body.',
      'tags': <String>['tips'],
      'like_count': likeCount,
      'comment_count': 0,
      'viewer_liked': false,
      'created_at': '2026-09-03T00:00:00Z',
    };

LalaApiClient _clientFor(_ScriptedAdapter adapter) => LalaApiClient(
  baseUri: Uri.parse('https://api.example.test'),
  bearerToken: 'test-token',
  dio: Dio()..httpClientAdapter = adapter,
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
    userId: 'test-user',
    createdAt: '2026-09-03T00:00:00Z',
    authenticated: true,
  );
}

/// Serves scripted community endpoints for the focused widget tests. No live
/// network is touched and no production data is created.
class _ScriptedAdapter implements HttpClientAdapter {
  final Map<int, Map<String, Object?>> _pagesByOffset =
      <int, Map<String, Object?>>{};
  final Set<int> _failingOffsets = <int>{};
  Map<String, Object?>? _postDetail;
  bool failLikes = false;
  int likeCalls = 0;

  void respondPosts({
    required int offset,
    required List<Map<String, Object?>> posts,
    required int total,
  }) {
    _pagesByOffset[offset] = <String, Object?>{'posts': posts, 'total': total};
  }

  void failPostsAt(int offset) => _failingOffsets.add(offset);

  void respondPost(Map<String, Object?> post) => _postDetail = post;

  void respondComments() =>
      _comments = <String, Object?>{'comments': <Object?>[], 'total': 0};

  Map<String, Object?>? _comments;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path == '/api/v1/community/posts' && options.method == 'GET') {
      final offset =
          int.tryParse(options.uri.queryParameters['offset'] ?? '0') ?? 0;
      if (_failingOffsets.remove(offset) ||
          !_pagesByOffset.containsKey(offset)) {
        return _error(503);
      }
      return _json(_pagesByOffset[offset]!);
    }
    if (path.endsWith('/like')) {
      likeCalls += 1;
      if (failLikes) return _error(503);
      return _json(<String, Object?>{
        'post_id': 'p1',
        'liked': true,
        'like_count': 6,
      });
    }
    if (path.endsWith('/comments') && options.method == 'GET') {
      return _json(_comments ?? <String, Object?>{'comments': <Object?>[]});
    }
    final postMatch = RegExp(r'^/api/v1/community/posts/[^/]+$').hasMatch(path);
    if (postMatch && _postDetail != null) {
      return _json(_postDetail!);
    }
    return _error(404);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, Object?> data) {
  final payload = utf8.encode(
    jsonEncode(<String, Object?>{
      'ok': true,
      'data': data,
      'meta': <String, Object?>{'request_id': 'test-request'},
      'error': null,
    }),
  );
  return ResponseBody(
    Stream<Uint8List>.value(Uint8List.fromList(payload)),
    200,
    headers: <String, List<String>>{
      'content-type': <String>['application/json; charset=utf-8'],
    },
  );
}

ResponseBody _error(int status) => ResponseBody(
  Stream<Uint8List>.value(Uint8List(0)),
  status,
  statusMessage: 'service unavailable',
);
