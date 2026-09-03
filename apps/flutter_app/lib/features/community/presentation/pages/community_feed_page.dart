// ONMU P3b: 커뮤니티 게시판 피드.
// - 게시글 세로 리스트(제목/요약/태그/좋아요·댓글 수/작성시간/작성자 팔로우).
// - 당겨서 새로고침(RefreshIndicator) + FAB 작성 -> /community/create.
// - 게시글 탭 -> /community/post/:id 상세.
// - 로딩/에러/빈 상태 분기. SafeArea + ColorScheme.fromSeed 테마 준수.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/community/presentation/community_api.dart';
import 'package:lala_next_app/features/community/presentation/community_auth_guard.dart';
import 'package:lala_next_app/features/community/presentation/community_post_actions.dart';
import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

class CommunityFeedPage extends StatefulWidget {
  const CommunityFeedPage({
    this.initialConfig = const LalaAppConfig.fromEnvironment(),
    this.authController,
    this.client,
    super.key,
  });

  final LalaAppConfig initialConfig;
  final LalaAuthController? authController;

  /// Optional injected client for focused tests; production always builds
  /// its own from [initialConfig]. Must stay optional because the shared
  /// router constructs this page without it.
  final LalaApiClient? client;

  @override
  State<CommunityFeedPage> createState() => _CommunityFeedPageState();
}

enum _FeedStatus { loading, data, error }

class _CommunityFeedPageState extends State<CommunityFeedPage> {
  late final LalaAppConfig _config;
  late LalaApiClient _client;
  late final bool _ownsClient;
  final ScrollController _scrollController = ScrollController();

  _FeedStatus _status = _FeedStatus.loading;
  List<CommunityPost> _posts = const <CommunityPost>[];
  int _total = 0;
  String? _error;

  static const int _pageSize = 20;
  bool _isLoadingMore = false;
  bool _hasMore = false;

  // Why: pagination failure must be visible and retryable — a silent stop
  // reads as "no more posts", which is a different truth.
  bool _loadMoreFailed = false;

  // 팔로우는 작성자 단위다: 같은 작성자의 카드들을 한 번에 갱신하며,
  // 진행 중인 작성자의 중복 탭을 막는다.
  final Set<String> _followBusyAuthors = <String>{};

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
    _ownsClient = widget.client == null;
    _client = widget.client ?? createCommunityClient(_config);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(initial: true);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    if (_ownsClient) _client.close();
    super.dispose();
  }

  String get _language => OnboardingState.language;

  void _onScroll() {
    if (_status != _FeedStatus.data) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _load({bool initial = false}) async {
    if (initial) {
      setState(() {
        _status = _FeedStatus.loading;
        _error = null;
        // Why: a full reload replaces the list, so a stale pagination failure
        // must not resurface as a retry row on the refreshed feed.
        _loadMoreFailed = false;
      });
    }
    try {
      final envelope = await _client.getCommunityPosts(
        limit: _pageSize,
        offset: 0,
      );
      final data = envelope.data;
      final posts = data?.posts ?? const <CommunityPost>[];
      final total = data?.total ?? posts.length;
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _total = total;
        _hasMore = posts.length < total;
        _status = _FeedStatus.data;
      });
    } on LalaApiException {
      if (!mounted) return;
      setState(() {
        _error = _fallbackError();
        _status = _FeedStatus.error;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = _fallbackError();
        _status = _FeedStatus.error;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
      _loadMoreFailed = false;
    });
    final offset = _posts.length;
    try {
      final envelope = await _client.getCommunityPosts(
        limit: _pageSize,
        offset: offset,
      );
      final data = envelope.data;
      final more = data?.posts ?? const <CommunityPost>[];
      if (!mounted) return;
      setState(() {
        _posts = <CommunityPost>[..._posts, ...more];
        _hasMore = _posts.length < (data?.total ?? _posts.length);
        _isLoadingMore = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _loadMoreFailed = true;
      });
    }
  }

  String _fallbackError() => lalaCopyMulti(
    _language,
    ko: '게시글을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
    en: 'Could not load posts. Please try again shortly.',
    ja: '投稿を読み込めませんでした。しばらくしてからもう一度お試しください。',
    zhHans: '无法加载帖子，请稍后重试。',
    zhHant: '無法載入貼文，請稍後重試。',
  );

  Future<void> _openCreate() async {
    final outcome = await requestCommunityAuthentication(
      context,
      controller: widget.authController,
      language: _language,
      actionLabel: lalaCopyMulti(
        _language,
        ko: '글쓰기',
        en: 'writing',
        ja: '投稿',
        zhHans: '发帖',
        zhHant: '發文',
      ),
    );
    if (!mounted || outcome != CommunityAuthOutcome.alreadyAuthenticated) {
      return;
    }
    final result = await context.push<Object?>(LalaRoutePaths.communityCreate);
    if (result == true && mounted) {
      _load(initial: true);
    }
  }

  void _openPost(CommunityPost post) {
    context.push(LalaRoutePaths.communityPostFor(post.id));
  }

  List<int> _postIndexesByAuthor(String authorUserId) => <int>[
    for (var i = 0; i < _posts.length; i++)
      if (_posts[i].authorUserId == authorUserId) i,
  ];

  void _setAuthorFollowState(String authorUserId, bool? following, bool busy) {
    setState(() {
      if (busy) {
        _followBusyAuthors.add(authorUserId);
      } else {
        _followBusyAuthors.remove(authorUserId);
      }
      if (following != null) {
        for (final i in _postIndexesByAuthor(authorUserId)) {
          _posts[i] = _posts[i].copyWithReactions(viewerFollowing: following);
        }
      }
    });
  }

  Future<void> _toggleFollow(CommunityPost post) async {
    final authorUserId = post.authorUserId;
    if (_followBusyAuthors.contains(authorUserId)) return;
    final outcome = await requestCommunityAuthentication(
      context,
      controller: widget.authController,
      language: _language,
      actionLabel: communityFollowActionLabel(_language),
    );
    if (!mounted || outcome != CommunityAuthOutcome.alreadyAuthenticated) {
      return;
    }
    final before = post.viewerFollowing;
    // 낙관적 반영: 같은 작성자의 모든 카드에 즉시 반영하고 서버 확정값으로 교체.
    _setAuthorFollowState(authorUserId, !before, true);
    try {
      final envelope = await _client.toggleCommunityFollow(
        followeeUserId: authorUserId,
      );
      final state = envelope.data;
      // Why: an ok envelope without data cannot confirm the follow — roll back
      // to the previous state instead of keeping the optimistic guess.
      if (state == null) {
        throw const LalaApiException(
          code: 'INVALID_RESPONSE',
          message: 'Follow response carried no data.',
          statusCode: 200,
          retryable: true,
        );
      }
      if (!mounted) return;
      _setAuthorFollowState(authorUserId, state.following, false);
    } on LalaApiException catch (error) {
      if (!mounted) return;
      _setAuthorFollowState(authorUserId, before, false);
      _showSnack(
        // Why: self-follow is a server-rejected target, not a transient error;
        // the exact case gets its own honest copy.
        error.code == 'INVALID_FOLLOW_TARGET'
            ? communitySelfFollowMessage(_language)
            : communityFollowFailureMessage(_language),
      );
    } on Object {
      if (!mounted) return;
      _setAuthorFollowState(authorUserId, before, false);
      _showSnack(communityFollowFailureMessage(_language));
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _openChat() async {
    final outcome = await requestCommunityAuthentication(
      context,
      controller: widget.authController,
      language: _language,
      actionLabel: lalaCopyMulti(
        _language,
        ko: '채팅',
        en: 'chat',
        ja: 'チャット',
        zhHans: '聊天',
        zhHant: '聊天',
      ),
    );
    if (!mounted) return;
    if (outcome == CommunityAuthOutcome.alreadyAuthenticated ||
        outcome == CommunityAuthOutcome.signedInNow) {
      context.push(LalaRoutePaths.communityChat);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          lalaCopyMulti(
            _language,
            ko: '커뮤니티',
            en: 'Community',
            ja: 'コミュニティ',
            zhHans: '社区',
            zhHant: '社群',
          ),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: lalaCopyMulti(
              _language,
              ko: '채팅',
              en: 'Chat',
              ja: 'チャット',
              zhHans: '聊天',
              zhHant: '聊天',
            ),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            onPressed: _openChat,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            _CommunityTrustNotice(language: _language),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(initial: true),
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.edit_outlined),
        label: Text(
          lalaCopyMulti(
            _language,
            ko: '글쓰기',
            en: 'Write',
            ja: '書き込む',
            zhHans: '发帖',
            zhHant: '發文',
          ),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case _FeedStatus.loading:
        return _FeedLoadingView(language: _language);
      case _FeedStatus.error:
        return _FeedErrorView(
          message: _error!,
          onRetry: () => _load(initial: true),
          language: _language,
        );
      case _FeedStatus.data:
        if (_posts.isEmpty) {
          return _FeedEmptyView(language: _language);
        }
        return _FeedListView(
          controller: _scrollController,
          posts: _posts,
          total: _total,
          isLoadingMore: _isLoadingMore,
          loadMoreFailed: _loadMoreFailed,
          language: _language,
          onTap: _openPost,
          onRetryLoadMore: _loadMore,
          followBusyAuthors: _followBusyAuthors,
          onToggleFollow: _toggleFollow,
        );
    }
  }
}

class _CommunityTrustNotice extends StatelessWidget {
  const _CommunityTrustNotice({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('community-trust-notice'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.people_outline_rounded,
            color: Color(0xFF1D4ED8),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              lalaCopyMulti(
                language,
                ko: '여행자와 지역 사용자의 대화예요. 출처가 검증된 집계는 Local Signals에서 확인하세요.',
                en: 'These are traveler and local conversations. See Local Signals for source-governed aggregates.',
                ja: '旅行者と地域ユーザーの会話です。出典を検証した集計はLocal Signalsで確認できます。',
                zhHans: '这里是旅行者与当地用户的交流。来源受控的汇总请查看 Local Signals。',
                zhHant: '這裡是旅行者與在地使用者的交流。來源受控的彙整請查看 Local Signals。',
              ),
              style: const TextStyle(
                color: Color(0xFF1E3A8A),
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 로딩 상태 본문.
class _FeedLoadingView extends StatelessWidget {
  const _FeedLoadingView({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(height: 14),
            Text(
              lalaCopyMulti(
                language,
                ko: '게시글을 불러오는 중...',
                en: 'Loading posts…',
                ja: '投稿を読み込んでいます…',
                zhHans: '正在加载帖子…',
                zhHant: '正在載入貼文…',
              ),
              style: const TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedErrorView extends StatelessWidget {
  const _FeedErrorView({
    required this.message,
    required this.onRetry,
    required this.language,
  });
  final String message;
  final VoidCallback onRetry;
  final String language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 36,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                lalaCopyMulti(
                  language,
                  ko: '재시도',
                  en: 'Retry',
                  ja: '再試行',
                  zhHans: '重试',
                  zhHant: '重試',
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedEmptyView extends StatelessWidget {
  const _FeedEmptyView({required this.language});
  final String language;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.forum_outlined,
                  size: 40,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(height: 12),
                Text(
                  lalaCopyMulti(
                    language,
                    ko: '아직 게시글이 없어요.\n첫 글을 남겨보세요!',
                    en: 'No posts yet.\nBe the first to share!',
                    ja: 'まだ投稿がありません。\n最初の投稿をどうぞ！',
                    zhHans: '还没有帖子。\n来发第一篇吧！',
                    zhHant: '還沒有貼文。\n來發第一篇吧！',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FeedListView extends StatelessWidget {
  const _FeedListView({
    required this.controller,
    required this.posts,
    required this.total,
    required this.isLoadingMore,
    required this.loadMoreFailed,
    required this.language,
    required this.onTap,
    required this.onRetryLoadMore,
    required this.followBusyAuthors,
    required this.onToggleFollow,
  });

  final ScrollController controller;
  final List<CommunityPost> posts;
  final int total;
  final bool isLoadingMore;
  final bool loadMoreFailed;
  final String language;
  final ValueChanged<CommunityPost> onTap;
  final VoidCallback onRetryLoadMore;
  final Set<String> followBusyAuthors;
  final ValueChanged<CommunityPost> onToggleFollow;

  @override
  Widget build(BuildContext context) {
    final tailCount = (isLoadingMore || loadMoreFailed) ? 1 : 0;
    return ListView.separated(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      itemCount: posts.length + tailCount,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == posts.length) {
          if (loadMoreFailed) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: OutlinedButton.icon(
                  key: const ValueKey('community-feed-load-more-retry'),
                  onPressed: onRetryLoadMore,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    lalaCopyMulti(
                      language,
                      ko: '더 불러오지 못했어요. 다시 시도',
                      en: 'Could not load more. Try again',
                      ja: 'さらに読み込めませんでした。再試行',
                      zhHans: '未能加载更多，请重试',
                      zhHant: '無法載入更多，請重試',
                    ),
                  ),
                ),
              ),
            );
          }
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final post = posts[index];
        return _CommunityPostCard(
          post: post,
          language: language,
          followBusy: followBusyAuthors.contains(post.authorUserId),
          onToggleFollow: () => onToggleFollow(post),
          onTap: () => onTap(post),
        );
      },
    );
  }
}

/// 게시글 카드 — 피드 본문 표현 + 작성자 팔로우 토글.
class _CommunityPostCard extends StatelessWidget {
  const _CommunityPostCard({
    required this.post,
    required this.language,
    required this.followBusy,
    required this.onToggleFollow,
    required this.onTap,
  });

  final CommunityPost post;
  final String language;
  final bool followBusy;
  final VoidCallback onToggleFollow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodySnippet = post.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                blurRadius: 14,
                offset: Offset(0, 6),
                color: Color(0x10000000),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.person_outline_rounded,
                    size: 13,
                    color: Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      shortAuthorLabel(post.authorUserId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CommunityFollowButton(
                    following: post.viewerFollowing,
                    busy: followBusy,
                    onPressed: onToggleFollow,
                    language: language,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                post.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                bodySnippet,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF475569),
                  height: 1.45,
                ),
              ),
              if (post.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: post.tags
                      .map(
                        (tag) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '#$tag',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    post.viewerLiked ? Icons.favorite : Icons.favorite_border,
                    size: 16,
                    color: post.viewerLiked
                        ? const Color(0xFFE11D48)
                        : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${post.likeCount}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 16,
                    color: Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${post.commentCount}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formatRelativeTime(post.createdAt, language),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
