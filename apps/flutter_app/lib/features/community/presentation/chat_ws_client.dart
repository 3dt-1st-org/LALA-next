// ONMU P3c: 커뮤니티 채팅 WebSocket 클라이언트.
// - ws://{baseUri}/api/v1/community/chat/rooms/{roomId}/ws?token={bearer} 연결.
// - web_socket_channel(모바일+웹 공용) 의 sink/stream 으로 송수신.
// - 서버 브로드캐스트 {"type":"message","data":{...}} → ChatMessage 로 파싱하여 노출.
// - {"type":"error","error":{"code":...}} → ChatWsError 로 노출.
// - 예기치 않은 종료 시 지수 백오프로 자동 재연결. disconnect() 로 명시 종료.
import 'dart:async';
import 'dart:convert';

import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:meta/meta.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket 연결 상태.
enum ChatWsStatus { disconnected, connecting, connected, error }

/// 서버가 보낸 에러 프레임.
class ChatWsError {
  const ChatWsError({this.code, this.message});

  final String? code;
  final String? message;
}

/// 커뮤니티 채팅용 WebSocket 클라이언트.
///
/// 페이지 StatefulWidget 의 수명주기에 맞춰 사용:
/// initState → connect, dispose → disconnect. 수신 메시지는 [messages] 스트림을
/// 구독하고, 연결 상태 변화는 [status] 스트림으로 관찰한다.
class ChatWsClient {
  ChatWsClient({this.reconnectDelays = _defaultReconnectDelays});

  /// 재연결 백오프 간격. 빈 리스트면 자동 재연결 비활성.
  final List<Duration> reconnectDelays;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;
  final StreamController<ChatMessage> _messages =
      StreamController<ChatMessage>.broadcast();
  final StreamController<ChatWsStatus> _status =
      StreamController<ChatWsStatus>.broadcast();
  final StreamController<ChatWsError> _errors =
      StreamController<ChatWsError>.broadcast();

  ChatWsStatus _currentStatus = ChatWsStatus.disconnected;
  bool _manuallyClosed = false;
  int _reconnectAttempt = 0;
  String? _activeUri;

  /// 수신 메시지 스트림(구독만).
  Stream<ChatMessage> get messages => _messages.stream;

  /// 연결 상태 변화 스트림.
  Stream<ChatWsStatus> get status => _status.stream;

  /// 서버 에러 프레임 스트림.
  Stream<ChatWsError> get errors => _errors.stream;

  /// 현재 연결 상태.
  ChatWsStatus get currentStatus => _currentStatus;

  /// [uri] 로 연결한다. 이미 연결 중이면 무시한다.
  Future<void> connect(Uri uri) async {
    if (_channel != null) return;
    _manuallyClosed = false;
    _activeUri = uri.toString();
    _setStatus(ChatWsStatus.connecting);
    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _socketSub = channel.stream.listen(
        _handleFrame,
        onError: (Object error) => _handleTermination('stream_error'),
        onDone: () => _handleTermination('done'),
        cancelOnError: true,
      );
      _reconnectAttempt = 0;
      _setStatus(ChatWsStatus.connected);
    } on Object {
      _channel = null;
      _socketSub = null;
      _setStatus(ChatWsStatus.error);
      _scheduleReconnect();
    }
  }

  /// 텍스트 메시지를 전송한다. 미연결 시 무시.
  void send(String body) {
    final channel = _channel;
    if (channel == null) return;
    final text = body.trim();
    if (text.isEmpty) return;
    channel.sink.add(jsonEncode(<String, dynamic>{
      'type': 'message',
      'body': text,
    }));
  }

  /// 연결을 명시적으로 종료한다. 이후 재연결 시도는 하지 않는다.
  Future<void> disconnect() async {
    _manuallyClosed = true;
    await _socketSub?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _socketSub = null;
    _activeUri = null;
    _setStatus(ChatWsStatus.disconnected);
  }

  /// 스트림 컨트롤러와 소켓 자원을 모두 해제한다. dispose 에서 호출.
  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
    await _status.close();
    await _errors.close();
  }

  void _handleFrame(dynamic frame) {
    final parsed = parseFrame(frame);
    if (parsed == null) return;
    if (parsed.message != null) {
      _messages.add(parsed.message!);
    } else if (parsed.error != null) {
      _errors.add(parsed.error!);
    }
  }

  /// 단일 수신 프레임을 파싱해 테스트 가능한 결과를 반환한다.
  /// [frame] 이 문자열이 아니거나 JSON 이 아니면 null. 그 외에는
  /// message 또는 error 필드 중 하나가 채워진 레코드를 반환한다.
  @visibleForTesting
  static ({ChatMessage? message, ChatWsError? error})? parseFrame(
    dynamic frame,
  ) {
    if (frame is! String) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(frame);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final type = decoded['type'];
    if (type == 'message') {
      final data = decoded['data'];
      if (data is Map<String, dynamic>) {
        return (message: ChatMessage.fromJsonObject(data), error: null);
      }
      return null;
    }
    if (type == 'error') {
      final rawError = decoded['error'];
      if (rawError is Map<String, dynamic>) {
        return (
          message: null,
          error: ChatWsError(
            code: rawError['code']?.toString(),
            message: rawError['message']?.toString(),
          ),
        );
      }
    }
    return null;
  }

  void _handleTermination(String reason) {
    _channel = null;
    _socketSub = null;
    if (_manuallyClosed) {
      _setStatus(ChatWsStatus.disconnected);
      return;
    }
    _setStatus(ChatWsStatus.error);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    final uri = _activeUri;
    if (uri == null || _manuallyClosed) return;
    if (reconnectDelays.isEmpty) return;
    final index =
        _reconnectAttempt < reconnectDelays.length
        ? _reconnectAttempt
        : reconnectDelays.length - 1;
    final delay = reconnectDelays[index];
    _reconnectAttempt += 1;
    Timer(delay, () {
      if (_manuallyClosed) return;
      connect(Uri.parse(uri));
    });
  }

  void _setStatus(ChatWsStatus next) {
    if (_currentStatus == next) return;
    _currentStatus = next;
    if (!_status.isClosed) _status.add(next);
  }
}

const List<Duration> _defaultReconnectDelays = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
];
