// ONMU P3b: 커뮤니티 게시판 피드.
// - 게시글 세로 리스트(제목/요약/태그/좋아요·댓글 수/작성시간).
// - 당겨서 새로고침(RefreshIndicator) + FAB 작성 -> /community/create.
// - 게시글 탭 -> /community/post/:id 상세.
// - 로딩/에러/빈 상태 분기. SafeArea + ColorScheme.fromSeed 테마 준수.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/community/presentation/community_api.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

class CommunityFeedPage extends StatefulWidget {
  const CommunityFeedPage({super.key});

  @override
  State<CommunityFeedPage> createState() => _CommunityFeedPageState();
}

enum _FeedStatus { loading, data, error }

class _CommunityFeedPageState extends State<CommunityFeedPage> {
  late final LalaAppConfig _config;
  late LalaApiClient _client;
  final ScrollController _scrollController = ScrollController();

  _FeedStatus _status = _FeedStatus.loading;
  List<CommunityPost> _posts = const <CommunityPost>[];
  int _total = 0;
  String? _error;

  static const int _pageSize = 20;
  bool _isLoadingMore = false;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _config = LalaAppConfig.fromEnvironment();
    _client = createCommunityClient(_config);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(initial: true);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _client.close();
    super.dispose();
  }

  String get _language => _config.lang;

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
    } on LalaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message.trim().isEmpty ? _fallbackError() : e.message;
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
    setState(() => _isLoadingMore = true);
    final offset = _posts.length;
    try {
      final envelope =
          await _client.getCommunityPosts(limit: _pageSize, offset: offset);
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
      setState(() => _isLoadingMore = false);
    }
  }

  String _fallbackError() => lalaCopy(
        _language,
        ko: '게시글을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
        en: 'Could not load posts. Please try again shortly.',
      );

  Future<void> _openCreate() async {
    final result =
        await context.push<Object?>(LalaRoutePaths.communityCreate);
    if (result == true && mounted) {
      _load(initial: true);
    }
  }

  void _openPost(CommunityPost post) {
    context.push(LalaRoutePaths.communityPostFor(post.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          lalaCopy(_language, ko: '커뮤니티', en: 'Community'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => _load(initial: true),
          child: _buildBody(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.edit_outlined),
        label: Text(
          lalaCopy(_language, ko: '글쓰기', en: 'Write'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case _FeedStatus.loading:
        return const _FeedLoadingView();
      case _FeedStatus.error:
        return _FeedErrorView(message: _error!, onRetry: () => _load(initial: true));
      case _FeedStatus.data:
        if (_posts.isEmpty) {
          return _FeedEmptyView(language: _language);
        }
        return _FeedListView(
          controller: _scrollController,
          posts: _posts,
          total: _total,
          isLoadingMore: _isLoadingMore,
          language: _language,
          onTap: _openPost,
        );
    }
  }
}

/// 로딩 상태 본문.
class _FeedLoadingView extends StatelessWidget {
  const _FeedLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(height: 14),
            Text(
              '게시글을 불러오는 중...',
              style: TextStyle(
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
  const _FeedErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 36, color: Color(0xFF94A3B8)),
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
              label: const Text('재시도'),
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
                  lalaCopy(
                    language,
                    ko: '아직 게시글이 없어요.\n첫 글을 남겨보세요!',
                    en: 'No posts yet.\nBe the first to share!',
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
    required this.language,
    required this.onTap,
  });

  final ScrollController controller;
  final List<CommunityPost> posts;
  final int total;
  final bool isLoadingMore;
  final String language;
  final ValueChanged<CommunityPost> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      itemCount: posts.length + (isLoadingMore ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == posts.length) {
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
          onTap: () => onTap(post),
        );
      },
    );
  }
}

/// 게시글 카드 — 피드/상세 공통 본문 표현.
class _CommunityPostCard extends StatelessWidget {
  const _CommunityPostCard({
    required this.post,
    required this.language,
    required this.onTap,
  });

  final CommunityPost post;
  final String language;
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
