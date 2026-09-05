import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/features/community/presentation/pages/community_feed_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';

/// S-40 stale-response epoch guard: a superseded `_loadMore` or `_load` may
/// never mutate the list, pagination flags, or visible status after a newer
/// full reload has begun or completed. Every scenario holds responses on
/// deterministic Completers so completion order is exact.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    OnboardingState.applySnapshot(
      const OnboardingSnapshot(completed: true, language: 'en'),
    );
  });

  tearDown(OnboardingState.reset);

  testWidgets(
    'a late load-more success after a full refresh never appends stale rows',
    (tester) async {
      final firstPage = List<Map<String, Object?>>.generate(
        12,
        (index) => _post('p$index', 'First page post $index'),
      );
      final refreshedPage = <Map<String, Object?>>[
        _post('r0', 'Refreshed post 0'),
        _post('r1', 'Refreshed post 1'),
      ];
      final staleSecondPage = <Map<String, Object?>>[
        _post('s12', 'Stale page-two post 12'),
        _post('s13', 'Stale page-two post 13'),
      ];
      final client = _EpochFeedClient()
        ..respondPostsNow(posts: firstPage, total: 30)
        ..holdNextPosts()
        ..respondPostsNow(posts: refreshedPage, total: 2);
      final heldLoadMore = client.heldPosts.single;

      await _pumpFeed(tester, client);
      await tester.pumpAndSettle();
      expect(find.text('First page post 0'), findsOneWidget);

      // Scroll to the bottom: pagination starts and is held in flight.
      await tester.fling(find.byType(ListView), const Offset(0, -6000), 2000);
      await _pumpFrames(tester);
      expect(client.requestedOffsets, <int>[0, 12]);

      // A full refresh supersedes the in-flight load-more and completes with
      // replacement data while the old request is still pending.
      await _triggerRefresh(tester);
      await tester.pumpAndSettle();
      expect(client.requestedOffsets, <int>[0, 12, 0]);
      expect(find.text('Refreshed post 0'), findsOneWidget);
      expect(find.text('Refreshed post 1'), findsOneWidget);

      // The stale load-more succeeds late — its rows must never appear and
      // the pagination flags must stay coherent (no spinner, no retry row).
      heldLoadMore.complete(_postsEnvelope(staleSecondPage, 30));
      await tester.pumpAndSettle();
      expect(find.text('Stale page-two post 12'), findsNothing);
      expect(find.text('Stale page-two post 13'), findsNothing);
      expect(find.text('Refreshed post 1'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_loadMoreRetryFinder, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a late load-more failure after a full refresh leaves no stale retry row',
    (tester) async {
      final firstPage = List<Map<String, Object?>>.generate(
        12,
        (index) => _post('p$index', 'First page post $index'),
      );
      final refreshedPage = <Map<String, Object?>>[
        _post('r0', 'Refreshed post 0'),
        _post('r1', 'Refreshed post 1'),
      ];
      final client = _EpochFeedClient()
        ..respondPostsNow(posts: firstPage, total: 30)
        ..holdNextPosts()
        ..respondPostsNow(posts: refreshedPage, total: 2);
      final heldLoadMore = client.heldPosts.single;

      await _pumpFeed(tester, client);
      await tester.pumpAndSettle();
      await tester.fling(find.byType(ListView), const Offset(0, -6000), 2000);
      await _pumpFrames(tester);
      expect(client.requestedOffsets, <int>[0, 12]);

      await _triggerRefresh(tester);
      await tester.pumpAndSettle();
      expect(find.text('Refreshed post 0'), findsOneWidget);

      // The stale load-more fails late — neither its retry row nor any error
      // surface may appear on the already-refreshed feed.
      heldLoadMore.complete(_unavailable);
      await tester.pumpAndSettle();
      expect(find.text('Refreshed post 1'), findsOneWidget);
      expect(_loadMoreRetryFinder, findsNothing);
      expect(find.textContaining('Could not load'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'overlapping full loads: the newest error wins over the older success',
    (tester) async {
      final client = _EpochFeedClient()
        ..respondPostsNow(
          posts: <Map<String, Object?>>[_post('p0', 'Initial post')],
          total: 1,
        )
        ..holdNextPosts()
        ..failPostsNow();
      final heldOlderLoad = client.heldPosts.single;

      await _pumpFeed(tester, client);
      await tester.pumpAndSettle();
      expect(find.text('Initial post'), findsOneWidget);

      // Refresh twice: the older request is held, the newer one fails first.
      await _triggerRefresh(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await _triggerRefresh(tester);
      await tester.pumpAndSettle();
      expect(client.requestedOffsets, <int>[0, 0, 0]);
      expect(find.textContaining('Could not load posts'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // The older refresh succeeds late — it must not resurrect the list over
      // the newer generation's error.
      heldOlderLoad.complete(
        _postsEnvelope(<Map<String, Object?>>[
          _post('old', 'Older refresh row'),
        ], 1),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load posts'), findsOneWidget);
      expect(find.text('Older refresh row'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'overlapping full loads: the newest success wins over the older error',
    (tester) async {
      final refreshedPage = <Map<String, Object?>>[
        _post('r0', 'Newest refresh row'),
      ];
      final client = _EpochFeedClient()
        ..respondPostsNow(
          posts: <Map<String, Object?>>[_post('p0', 'Initial post')],
          total: 1,
        )
        ..holdNextPosts()
        ..respondPostsNow(posts: refreshedPage, total: 1);
      final heldOlderLoad = client.heldPosts.single;

      await _pumpFeed(tester, client);
      await tester.pumpAndSettle();
      expect(find.text('Initial post'), findsOneWidget);

      // Refresh twice: the older request is held, the newer one succeeds.
      await _triggerRefresh(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await _triggerRefresh(tester);
      await tester.pumpAndSettle();
      expect(client.requestedOffsets, <int>[0, 0, 0]);
      expect(find.text('Newest refresh row'), findsOneWidget);

      // The older refresh fails late — it must not flip the feed into the
      // error state.
      heldOlderLoad.complete(_unavailable);
      await tester.pumpAndSettle();
      expect(find.text('Newest refresh row'), findsOneWidget);
      expect(find.textContaining('Could not load posts'), findsNothing);
      expect(_loadMoreRetryFinder, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

const LalaAppConfig _offlineAppConfig = LalaAppConfig(
  baseUri: 'https://api.example.invalid',
);

final Finder _loadMoreRetryFinder = find.byKey(
  const ValueKey('community-feed-load-more-retry'),
);

Future<void> _pumpFeed(WidgetTester tester, _EpochFeedClient client) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CommunityFeedPage(
        initialConfig: _offlineAppConfig,
        client: client,
      ),
    ),
  );
}

/// Advance a fixed number of frames instead of settling: a held in-flight
/// request keeps the bottom spinner animating forever.
Future<void> _pumpFrames(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Drive the exact callback a pull-to-refresh gesture would invoke, without
/// depending on gesture displacement or the indicator's own spinner.
Future<void> _triggerRefresh(WidgetTester tester) async {
  final indicator = tester.widget<RefreshIndicator>(
    find.byType(RefreshIndicator),
  );
  unawaited(indicator.onRefresh());
}

Map<String, Object?> _post(String id, String title) =>
    <String, Object?>{
      'id': id,
      'author_user_id': '11111111-1111-4111-8111-111111111111',
      'title': title,
      'body': 'A public traveler conversation body.',
      'tags': <String>['tips'],
      'like_count': 0,
      'comment_count': 0,
      'viewer_liked': false,
      'viewer_following': false,
      'created_at': '2026-09-03T00:00:00Z',
    };

const LalaApiException _unavailable = LalaApiException(
  code: 'HTTP_503',
  message: 'service unavailable',
  statusCode: 503,
  retryable: true,
);

LalaEnvelope<CommunityPostsResponse> _postsEnvelope(
  List<Map<String, Object?>> posts,
  int total,
) =>
    LalaEnvelope<CommunityPostsResponse>(
      ok: true,
      data: CommunityPostsResponse.fromJsonObject(
        <String, Object?>{'posts': posts, 'total': total},
      ),
      meta: const <String, dynamic>{'request_id': 'test-request'},
      error: null,
      statusCode: 200,
      requestId: 'test-request',
    );

typedef _PostsResponder
    = Future<LalaEnvelope<CommunityPostsResponse>> Function();

/// Serves Completer-scripted community post responses in strict call order.
/// Each `getCommunityPosts` call consumes exactly one scripted responder, so
/// tests control which request is held, which resolves, and in what order.
class _EpochFeedClient extends LalaApiClient {
  _EpochFeedClient() : super(baseUri: _scriptedBaseUri);

  static final Uri _scriptedBaseUri = Uri.parse('https://api.example.test');

  final List<int> requestedOffsets = <int>[];
  final List<_PostsResponder> _responders = <_PostsResponder>[];
  final List<Completer<Object?>> heldPosts = <Completer<Object?>>[];

  void respondPostsNow({
    required List<Map<String, Object?>> posts,
    required int total,
  }) {
    final envelope = _postsEnvelope(posts, total);
    _responders.add(() async => envelope);
  }

  void failPostsNow() {
    _responders.add(() async => throw _unavailable);
  }

  Completer<Object?> holdNextPosts() {
    final completion = Completer<Object?>();
    heldPosts.add(completion);
    _responders.add(() async {
      final outcome = await completion.future;
      if (outcome is LalaApiException) throw outcome;
      return outcome as LalaEnvelope<CommunityPostsResponse>;
    });
    return completion;
  }

  @override
  Future<LalaEnvelope<CommunityPostsResponse>> getCommunityPosts({
    int limit = 20,
    int offset = 0,
    String? requestId,
    Duration? timeout,
  }) {
    requestedOffsets.add(offset);
    if (_responders.isEmpty) {
      throw StateError(
        'unexpected community posts request at offset $offset '
        '(limit $limit); no scripted responder left',
      );
    }
    return _responders.removeAt(0)();
  }
}
