// ONMU P3b: 커뮤니티 게시글 상세.
// - 게시글 본문 + 태그 + 좋아요 버튼(낙관적 토글).
// - 댓글 리스트 + 하단 댓글 입력(TextField + 전송).
// - 로딩/에러 상태 분기. SafeArea + 오버플로우 방지.
import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/features/community/presentation/community_api.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

class CommunityPostDetailPage extends StatefulWidget {
  const CommunityPostDetailPage({super.key, required this.postId});

  final String postId;

  @override
  State<CommunityPostDetailPage> createState() =>
      _CommunityPostDetailPageState();
}

enum _DetailStatus { loading, data, error }

class _CommunityPostDetailPageState extends State<CommunityPostDetailPage> {
  late final LalaAppConfig _config;
  late LalaApiClient _client;

  _DetailStatus _status = _DetailStatus.loading;
  CommunityPost? _post;
  List<CommunityComment> _comments = const <CommunityComment>[];
  String? _error;

  bool _likeBusy = false;
  bool _commentBusy = false;
  late final TextEditingController _commentController;

  @override
  void initState() {
    super.initState();
    _config = LalaAppConfig.fromEnvironment();
    _client = createCommunityClient(_config);
    _commentController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    _client.close();
    super.dispose();
  }

  String get _language => _config.lang;

  Future<void> _load() async {
    setState(() {
      _status = _DetailStatus.loading;
      _error = null;
    });
    try {
      final postFuture = _client.getCommunityPost(postId: widget.postId);
      final commentsFuture =
          _client.getCommunityComments(postId: widget.postId, limit: 100);
      final postEnvelope = await postFuture;
      final commentsEnvelope = await commentsFuture;
      if (!mounted) return;
      setState(() {
        _post = postEnvelope.data;
        _comments = commentsEnvelope.data?.comments ?? const <CommunityComment>[];
        _status = _DetailStatus.data;
      });
    } on LalaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message.trim().isEmpty ? _fallbackError() : e.message;
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

  String _fallbackError() => lalaCopy(
        _language,
        ko: '게시글을 불러오지 못했어요.',
        en: 'Could not load this post.',
      );

  Future<void> _toggleLike() async {
    final current = _post;
    if (current == null || _likeBusy) return;
    // 낙관적 반영.
    setState(() {
      _post = current.copyWithReactions(
        viewerLiked: !current.viewerLiked,
        likeCount:
            current.likeCount + (current.viewerLiked ? -1 : 1),
      );
      _likeBusy = true;
    });
    try {
      final envelope = await _client.toggleCommunityLike(postId: current.id);
      final state = envelope.data;
      if (!mounted) return;
      setState(() {
        if (state != null) {
          _post = current.copyWithReactions(
            viewerLiked: state.liked,
            likeCount: state.likeCount,
          );
        }
        _likeBusy = false;
      });
    } on Object {
      if (!mounted) return;
      // 실패 시 롤백.
      setState(() {
        _post = current;
        _likeBusy = false;
      });
    }
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _commentBusy || _post == null) return;
    setState(() => _commentBusy = true);
    try {
      final envelope = await _client.createCommunityComment(
        postId: _post!.id,
        body: text,
      );
      final created = envelope.data;
      if (!mounted) return;
      setState(() {
        if (created != null) {
          _comments = <CommunityComment>[..._comments, created];
          _post = _post!.copyWithReactions(
            commentCount: _post!.commentCount + 1,
          );
        }
        _commentBusy = false;
      });
      _commentController.clear();
    } on LalaApiException catch (e) {
      if (!mounted) return;
      setState(() => _commentBusy = false);
      _showSnack(
        e.message.trim().isEmpty
            ? lalaCopy(_language, ko: '댓글 작성에 실패했어요.', en: 'Failed to post comment.')
            : e.message,
      );
    } on Object {
      if (!mounted) return;
      setState(() => _commentBusy = false);
      _showSnack(lalaCopy(_language, ko: '댓글 작성에 실패했어요.', en: 'Failed to post comment.'));
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
          lalaCopy(_language, ko: '게시글', en: 'Post'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: _buildBody(),
      ),
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
                onToggleLike: _toggleLike,
              ),
              const SizedBox(height: 16),
              _CommentSection(
                comments: _comments,
                language: _language,
              ),
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
              label: Text(lalaCopy(language, ko: '재시도', en: 'Retry')),
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

/// 상단 게시글 본문 + 좋아요 버튼.
class _PostDetailHeader extends StatelessWidget {
  const _PostDetailHeader({
    required this.post,
    required this.language,
    required this.likeBusy,
    required this.onToggleLike,
  });

  final CommunityPost post;
  final String language;
  final bool likeBusy;
  final VoidCallback onToggleLike;

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
              const Icon(Icons.person_outline_rounded, size: 14, color: Color(0xFF94A3B8)),
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
                color: liked ? const Color(0xFFE11D48) : const Color(0xFF64748B),
              ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: liked ? const Color(0xFFE11D48) : const Color(0xFF64748B),
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
          lalaCopy(
            language,
            ko: '댓글 ${comments.length}',
            en: 'Comments ${comments.length}',
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
                lalaCopy(
                  language,
                  ko: '첫 댓글을 남겨보세요.',
                  en: 'Be the first to comment.',
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
              return _CommentTile(
                comment: comment,
                language: language,
              );
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
                hintText: lalaCopy(
                  language,
                  ko: '댓글을 입력하세요',
                  en: 'Write a comment',
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
