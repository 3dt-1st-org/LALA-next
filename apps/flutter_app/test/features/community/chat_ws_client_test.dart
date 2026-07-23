// ONMU P3c: ChatWsClient 프레임 파싱 + 수명주기 단위 테스트.
// 실제 소켓 연결 없이 parseFrame 정적 헬퍼와 공개 스트림 수명주기를 검증한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:lala_next_app/features/community/presentation/chat_ws_client.dart';

void main() {
  group('ChatWsClient.parseFrame', () {
    test('parses a message frame into a ChatMessage', () {
      const frame =
          '{"type":"message","data":{"id":"m1","room_id":"r1",'
          '"author_user_id":"u1","body":"안녕","created_at":"2026-07-22T09:00:00Z"}}';
      final parsed = ChatWsClient.parseFrame(frame);
      expect(parsed, isNotNull);
      expect(parsed!.message, isA<ChatMessage>());
      expect(parsed.error, isNull);
      final message = parsed.message!;
      expect(message.id, 'm1');
      expect(message.roomId, 'r1');
      expect(message.authorUserId, 'u1');
      expect(message.body, '안녕');
    });

    test('parses an error frame into a ChatWsError', () {
      const frame =
          '{"type":"error","error":{"code":"INVALID_MESSAGE","message":"body is required"}}';
      final parsed = ChatWsClient.parseFrame(frame);
      expect(parsed, isNotNull);
      expect(parsed!.error, isA<ChatWsError>());
      expect(parsed.message, isNull);
      final error = parsed.error!;
      expect(error.code, 'INVALID_MESSAGE');
      expect(error.message, 'body is required');
    });

    test('returns null for non-string, malformed JSON, or unknown type', () {
      expect(ChatWsClient.parseFrame(42), isNull);
      expect(ChatWsClient.parseFrame('not json'), isNull);
      expect(ChatWsClient.parseFrame('{"type":"ping"}'), isNull);
      expect(
        ChatWsClient.parseFrame('{"type":"message","data":"not-a-map"}'),
        isNull,
      );
      expect(
        ChatWsClient.parseFrame('{"type":"error","error":"not-a-map"}'),
        isNull,
      );
    });

    test('tolerates a null author_user_id in message data', () {
      const frame =
          '{"type":"message","data":{"id":"m2","room_id":"r1",'
          '"author_user_id":null,"body":"익명","created_at":"2026-07-22T09:01:00Z"}}';
      final parsed = ChatWsClient.parseFrame(frame);
      expect(parsed, isNotNull);
      final message = parsed!.message!;
      expect(message.authorUserId, isNull);
      expect(message.body, '익명');
    });
  });

  group('ChatWsClient lifecycle', () {
    test('starts disconnected and disconnect is a safe no-op before connect',
        () async {
      final client = ChatWsClient(reconnectDelays: const []);
      expect(client.currentStatus, ChatWsStatus.disconnected);
      // send before connect should not throw.
      client.send('hi');
      await client.disconnect();
      expect(client.currentStatus, ChatWsStatus.disconnected);
      await client.dispose();
    });

    test('status stream emits nothing for a redundant disconnect', () async {
      final client = ChatWsClient(reconnectDelays: const []);
      final statuses = <ChatWsStatus>[];
      final sub = client.status.listen(statuses.add);
      // disconnect emits a status transition only when changed; from
      // disconnected → disconnected is a no-op so no emission here.
      await client.disconnect();
      expect(client.currentStatus, ChatWsStatus.disconnected);
      await sub.cancel();
      await client.dispose();
      expect(statuses, isEmpty);
    });
  });
}
