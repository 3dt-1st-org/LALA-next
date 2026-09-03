// ONMU P3b: 커뮤니티 게시글 작성.
// - 제목 TextField + 본문 multiline + 태그 chip 입력 -> "게시" 버튼.
// - 전송 중 비활성화, 입력 검증(제목/본문 빈 값 방지). 성공 시 pop(true) 로 피드 갱신 트리거.
import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/features/community/presentation/community_api.dart';
import 'package:lala_next_app/features/community/presentation/community_auth_guard.dart';
import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

class CommunityCreatePostPage extends StatefulWidget {
  const CommunityCreatePostPage({
    this.initialConfig = const LalaAppConfig.fromEnvironment(),
    this.authController,
    super.key,
  });

  final LalaAppConfig initialConfig;
  final LalaAuthController? authController;

  @override
  State<CommunityCreatePostPage> createState() =>
      _CommunityCreatePostPageState();
}

class _CommunityCreatePostPageState extends State<CommunityCreatePostPage> {
  late final LalaAppConfig _config;
  late LalaApiClient _client;

  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final TextEditingController _tagController;

  final List<String> _tags = <String>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
    _client = createCommunityClient(_config);
    _titleController = TextEditingController();
    _bodyController = TextEditingController();
    _tagController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _tagController.dispose();
    _client.close();
    super.dispose();
  }

  String get _language => OnboardingState.language;

  bool get _canSubmit {
    if (_busy) return false;
    return _titleController.text.trim().isNotEmpty &&
        _bodyController.text.trim().isNotEmpty;
  }

  void _addTag() {
    final raw = _tagController.text.trim();
    if (raw.isEmpty) return;
    final cleaned = raw.replaceAll(RegExp(r'^#+'), '').trim();
    if (cleaned.isEmpty) return;
    if (_tags.any((t) => t.toLowerCase() == cleaned.toLowerCase())) {
      _tagController.clear();
      return;
    }
    if (_tags.length >= 8) {
      _showSnack(lalaCopy(_language, ko: '태그는 최대 8개까지.', en: 'Up to 8 tags.'));
      return;
    }
    setState(() => _tags.add(cleaned));
    _tagController.clear();
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty || body.isEmpty || _busy) return;
    final outcome = await requestCommunityAuthentication(
      context,
      controller: widget.authController,
      language: _language,
      actionLabel: lalaCopyMulti(
        _language,
        ko: '게시',
        en: 'publishing',
        ja: '投稿',
        zhHans: '发布',
        zhHant: '發布',
      ),
    );
    if (!mounted) return;
    if (outcome != CommunityAuthOutcome.alreadyAuthenticated) {
      if (outcome == CommunityAuthOutcome.signedInNow) setState(() {});
      return;
    }
    setState(() => _busy = true);
    try {
      await _client.createCommunityPost(
        title: title,
        body: body,
        tags: _tags.isEmpty ? null : _tags,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on LalaApiException {
      if (!mounted) return;
      setState(() => _busy = false);
      _showSnack(
        lalaCopyMulti(
          _language,
          ko: '게시에 실패했어요. 내용은 유지됐습니다.',
          en: 'Failed to publish. Your draft is still here.',
          ja: '投稿できませんでした。入力内容は保持されています。',
          zhHans: '发布失败，草稿已保留。',
          zhHant: '發布失敗，草稿已保留。',
        ),
      );
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      _showSnack(
        lalaCopy(_language, ko: '게시에 실패했어요.', en: 'Failed to publish.'),
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
          lalaCopy(_language, ko: '새 게시글', en: 'New Post'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              key: const ValueKey('community-post-submit'),
              onPressed: _canSubmit ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                disabledBackgroundColor: const Color(0xFFE2E8F0),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(lalaCopy(_language, ko: '게시', en: 'Post')),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (!isCommunityAuthenticated(widget.authController)) ...<Widget>[
              Container(
                key: const ValueKey('community-create-auth-notice'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: Text(
                  lalaCopyMulti(
                    _language,
                    ko: '작성 내용은 보존돼요. 게시할 때 Logto 로그인을 연결합니다.',
                    en: 'Your draft is preserved. LALA asks for Logto sign-in when you publish.',
                    ja: '入力内容は保持されます。投稿時にLogtoログインを案内します。',
                    zhHans: '草稿会保留，发布时将提示连接 Logto 登录。',
                    zhHant: '草稿會保留，發布時將提示連結 Logto 登入。',
                  ),
                  style: const TextStyle(
                    color: Color(0xFF9A3412),
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _titleController,
              maxLength: 160,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: lalaCopy(_language, ko: '제목', en: 'Title'),
                labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                alignLabelWithHint: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 1.6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bodyController,
              maxLength: 4000,
              minLines: 8,
              maxLines: 12,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: lalaCopy(_language, ko: '본문', en: 'Body'),
                labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                alignLabelWithHint: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 1.6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              lalaCopy(_language, ko: '태그', en: 'Tags'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagController,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addTag(),
                    decoration: InputDecoration(
                      hintText: lalaCopy(
                        _language,
                        ko: '태그 입력 후 엔터',
                        en: 'Type a tag and press enter',
                      ),
                      isDense: true,
                      prefixText: '#',
                      prefixStyle: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w900,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 1.6,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _addTag,
                  icon: const Icon(Icons.add_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            if (_tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _tags
                    .map(
                      (tag) => Chip(
                        label: Text(
                          '#$tag',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onDeleted: () => _removeTag(tag),
                        deleteIconColor: const Color(0xFF64748B),
                        backgroundColor: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.5),
                        labelStyle: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
