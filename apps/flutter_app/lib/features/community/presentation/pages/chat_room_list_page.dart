// ONMU P3c: 커뮤니티 채팅방 목록.
// - 채팅방 세로 리스트(이름/생성 시간).
// - FAB "+ 방 만들기" → 방 생성 다이얼로그(OAuth 필요: 미인증 시 안내).
// - 탭 → /community/chat/:id 채팅방.
// - 당겨서 새로고침 + 페이지네이션. 로딩/에러/빈 상태 분기.
// - SafeArea + ColorScheme.fromSeed 테마 준수.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/community/presentation/community_api.dart';
import 'package:lala_next_app/features/community/presentation/community_auth_guard.dart';
import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

class ChatRoomListPage extends StatefulWidget {
  const ChatRoomListPage({
    this.initialConfig = const LalaAppConfig.fromEnvironment(),
    this.authController,
    super.key,
  });

  final LalaAppConfig initialConfig;
  final LalaAuthController? authController;

  @override
  State<ChatRoomListPage> createState() => _ChatRoomListPageState();
}

enum _ListStatus { authRequired, loading, data, error }

class _ChatRoomListPageState extends State<ChatRoomListPage> {
  late final LalaAppConfig _config;
  late LalaApiClient _client;
  final ScrollController _scrollController = ScrollController();

  _ListStatus _status = _ListStatus.loading;
  List<ChatRoom> _rooms = const <ChatRoom>[];
  int _total = 0;
  String? _error;

  static const int _pageSize = 20;
  bool _isLoadingMore = false;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
    _client = createCommunityClient(_config);
    _scrollController.addListener(_onScroll);
    widget.authController?.addListener(_onAuthChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(initial: true);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    widget.authController?.removeListener(_onAuthChanged);
    _client.close();
    super.dispose();
  }

  String get _language => OnboardingState.language;
  bool get _canCreate => isCommunityAuthenticated(widget.authController);

  void _onAuthChanged() {
    if (!mounted) return;
    if (!_canCreate) {
      if (_status != _ListStatus.authRequired || _rooms.isNotEmpty) {
        setState(() {
          _rooms = const <ChatRoom>[];
          _total = 0;
          _hasMore = false;
          _isLoadingMore = false;
          _status = _ListStatus.authRequired;
        });
      }
      return;
    }
    if (_status == _ListStatus.authRequired) {
      _load(initial: true);
    } else {
      setState(() {});
    }
  }

  void _onScroll() {
    if (_status != _ListStatus.data) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _load({bool initial = false}) async {
    if (!_canCreate) {
      setState(() => _status = _ListStatus.authRequired);
      return;
    }
    if (initial) {
      setState(() {
        _status = _ListStatus.loading;
        _error = null;
      });
    }
    try {
      final envelope = await _client.getChatRooms(limit: _pageSize, offset: 0);
      final data = envelope.data;
      final rooms = data?.rooms ?? const <ChatRoom>[];
      final total = data?.total ?? rooms.length;
      if (!mounted) return;
      if (!_canCreate) {
        setState(() => _status = _ListStatus.authRequired);
        return;
      }
      setState(() {
        _rooms = rooms;
        _total = total;
        _hasMore = rooms.length < total;
        _status = _ListStatus.data;
      });
    } on LalaApiException {
      if (!mounted) return;
      if (!_canCreate) {
        setState(() => _status = _ListStatus.authRequired);
        return;
      }
      setState(() {
        _error = _fallbackError();
        _status = _ListStatus.error;
      });
    } on Object {
      if (!mounted) return;
      if (!_canCreate) {
        setState(() => _status = _ListStatus.authRequired);
        return;
      }
      setState(() {
        _error = _fallbackError();
        _status = _ListStatus.error;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    final offset = _rooms.length;
    try {
      final envelope = await _client.getChatRooms(
        limit: _pageSize,
        offset: offset,
      );
      final data = envelope.data;
      final more = data?.rooms ?? const <ChatRoom>[];
      if (!mounted) return;
      if (!_canCreate) {
        setState(() {
          _isLoadingMore = false;
          _status = _ListStatus.authRequired;
        });
        return;
      }
      setState(() {
        _rooms = <ChatRoom>[..._rooms, ...more];
        _hasMore = _rooms.length < (data?.total ?? _rooms.length);
        _isLoadingMore = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        if (!_canCreate) _status = _ListStatus.authRequired;
      });
    }
  }

  String _fallbackError() => lalaCopyMulti(
    _language,
    ko: '채팅방을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
    en: 'Could not load chat rooms. Please try again shortly.',
    ja: 'チャットルームを読み込めませんでした。しばらくしてからもう一度お試しください。',
    zhHans: '无法加载聊天室，请稍后重试。',
    zhHant: '無法載入聊天室，請稍後重試。',
  );

  Future<void> _openCreate() async {
    if (!_canCreate) {
      await requestCommunityAuthentication(
        context,
        controller: widget.authController,
        language: _language,
        actionLabel: lalaCopyMulti(
          _language,
          ko: '채팅방 만들기',
          en: 'creating a chat room',
          ja: 'チャットルーム作成',
          zhHans: '创建聊天室',
          zhHant: '建立聊天室',
        ),
      );
      return;
    }
    final name = await _showCreateDialog();
    if (name == null || name.trim().isEmpty) return;
    try {
      await _client.createChatRoom(name: name.trim());
      if (!mounted) return;
      _load(initial: true);
    } on LalaApiException {
      if (!mounted) return;
      _showSnack(
        lalaCopyMulti(
          _language,
          ko: '방 생성에 실패했어요.',
          en: 'Failed to create room.',
          ja: 'ルーム作成に失敗しました。',
          zhHans: '创建房间失败。',
          zhHant: '建立房間失敗。',
        ),
      );
    } on Object {
      if (!mounted) return;
      _showSnack(
        lalaCopyMulti(
          _language,
          ko: '방 생성에 실패했어요.',
          en: 'Failed to create room.',
          ja: 'ルーム作成に失敗しました。',
          zhHans: '创建房间失败。',
          zhHant: '建立房間失敗。',
        ),
      );
    }
  }

  Future<String?> _showCreateDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            lalaCopyMulti(
              _language,
              ko: '새 채팅방',
              en: 'New chat room',
              ja: '新しいチャットルーム',
              zhHans: '新聊天室',
              zhHant: '新聊天室',
            ),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 120,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
            decoration: InputDecoration(
              hintText: lalaCopyMulti(
                _language,
                ko: '방 이름',
                en: 'Room name',
                ja: 'ルーム名',
                zhHans: '房间名称',
                zhHant: '房間名稱',
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                lalaCopyMulti(
                  _language,
                  ko: '취소',
                  en: 'Cancel',
                  ja: 'キャンセル',
                  zhHans: '取消',
                  zhHant: '取消',
                ),
              ),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: Text(
                lalaCopyMulti(
                  _language,
                  ko: '만들기',
                  en: 'Create',
                  ja: '作成',
                  zhHans: '创建',
                  zhHant: '建立',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  void _openRoom(ChatRoom room) {
    context.push(LalaRoutePaths.communityChatRoomFor(room.id));
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
            ko: '채팅',
            en: 'Chat',
            ja: 'チャット',
            zhHans: '聊天',
            zhHant: '聊天',
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
            } else {
              context.go(LalaRoutePaths.community);
            }
          },
        ),
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
        icon: const Icon(Icons.add_rounded),
        label: Text(
          lalaCopyMulti(
            _language,
            ko: '방 만들기',
            en: 'New room',
            ja: 'ルームを作る',
            zhHans: '创建房间',
            zhHant: '建立房間',
          ),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case _ListStatus.authRequired:
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
            if (_status == _ListStatus.authRequired) {
              _load(initial: true);
            }
          },
        );
      case _ListStatus.loading:
        return const _ListLoadingView();
      case _ListStatus.error:
        return _ListErrorView(
          message: _error!,
          onRetry: () => _load(initial: true),
        );
      case _ListStatus.data:
        if (_rooms.isEmpty) {
          return _ListEmptyView(language: _language);
        }
        return _RoomListView(
          controller: _scrollController,
          rooms: _rooms,
          total: _total,
          isLoadingMore: _isLoadingMore,
          language: _language,
          onTap: _openRoom,
        );
    }
  }
}

class _ListLoadingView extends StatelessWidget {
  const _ListLoadingView();

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
              '채팅방을 불러오는 중...',
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

class _ListErrorView extends StatelessWidget {
  const _ListErrorView({required this.message, required this.onRetry});
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
              // Why: the sheet reads the widget locale, so route it through
              // the SSOT normalizer rather than a raw locale code.
              label: Text(
                lalaCopyMulti(
                  normalizeLalaLanguage(
                    Localizations.localeOf(context).languageCode,
                  ),
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

class _ListEmptyView extends StatelessWidget {
  const _ListEmptyView({required this.language});
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
                  Icons.chat_bubble_outline_rounded,
                  size: 40,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(height: 12),
                Text(
                  lalaCopyMulti(
                    language,
                    ko: '아직 채팅방이 없어요.\n첫 방을 만들어보세요!',
                    en: 'No chat rooms yet.\nCreate the first one!',
                    ja: 'まだチャットルームがありません。\n最初のルームを作ってみましょう！',
                    zhHans: '还没有聊天室。\n来创建第一个吧！',
                    zhHant: '還沒有聊天室。\n來建立第一個吧！',
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

class _RoomListView extends StatelessWidget {
  const _RoomListView({
    required this.controller,
    required this.rooms,
    required this.total,
    required this.isLoadingMore,
    required this.language,
    required this.onTap,
  });

  final ScrollController controller;
  final List<ChatRoom> rooms;
  final int total;
  final bool isLoadingMore;
  final String language;
  final ValueChanged<ChatRoom> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: rooms.length + (isLoadingMore ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == rooms.length) {
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
        final room = rooms[index];
        return _ChatRoomCard(
          room: room,
          language: language,
          onTap: () => onTap(room),
        );
      },
    );
  }
}

class _ChatRoomCard extends StatelessWidget {
  const _ChatRoomCard({
    required this.room,
    required this.language,
    required this.onTap,
  });

  final ChatRoom room;
  final String language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.6,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.tag_rounded,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatRelativeTime(room.createdAt, language),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF94A3B8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}
