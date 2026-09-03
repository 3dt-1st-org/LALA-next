// ONMU P3b: 커뮤니티 게시글 상세.
// - 게시글 본문 + 태그 + 좋아요 버튼(낙관적 토글) + 작성자 팔로우 토글.
// - 댓글 리스트 + 하단 댓글 입력(TextField + 전송).
// - 게시글 신고(제한된 사유 코드, 접수 영수증 안내).
// - 로딩/에러 상태 분기. SafeArea + 오버플로우 방지.
import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/features/community/presentation/community_api.dart';
import 'package:lala_next_app/features/community/presentation/community_auth_guard.dart';
import 'package:lala_next_app/features/community/presentation/community_post_actions.dart';
import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

class CommunityPostDetailPage extends StatefulWidget {
  const CommunityPostDetailPage({
    super.key,
    required this.postId,
    this.initialConfig = const LalaAppConfig.fromEnvironment(),
    this.authController,
    this.client,
  });

  final String postId;
  final LalaAppConfig initialConfig;
  final LalaAuthController? authController;

  /// Optional injected client for focused tests; production always builds
  /// its own from [initialConfig]. Must stay optional because the shared
  /// router constructs this page without it.
  final LalaApiClient? client;

  @override
  State<CommunityPostDetailPage> createState() =>
      _CommunityPostDetailPageState();
}

enum _DetailStatus { loading, data, error }

class _CommunityPostDetailPageState extends State<CommunityPostDetailPage> {
  late final LalaAppConfig _config;
  late LalaApiClient _client;
  late final bool _ownsClient;

  _DetailStatus _status = _DetailStatus.loading;
  CommunityPost? _post;
  List<CommunityComment> _comments = const <CommunityComment>[];
  String? _error;

  bool _likeBusy = false;
  bool _commentBusy = false;
  bool _followBusy = false;
  bool _reportBusy = false;
  late final TextEditingController _commentController;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
    _ownsClient = widget.client == null;
    _client = widget.client ?? createCommunityClient(_config);
    _commentController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    if (_ownsClient) _client.close();
    super.dispose();
  }

  String get _language => OnboardingState.language;

  Future<void> _load() async {
    setState(() {
      _status = _DetailStatus.loading;
      _error = null;
    });
    try {
      final postFuture = _client.getCommunityPost(postId: widget.postId);
      final commentsFuture = _client.getCommunityComments(
        postId: widget.postId,
        limit: 100,
      );
      final postEnvelope = await postFuture;
      final commentsEnvelope = await commentsFuture;
      if (!mounted) return;
      setState(() {
        _post = postEnvelope.data;
        _comments =
            commentsEnvelope.data?.comments ?? const <CommunityComment>[];
        _status = _DetailStatus.data;
      });
    } on LalaApiException {
      if (!mounted) return;
      setState(() {
        _error = _fallbackError();
        _status = _DetailStatus.error;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = _fallbackError();
        _status = _DetailStatus.error;
      });
    }
  }

  String _fallbackError() => lalaCopyMulti(
    _language,
    ko: '게시글을 불러오지 못했어요.',
    en: 'Could not load this post.',
    ja: '投稿を読み込めませんでした。',
    zhHans: '无法加载这篇帖子。',
    zhHant: '無法載入這篇貼文。',
  );

  Future<void> _toggleLike() async {
    final current = _post;
    if (current == null || _likeBusy) return;
    final outcome = await requestCommunityAuthentication(
      context,
      controller: widget.authController,
      language: _language,
      actionLabel: lalaCopyMulti(
        _language,
        ko: '좋아요',
        en: 'reactions',
        ja: 'いいね',
        zhHans: '点赞',
        zhHant: '按讚',
      ),
    );
    if (!mounted || outcome != CommunityAuthOutcome.alreadyAuthenticated) {
      return;
    }
    // 낙관적 반영.
    setState(() {
      _post = current.copyWithReactions(
        viewerLiked: !current.viewerLiked,
        likeCount: current.likeCount + (current.viewerLiked ? -1 : 1),
      );
      _likeBusy = true;
    });
    try {
      final envelope = await _client.toggleCommunityLike(postId: current.id);
      final state = envelope.data;
      // Why: an ok envelope without data cannot confirm the new reaction —
      // treating it as an invalid response rolls the optimistic toggle back
      // and states the failure instead of silently keeping the local guess.
      if (state == null) {
        throw const LalaApiException(
          code: 'INVALID_RESPONSE',
          message: 'Like response carried no data.',
          statusCode: 200,
          retryable: true,
        );
      }
      if (!mounted) return;
      setState(() {
        _post = current.copyWithReactions(
          viewerLiked: state.liked,
          likeCount: state.likeCount,
        );
        _likeBusy = false;
      });
    } on Object {
      if (!mounted) return;
      // 실패 시 롤백 + 정직한 안내(조용히 되돌리면 반영된 것으로 읽힌다).
      setState(() {
        _post = current;
        _likeBusy = false;
      });
      _showSnack(
        lalaCopyMulti(
          _language,
          ko: '좋아요 처리에 실패했어요. 잠시 후 다시 시도해 주세요.',
          en: 'Could not update your like. Please try again.',
          ja: 'いいねを更新できませんでした。しばらくしてからもう一度お試しください。',
          zhHans: '无法更新点赞，请稍后重试。',
          zhHant: '無法更新按讚，請稍後再試。',
        ),
      );
    }
  }

  Future<void> _toggleFollow() async {
    final current = _post;
    if (current == null || _followBusy) return;
    final outcome = await requestCommunityAuthentication(
      context,
      controller: widget.authController,
      language: _language,
      actionLabel: communityFollowActionLabel(_language),
    );
    if (!mounted || outcome != CommunityAuthOutcome.alreadyAuthenticated) {
      return;
    }
    // 낙관적 반영(좋아요와 동일한 롤백 계약).
    setState(() {
      _post = current.copyWithReactions(
        viewerFollowing: !current.viewerFollowing,
      );
      _followBusy = true;
    });
    try {
      final envelope = await _client.toggleCommunityFollow(
        followeeUserId: current.authorUserId,
      );
      final state = envelope.data;
      // Why: an ok envelope without data cannot confirm the new follow —
      // rolling back and stating the failure is safer than keeping the guess.
      if (state == null) {
        throw const LalaApiException(
          code: 'INVALID_RESPONSE',
          message: 'Follow response carried no data.',
          statusCode: 200,
          retryable: true,
        );
      }
      if (!mounted) return;
      setState(() {
        _post = current.copyWithReactions(viewerFollowing: state.following);
        _followBusy = false;
      });
    } on LalaApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _post = current;
        _followBusy = false;
      });
      _showSnack(
        // Why: the server rejects self-follow explicitly (INVALID_FOLLOW_TARGET);
        // surfacing that exact case avoids presenting it as a transient failure.
        error.code == 'INVALID_FOLLOW_TARGET'
            ? communitySelfFollowMessage(_language)
            : communityFollowFailureMessage(_language),
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _post = current;
        _followBusy = false;
      });
      _showSnack(communityFollowFailureMessage(_language));
    }
  }

  Future<void> _reportPost() async {
    final current = _post;
    if (current == null || _reportBusy) return;
    final outcome = await requestCommunityAuthentication(
      context,
      controller: widget.authController,
      language: _language,
      actionLabel: communityReportActionLabel(_language),
    );
    if (!mounted || outcome != CommunityAuthOutcome.alreadyAuthenticated) {
      return;
    }
    final reason = await showCommunityReportReasonSheet(context, _language);
    if (reason == null || !mounted) return;
    // 접수 중 재제출 방지(이중 탭/메뉴 재선택 모두 차단).
    setState(() => _reportBusy = true);
    try {
      final envelope = await _client.reportCommunityPost(
        postId: current.id,
        reasonCode: reason,
      );
      final receipt = envelope.data;
      // Why: without a receipt the submit cannot be confirmed — reporting
      // success here would be an optimistic false success.
      if (receipt == null) {
        throw const LalaApiException(
          code: 'INVALID_RESPONSE',
          message: 'Report response carried no data.',
          statusCode: 200,
          retryable: true,
        );
      }
      if (!mounted) return;
      setState(() => _reportBusy = false);
      _showSnack(communityReportReceiptMessage(_language, receipt.duplicate));
    } on Object {
      if (!mounted) return;
      setState(() => _reportBusy = false);
      _showSnack(communityReportFailureMessage(_language));
    }
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _commentBusy || _post == null) return;
    final outcome = await requestCommunityAuthentication(
      context,
      controller: widget.authController,
      language: _language,
      actionLabel: lalaCopyMulti(
        _language,
        ko: '댓글 작성',
        en: 'commenting',
        ja: 'コメント投稿',
        zhHans: '发表评论',
        zhHant: '發表留言',
      ),
    );
    if (!mounted || outcome != CommunityAuthOutcome.alreadyAuthenticated) {
      return;
    }
    setState(() => _commentBusy = true);
    try {
      final envelope = await _client.createCommunityComment(
        postId: _post!.id,
        body: text,
      );
      final created = envelope.data;
      // Why: an ok envelope without data never echoed the created comment —
      // routing it into the API-failure branch keeps the typed text and
      // reports the failure instead of clearing the composer as if it posted.
      if (created == null) {
        throw const LalaApiException(
          code: 'INVALID_RESPONSE',
          message: 'Comment response carried no data.',
          statusCode: 200,
          retryable: true,
        );
      }
      if (!mounted) return;
      setState(() {
        _comments = <CommunityComment>[..._comments, created];
        _post = _post!.copyWithReactions(commentCount: _post!.commentCount + 1);
        _commentBusy = false;
      });
      _commentController.clear();
    } on LalaApiException {
      if (!mounted) return;
      setState(() => _commentBusy = false);
      _showSnack(
        lalaCopyMulti(
          _language,
          ko: '댓글 작성에 실패했어요. 입력 내용은 유지됐습니다.',
          en: 'Failed to post comment. Your text is still here.',
          ja: 'コメントを投稿できませんでした。入力内容は保持されています。',
          zhHans: '发表评论失败，输入内容已保留。',
          zhHant: '發表留言失敗，輸入內容已保留。',
        ),
      );
    } on Object {
      if (!mounted) return;
      setState(() => _commentBusy = false);
      _showSnack(
        lalaCopyMulti(
          _language,
          ko: '댓글 작성에 실패했어요.',
          en: 'Failed to post comment.',
          ja: 'コメントの投稿に失敗しました。',
          zhHans: '发表评论失败。',
          zhHant: '發表留言失敗。',
        ),
      );
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
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
            ko: '게시글',
            en: 'Post',
            ja: '投稿',
            zhHans: '帖子',
            zhHant: '貼文',
          ),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: <Widget>[
          // 제출 중에는 메뉴 자체를 막아 이중 신고 제출 경로를 원천 차단한다.
          PopupMenuButton<String>(
            key: const ValueKey('community-post-menu'),
            enabled: !_reportBusy,
            tooltip: communityReportMenuLabel(_language),
            onSelected: (value) {
              if (value == 'report') _reportPost();
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'report',
                child: Text(communityReportMenuLabel(_language)),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(top: false, child: _buildBody()),
      bottomNavigationBar: _post == null
          ? null
          : SafeArea(
              top: false,
              child: _CommentInputBar(
                controller: _commentController,
                busy: _commentBusy,
                language: _language,
                onSubmit: _submitComment,
              ),
            ),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case _DetailStatus.loading:
        return const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        );
      case _DetailStatus.error:
        return _DetailErrorView(
          message: _error!,
          onRetry: _load,
          language: _language,
        );
      case _DetailStatus.data:
        final post = _post;
        if (post == null) {
          return _DetailErrorView(
            message: _fallbackError(),
            onRetry: _load,
            language: _language,
          );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _PostDetailHeader(
                post: post,
                language: _language,
                likeBusy: _likeBusy,
                followBusy: _followBusy,
                onToggleLike: _toggleLike,
                onToggleFollow: _toggleFollow,
              ),
              const SizedBox(height: 16),
              _CommentSection(comments: _comments, language: _language),
            ],
          ),
        );
    }
  }
}

class _DetailErrorView extends StatelessWidget {
  const _DetailErrorView({
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

/// 상단 게시글 본문 + 좋아요/팔로우 버튼.
class _PostDetailHeader extends StatelessWidget {
  const _PostDetailHeader({
    required this.post,
    required this.language,
    required this.likeBusy,
    required this.followBusy,
    required this.onToggleLike,
    required this.onToggleFollow,
  });

  final CommunityPost post;
  final String language;
  final bool likeBusy;
  final bool followBusy;
  final VoidCallback onToggleLike;
  final VoidCallback onToggleFollow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            post.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                size: 14,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(width: 4),
              Text(
                shortAuthorLabel(post.authorUserId),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatRelativeTime(post.createdAt, language),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF94A3B8),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              CommunityFollowButton(
                following: post.viewerFollowing,
                busy: followBusy,
                onPressed: onToggleFollow,
                language: language,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            post.body,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          if (post.tags.isNotEmpty) ...[
            const SizedBox(height: 14),
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
                        color: theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.5,
                        ),
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
          const Divider(height: 28),
          Row(
            children: [
              _LikeButton(
                liked: post.viewerLiked,
                count: post.likeCount,
                busy: likeBusy,
                onPressed: onToggleLike,
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '${post.commentCount}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.liked,
    required this.count,
    required this.busy,
    required this.onPressed,
  });

  final bool liked;
  final int count;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: busy ? null : onPressed,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: liked
              ? const Color(0xFFE11D48).withValues(alpha: 0.1)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                size: 16,
                color: liked
                    ? const Color(0xFFE11D48)
                    : const Color(0xFF64748B),
              ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: liked
                    ? const Color(0xFFE11D48)
                    : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentSection extends StatelessWidget {
  const _CommentSection({required this.comments, required this.language});

  final List<CommunityComment> comments;
  final String language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          lalaCopyMulti(
            language,
            ko: '댓글 ${comments.length}',
            en: 'Comments ${comments.length}',
            ja: 'コメント ${comments.length}',
            zhHans: '评论 ${comments.length}',
            zhHant: '留言 ${comments.length}',
          ),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: const Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 10),
        if (comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                lalaCopyMulti(
                  language,
                  ko: '첫 댓글을 남겨보세요.',
                  en: 'Be the first to comment.',
                  ja: '最初のコメントをどうぞ。',
                  zhHans: '来发表第一条评论吧。',
                  zhHant: '來發表第一則留言吧。',
                ),
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: comments.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final comment = comments[index];
              return _CommentTile(comment: comment, language: language);
            },
          ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.language});

  final CommunityComment comment;
  final String language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  shortAuthorLabel(comment.authorUserId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatRelativeTime(comment.createdAt, language),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF94A3B8),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            comment.body,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}

/// 하단 고정 댓글 입력 바.
class _CommentInputBar extends StatelessWidget {
  const _CommentInputBar({
    required this.controller,
    required this.busy,
    required this.language,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final String language;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: const Color(0xFFE2E8F0), width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                hintText: lalaCopyMulti(
                  language,
                  ko: '댓글을 입력하세요',
                  en: 'Write a comment',
                  ja: 'コメントを入力',
                  zhHans: '输入评论',
                  zhHant: '輸入留言',
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            onPressed: busy ? null : onSubmit,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 18),
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
