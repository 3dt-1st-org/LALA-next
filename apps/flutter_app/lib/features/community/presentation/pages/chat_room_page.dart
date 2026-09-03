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
import 'package:lala_next_app/features/community/presentation/community_auth_guard.dart';
import 'package:lala_next_app/features/community/presentation/chat_ws_client.dart';
import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({
    super.key,
    required this.roomId,
    this.initialConfig = const LalaAppConfig.fromEnvironment(),
    this.authController,
  });

  final String roomId;
  final LalaAppConfig initialConfig;
  final LalaAuthController? authController;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

enum _LoadStatus { authRequired, loading, data, error }

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
  bool _initializing = false;
  bool _sending = false;
  String? _pendingDraft;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
    _client = createCommunityClient(_config);
    _ws = ChatWsClient();
    _inputController = TextEditingController();
    _scrollController = ScrollController();
    _statusSub = _ws.status.listen(_onWsStatus);
    _errorSub = _ws.errors.listen(_onWsError);
    widget.authController?.addListener(_onAuthChanged);
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
    widget.authController?.removeListener(_onAuthChanged);
    _client.close();
    super.dispose();
  }

  String get _language => OnboardingState.language;

  bool get _authenticated => isCommunityAuthenticated(widget.authController);

  void _onAuthChanged() {
    if (!mounted) return;
    if (_authenticated && _status == _LoadStatus.authRequired) {
      unawaited(_initialize());
      return;
    }
    if (!_authenticated && _status != _LoadStatus.authRequired) {
      unawaited(_ws.disconnect());
      setState(() {
        _messages = const <ChatMessage>[];
        _currentUserId = null;
        _status = _LoadStatus.authRequired;
        _wsStatus = ChatWsStatus.disconnected;
      });
    }
  }

  Future<void> _initialize() async {
    if (_initializing) return;
    if (!_authenticated) {
      setState(() => _status = _LoadStatus.authRequired);
      return;
    }
    _initializing = true;
    try {
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
    } finally {
      _initializing = false;
    }
  }

  Future<void> _loadMessages() async {
    if (!_authenticated) {
      setState(() => _status = _LoadStatus.authRequired);
      return;
    }
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
      if (!_authenticated) {
        setState(() => _status = _LoadStatus.authRequired);
        return;
      }
      setState(() {
        _messages = messages;
        _status = _LoadStatus.data;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    } on LalaApiException {
      if (!mounted) return;
      if (!_authenticated) {
        setState(() => _status = _LoadStatus.authRequired);
        return;
      }
      setState(() {
        _error = _fallbackError();
        _status = _LoadStatus.error;
      });
    } on Object {
      if (!mounted) return;
      if (!_authenticated) {
        setState(() => _status = _LoadStatus.authRequired);
        return;
      }
      setState(() {
        _error = _fallbackError();
        _status = _LoadStatus.error;
      });
    }
  }

  Future<void> _connectWebSocket() async {
    if (!_authenticated) {
      setState(() => _wsStatus = ChatWsStatus.disconnected);
      return;
    }
    final token = await _client.resolveWebSocketToken();
    if (!mounted || !_authenticated) {
      if (mounted) setState(() => _wsStatus = ChatWsStatus.disconnected);
      return;
    }
    if (token.isEmpty) {
      // 인증 미지원: 실시간 수신은 불가. REST 메시지 로드는 유지.
      setState(() => _wsStatus = ChatWsStatus.error);
      return;
    }
    final uri = _client.chatWebSocketUri(roomId: widget.roomId, token: token);
    await _ws.connect(uri);
    // 연결 후 수신 스트림 구독(connect 이후에 구독해야 스트림이 활성).
    _messageSub ??= _ws.messages.listen(_onIncomingMessage);
  }

  void _onIncomingMessage(ChatMessage message) {
    // 방 필터(브로드캐스트는 동일 방에만 가지만 안전하게 가드).
    if (message.roomId != widget.roomId && message.roomId.isNotEmpty) return;
    setState(() {
      _messages = <ChatMessage>[..._messages, message];
      if (_isMine(message) && message.body.trim() == _pendingDraft) {
        _pendingDraft = null;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  void _onWsStatus(ChatWsStatus next) {
    if (!mounted) return;
    setState(() => _wsStatus = next);
  }

  void _onWsError(ChatWsError _) {
    if (!mounted) return;
    final draft = _pendingDraft;
    if (draft != null && _inputController.text.trim().isEmpty) {
      _inputController.text = draft;
      _inputController.selection = TextSelection.collapsed(
        offset: _inputController.text.length,
      );
    }
    _pendingDraft = null;
    final message = lalaCopyMulti(
      _language,
      ko: '메시지를 보내지 못했어요. 입력 내용을 복원했습니다.',
      en: 'Message not sent. Your text was restored.',
      ja: 'メッセージを送信できませんでした。入力内容を復元しました。',
      zhHans: '消息未发送，输入内容已恢复。',
      zhHant: '訊息未傳送，輸入內容已還原。',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  String _fallbackError() => lalaCopyMulti(
    _language,
    ko: '메시지를 불러오지 못했어요.',
    en: 'Could not load messages.',
    ja: 'メッセージを読み込めませんでした。',
    zhHans: '无法加载消息。',
    zhHant: '無法載入訊息。',
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
    final outcome = await requestCommunityAuthentication(
      context,
      controller: widget.authController,
      language: _language,
      actionLabel: lalaCopyMulti(
        _language,
        ko: '메시지 보내기',
        en: 'sending messages',
        ja: 'メッセージ送信',
        zhHans: '发送消息',
        zhHant: '傳送訊息',
      ),
    );
    if (!mounted || outcome != CommunityAuthOutcome.alreadyAuthenticated) {
      return;
    }
    if (_wsStatus != ChatWsStatus.connected) {
      _onWsError(const ChatWsError(code: 'not_connected'));
      return;
    }
    setState(() => _sending = true);
    _pendingDraft = text;
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
          lalaCopyMulti(
            _language,
            ko: '채팅방',
            en: 'Chat room',
            ja: 'チャットルーム',
            zhHans: '聊天室',
            zhHant: '聊天室',
          ),
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
      case _LoadStatus.authRequired:
        return CommunityAuthenticationView(
          language: _language,
          controller: widget.authController,
          purpose: lalaCopyMulti(
            _language,
            ko: '채팅',
            en: 'chat',
            ja: 'チャット',
            zhHans: '聊天',
            zhHant: '聊天',
          ),
          onAuthenticated: () {
            if (_status == _LoadStatus.authRequired) {
              unawaited(_initialize());
            }
          },
        );
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
  const _ConnectionBadge({required this.status, required this.language});

  final ChatWsStatus status;
  final String language;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      ChatWsStatus.connected => (
        const Color(0xFF22C55E),
        lalaCopyMulti(
          language,
          ko: '온라인',
          en: 'Online',
          ja: 'オンライン',
          zhHans: '在线',
          zhHant: '線上',
        ),
      ),
      ChatWsStatus.connecting => (
        const Color(0xFFF59E0B),
        lalaCopyMulti(
          language,
          ko: '연결 중',
          en: 'Connecting',
          ja: '接続中',
          zhHans: '连接中',
          zhHant: '連線中',
        ),
      ),
      ChatWsStatus.error => (
        const Color(0xFFEF4444),
        lalaCopyMulti(
          language,
          ko: '연결 끊김',
          en: 'Offline',
          ja: 'オフライン',
          zhHans: '已断开',
          zhHant: '已斷線',
        ),
      ),
      ChatWsStatus.disconnected => (
        const Color(0xFF94A3B8),
        lalaCopyMulti(
          language,
          ko: '미연결',
          en: 'Idle',
          ja: '未接続',
          zhHans: '未连接',
          zhHant: '未連線',
        ),
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
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
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
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
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
                  padding: const EdgeInsets.only(left: 4, right: 4, top: 3),
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
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
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
                hintText: lalaCopyMulti(
                  language,
                  ko: '메시지를 입력하세요',
                  en: 'Type a message',
                  ja: 'メッセージを入力',
                  zhHans: '输入消息',
                  zhHant: '輸入訊息',
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
              disabledBackgroundColor: theme.colorScheme.primary.withValues(
                alpha: 0.4,
              ),
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

class _ChatEmptyView extends StatelessWidget {
  const _ChatEmptyView({required this.language});
  final String language;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          lalaCopyMulti(
            language,
            ko: '아직 메시지가 없어요.\n첫 인사를 남겨보세요!',
            en: 'No messages yet.\nSay hello!',
            ja: 'まだメッセージがありません。\n最初のあいさつをどうぞ！',
            zhHans: '还没有消息。\n来打个招呼吧！',
            zhHant: '還沒有訊息。\n來打個招呼吧！',
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
