// ONMU P3c: 채팅방 화면.
// - REST 로 최초 메시지 로드(getChatMessages) + WebSocket 으로 실시간 수신.
// - 말풍선 리스트(본인 오른쪽 primary / 타인 왼쪽 회색). 최신이 하단, 자동 스크롤.
// - 하단 고정 입력 바(TextField + 전송). WebSocket 미연결 시에도 전송 시도.
// - 연결 상태 배지 + 로딩/에러/빈 상태 분기. SafeArea + 오버플로우 방지.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/features/community/presentation/community_api.dart';
import 'package:lala_next_app/features/community/presentation/chat_ws_client.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({super.key, required this.roomId});

  final String roomId;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

enum _LoadStatus { loading, data, error }

class _ChatRoomPageState extends State<ChatRoomPage> {
  late final LalaAppConfig _config;
  late LalaApiClient _client;
  late final ChatWsClient _ws;
  late final TextEditingController _inputController;
  late final ScrollController _scrollController;
  StreamSubscription<ChatMessage>? _messageSub;
  StreamSubscription<ChatWsStatus>? _statusSub;
  StreamSubscription<ChatWsError>? _errorSub;

  _LoadStatus _status = _LoadStatus.loading;
  List<ChatMessage> _messages = const <ChatMessage>[];
  String? _error;
  String? _currentUserId;
  ChatWsStatus _wsStatus = ChatWsStatus.disconnected;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _config = LalaAppConfig.fromEnvironment();
    _client = createCommunityClient(_config);
    _ws = ChatWsClient();
    _inputController = TextEditingController();
    _scrollController = ScrollController();
    _statusSub = _ws.status.listen(_onWsStatus);
    _errorSub = _ws.errors.listen(_onWsError);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initialize();
    });
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _statusSub?.cancel();
    _errorSub?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _ws.dispose();
    _client.close();
    super.dispose();
  }

  String get _language => _config.lang;

  Future<void> _initialize() async {
    // 현재 사용자 식별자(본인 말풍선 판별). 실패해도 채팅은 계속 진행.
    try {
      final me = await _client.getMe();
      _currentUserId = me.data?.userId;
    } on Object {
      _currentUserId = null;
    }
    if (!mounted) return;
    await _loadMessages();
    if (!mounted) return;
    await _connectWebSocket();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _status = _LoadStatus.loading;
      _error = null;
    });
    try {
      final envelope = await _client.getChatMessages(
        roomId: widget.roomId,
        limit: 50,
      );
      final data = envelope.data;
      final messages = data?.messages ?? const <ChatMessage>[];
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _status = _LoadStatus.data;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    } on LalaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message.trim().isEmpty ? _fallbackError() : e.message;
        _status = _LoadStatus.error;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = _fallbackError();
        _status = _LoadStatus.error;
      });
    }
  }

  Future<void> _connectWebSocket() async {
    final token = await _client.resolveWebSocketToken();
    if (token.isEmpty) {
      // 인증 미지원: 실시간 수신은 불가. REST 메시지 로드는 유지.
      setState(() => _wsStatus = ChatWsStatus.error);
      return;
    }
    final uri = _client.chatWebSocketUri(
      roomId: widget.roomId,
      token: token,
    );
    await _ws.connect(uri);
    // 연결 후 수신 스트림 구독(connect 이후에 구독해야 스트림이 활성).
    _messageSub ??= _ws.messages.listen(_onIncomingMessage);
  }

  void _onIncomingMessage(ChatMessage message) {
    // 방 필터(브로드캐스트는 동일 방에만 가지만 안전하게 가드).
    if (message.roomId != widget.roomId && message.roomId.isNotEmpty) return;
    setState(() {
      _messages = <ChatMessage>[..._messages, message];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  void _onWsStatus(ChatWsStatus next) {
    if (!mounted) return;
    setState(() => _wsStatus = next);
  }

  void _onWsError(ChatWsError error) {
    if (!mounted) return;
    final message = error.message ??
        lalaCopy(_language, ko: '메시지 전송에 실패했어요.', en: 'Failed to send message.');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  String _fallbackError() => lalaCopy(
        _language,
        ko: '메시지를 불러오지 못했어요.',
        en: 'Could not load messages.',
      );

  bool _isMine(ChatMessage message) {
    final me = _currentUserId;
    if (me == null || me.isEmpty) return false;
    final author = message.authorUserId;
    return author != null && author.isNotEmpty && author == me;
  }

  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent.isFinite) {
      _scrollController.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _ws.send(text);
    _inputController.clear();
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          lalaCopy(_language, ko: '채팅방', en: 'Chat room'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          _ConnectionBadge(status: _wsStatus, language: _language),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: _buildBody()),
            _ChatInputBar(
              controller: _inputController,
              sending: _sending,
              connected: _wsStatus == ChatWsStatus.connected,
              language: _language,
              onSend: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case _LoadStatus.loading:
        return const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        );
      case _LoadStatus.error:
        return _ChatErrorView(
          message: _error!,
          onRetry: _loadMessages,
          language: _language,
        );
      case _LoadStatus.data:
        if (_messages.isEmpty) {
          return _ChatEmptyView(language: _language);
        }
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          itemCount: _messages.length,
          itemBuilder: (context, index) {
            final message = _messages[index];
            return _MessageBubble(
              message: message,
              mine: _isMine(message),
              language: _language,
            );
          },
        );
    }
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({
    required this.status,
    required this.language,
  });

  final ChatWsStatus status;
  final String language;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      ChatWsStatus.connected => (
        const Color(0xFF22C55E),
        lalaCopy(language, ko: '온라인', en: 'Online'),
      ),
      ChatWsStatus.connecting => (
        const Color(0xFFF59E0B),
        lalaCopy(language, ko: '연결 중', en: 'Connecting'),
      ),
      ChatWsStatus.error => (
        const Color(0xFFEF4444),
        lalaCopy(language, ko: '연결 끊김', en: 'Offline'),
      ),
      ChatWsStatus.disconnected => (
        const Color(0xFF94A3B8),
        lalaCopy(language, ko: '미연결', en: 'Idle'),
      ),
    };
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.language,
  });

  final ChatMessage message;
  final bool mine;
  final String language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = shortAuthorLabel(message.authorUserId ?? '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFFE2E8F0),
                child: const Icon(
                  Icons.person_outline_rounded,
                  size: 16,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!mine && author.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Text(
                      author,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.74,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: mine
                        ? theme.colorScheme.primary
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(mine ? 16 : 4),
                      bottomRight: Radius.circular(mine ? 4 : 16),
                    ),
                  ),
                  child: Text(
                    message.body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: mine
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 4,
                    right: 4,
                    top: 3,
                  ),
                  child: Text(
                    formatRelativeTime(message.createdAt, language),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  const _ChatInputBar({
    required this.controller,
    required this.sending,
    required this.connected,
    required this.language,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final bool connected;
  final String language;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: const BoxDecoration(
        color: Colors.transparent,
        border: Border(
          top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
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
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: lalaCopy(
                  language,
                  ko: '메시지를 입력하세요',
                  en: 'Type a message',
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
            onPressed: sending ? null : onSend,
            icon: sending
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
              disabledBackgroundColor:
                  theme.colorScheme.primary.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatErrorView extends StatelessWidget {
  const _ChatErrorView({
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

class _ChatEmptyView extends StatelessWidget {
  const _ChatEmptyView({required this.language});
  final String language;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          lalaCopy(
            language,
            ko: '아직 메시지가 없어요.\n첫 인사를 남겨보세요!',
            en: 'No messages yet.\nSay hello!',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
