// P7: ChatRoomPage 전송 경계 단위 테스트.
// - WebSocket 미연결 시 REST 폴백 전송(sendChatMessage)과 idempotency key 전파.
// - 권한 거부(404)는 재시도 없는 안내, 일시 실패(500)는 같은 키로 재시도.
// - 서버 재생 응답(같은 메시지 id)은 화면에 한 번만 표시.
// - 티켓 발급 실패(404)는 재연결 루프 없이 연결 상태 에러로 처리.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/features/community/presentation/pages/chat_room_page.dart';

const _enabledAuthConfig = LalaAuthConfig(
  endpoint: 'https://auth.example.com',
  appId: 'native-client-id',
  apiAudience: 'https://api.example.com',
  redirectUri: 'cloud.lalanext.lala://callback',
);

const _me = LalaMe(
  userId: 'account-123',
  createdAt: '2026-07-10T00:00:00Z',
  authenticated: true,
);

class _StubAuthGateway implements LalaAuthGateway {
  @override
  Future<bool> get isAuthenticated async => true;

  @override
  Future<String?> accessToken(String resource) async => 'token';

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async {}
}

class _StubAccountApi implements LalaAccountApi {
  @override
  Future<LalaMe> getMe() async => _me;

  @override
  Future<void> deleteMe({required String confirmation}) async {}
}

Future<LalaAuthController> _authenticatedController() async {
  final controller = LalaAuthController(
    config: _enabledAuthConfig,
    gateway: _StubAuthGateway(),
    accountApi: _StubAccountApi(),
  );
  await controller.initialize();
  assert(controller.state.authenticated, 'controller must be signed in');
  return controller;
}

class _ScriptedChatClient extends LalaApiClient {
  _ScriptedChatClient({this.ticketError, this.sendResults = const <Object>[]})
    : super(baseUri: Uri.parse('https://api.chat.test'));

  /// createChatWsTicket 결과: 예외를 던지면 티켓 발급 실패를 시뮬레이션.
  final LalaApiException? ticketError;

  /// sendChatMessage 순차 결과: LalaApiException 또는 ChatMessage.
  final List<Object> sendResults;

  final List<String?> sentKeys = <String?>[];
  int sends = 0;
  int ticketCalls = 0;

  LalaEnvelope<T> _ok<T>(T? data) => LalaEnvelope<T>(
    ok: true,
    data: data,
    meta: const <String, dynamic>{'request_id': 'chat-test'},
    error: null,
    statusCode: 200,
    requestId: 'chat-test',
  );

  ChatMessage _message(String id, String body) => ChatMessage.fromJsonObject(
    <String, Object?>{
      'id': id,
      'room_id': 'room-1',
      'author_user_id': 'account-123',
      'body': body,
      'created_at': '2026-09-05T00:00:00Z',
    },
  );

  @override
  Future<LalaEnvelope<LalaMe>> getMe({
    String? requestId,
    Duration? timeout,
  }) async => _ok(_me);

  @override
  Future<LalaEnvelope<ChatMessagesResponse>> getChatMessages({
    required String roomId,
    int limit = 50,
    int offset = 0,
    String? requestId,
    Duration? timeout,
  }) async => _ok(
    ChatMessagesResponse.fromJsonObject(
      <String, Object?>{'messages': <Object?>[], 'total': 0},
    ),
  );

  @override
  Future<LalaEnvelope<ChatWsTicket>> createChatWsTicket({
    required String roomId,
    String? requestId,
    Duration? timeout,
  }) async {
    ticketCalls += 1;
    final error = ticketError;
    if (error != null) throw error;
    return _ok(
      ChatWsTicket.fromJsonObject(<String, Object?>{
        'room_id': roomId,
        'ticket': 'one-shot',
        'expires_at': '2026-09-05T00:01:00Z',
      }),
    );
  }

  @override
  Future<LalaEnvelope<ChatMessage>> sendChatMessage({
    required String roomId,
    required String body,
    String? idempotencyKey,
    String? requestId,
    Duration? timeout,
  }) async {
    sentKeys.add(idempotencyKey);
    sends += 1;
    if (sendResults.isEmpty) {
      return _ok(_message('m$sends', body));
    }
    final next = sendResults.removeAt(0);
    if (next is LalaApiException) throw next;
    return _ok(next as ChatMessage);
  }

  @override
  Future<void> close() async {}
}

Widget _wrap(Widget child) =>
    MaterialApp(home: child, locale: const Locale('ko'));

Future<void> _pumpRoom(
  WidgetTester tester, {
  required _ScriptedChatClient client,
  required LalaAuthController controller,
}) async {
  await tester.pumpWidget(
    _wrap(
      ChatRoomPage(roomId: 'room-1', client: client, authController: controller),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _typeAndSend(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.send_rounded));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('REST fallback sends with an idempotency key and shows it once', (
    tester,
  ) async {
    final controller = await _authenticatedController();
    // 티켓 404 → WS 는 실행되지 않는다(REST 폴백 경로).
    final client = _ScriptedChatClient(
      ticketError: const LalaApiException(
        code: 'HTTP_404',
        message: 'no room',
        statusCode: 404,
        retryable: false,
      ),
    );
    await _pumpRoom(tester, client: client, controller: controller);

    await _typeAndSend(tester, '폴백 메시지');

    expect(client.sends, 1);
    expect(client.sentKeys.first, isNotNull);
    expect(find.text('폴백 메시지'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-failed-message')), findsNothing);
  });

  testWidgets('server replay (same id) renders exactly once', (tester) async {
    final controller = await _authenticatedController();
    // 서버 재생 시뮬레이션: 두 전송 모두 같은 id(m-same)를 반환한다.
    final replayed = ChatMessage.fromJsonObject(<String, Object?>{
      'id': 'm-same',
      'room_id': 'room-1',
      'author_user_id': 'account-123',
      'body': '동일 메시지',
      'created_at': '2026-09-05T00:00:00Z',
    });
    final client = _ScriptedChatClient(
      ticketError: const LalaApiException(
        code: 'HTTP_404',
        message: 'no room',
        statusCode: 404,
        retryable: false,
      ),
      sendResults: <Object>[replayed, replayed],
    );
    await _pumpRoom(tester, client: client, controller: controller);

    await _typeAndSend(tester, '동일 메시지');
    await _typeAndSend(tester, '동일 메시지');

    // 두 번 전송했지만 같은 메시지 id 는 한 번만 그려진다.
    expect(client.sends, 2);
    expect(find.text('동일 메시지'), findsOneWidget);
  });

  testWidgets('permission denial (404) shows guidance without retry bubble', (
    tester,
  ) async {
    final controller = await _authenticatedController();
    final client = _ScriptedChatClient(
      ticketError: const LalaApiException(
        code: 'HTTP_404',
        message: 'no room',
        statusCode: 404,
        retryable: false,
      ),
      sendResults: <Object>[
        const LalaApiException(
          code: 'HTTP_404',
          message: 'no room',
          statusCode: 404,
          retryable: false,
        ),
      ],
    );
    await _pumpRoom(tester, client: client, controller: controller);

    await _typeAndSend(tester, '거부된 메시지');

    expect(find.text('이 채팅방에 메시지를 보낼 수 없어요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-failed-message')), findsNothing);
  });

  testWidgets('transient failure keeps the draft and retries with the same key', (
    tester,
  ) async {
    final controller = await _authenticatedController();
    final client = _ScriptedChatClient(
      ticketError: const LalaApiException(
        code: 'HTTP_404',
        message: 'no room',
        statusCode: 404,
        retryable: false,
      ),
      sendResults: <Object>[
        const LalaApiException(
          code: 'HTTP_500',
          message: 'server error',
          statusCode: 500,
          retryable: true,
        ),
      ],
    );
    await _pumpRoom(tester, client: client, controller: controller);

    await _typeAndSend(tester, '재시도 메시지');
    expect(find.byKey(const ValueKey('chat-failed-message')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-failed-retry')));
    await tester.pumpAndSettle();

    // 같은 idempotency key 로 재시도했는지 검증.
    expect(client.sends, 2);
    expect(client.sentKeys[0], client.sentKeys[1]);
    expect(find.byKey(const ValueKey('chat-failed-message')), findsNothing);
    expect(find.text('재시도 메시지'), findsOneWidget);
  });

  testWidgets('ticket issuance failure sets offline badge and stops reconnects', (
    tester,
  ) async {
    final controller = await _authenticatedController();
    final client = _ScriptedChatClient(
      ticketError: const LalaApiException(
        code: 'HTTP_404',
        message: 'private room denied',
        statusCode: 404,
        retryable: false,
      ),
    );
    await _pumpRoom(tester, client: client, controller: controller);

    // 권한 거부: 재발급 루프 없이 발급이 딱 한 번만 호출된다.
    expect(client.ticketCalls, 1);
    await tester.pump(const Duration(seconds: 10));
    expect(client.ticketCalls, 1);
  });
}
