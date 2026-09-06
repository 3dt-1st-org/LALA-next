// ONMU P3c: ChatWsClient 프레임 파싱 + 수명주기 단위 테스트.
// 실제 소켓 연결 없이 parseFrame 정적 헬퍼와 공개 스트림 수명주기를 검증한다.
import 'dart:async';

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

  group('ChatWsClient.encodeSendFrame', () {
    test('matches the strict server schema without extra fields', () {
      final frame = ChatWsClient.encodeSendFrame('안녕');
      expect(frame, '{"body":"안녕"}');
      // ``type`` 등 추가 필드는 서버 extra=forbid 로 거부된다.
      expect(frame.contains('type'), isFalse);
    });

    test('carries the idempotency key when provided', () {
      final frame = ChatWsClient.encodeSendFrame(
        'hello',
        idempotencyKey: 'retry-9',
      );
      expect(frame, '{"body":"hello","idempotency_key":"retry-9"}');
    });
  });

  group('ChatWsClient lifecycle', () {
    test(
      'starts disconnected and disconnect is a safe no-op before connect',
      () async {
        final client = ChatWsClient(reconnectDelays: const []);
        expect(client.currentStatus, ChatWsStatus.disconnected);
        // send before connect should not throw.
        client.send('hi');
        await client.disconnect();
        expect(client.currentStatus, ChatWsStatus.disconnected);
        await client.dispose();
      },
    );

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

    testWidgets('provider failure does not auto-retry', (tester) async {
      final client = ChatWsClient(reconnectDelays: const [Duration(seconds: 1)]);
      final requested = <int>[];
      Future<Uri> provider() async {
        requested.add(requested.length + 1);
        throw StateError('ticket unavailable');
      }

      unawaited(client.connect(provider));
      await tester.pump(const Duration(milliseconds: 10));
      expect(requested, [1]);
      expect(client.currentStatus, ChatWsStatus.error);

      // 호출측 정책이 재시도를 결정한다: 타이머로 재시도하지 않는다.
      await tester.pump(const Duration(seconds: 10));
      expect(requested, [1]);
      await client.dispose();
    });

    testWidgets('socket termination refetches a fresh URI per attempt', (
      tester,
    ) async {
      final client = ChatWsClient(reconnectDelays: const [Duration(seconds: 1)]);
      final attempts = <int>[];
      Future<Uri> provider() async {
        attempts.add(attempts.length + 1);
        return Uri.parse('ws://127.0.0.1:1/room/ws?ticket=t${attempts.length}');
      }

      unawaited(client.connect(provider));
      await tester.pump(const Duration(milliseconds: 50));
      expect(attempts, [1]);

      // 연결 종료(서버/네트워크) 시뮬레이션 → 자동 재연결 예약.
      client.debugHandleTermination('done');
      expect(client.currentStatus, ChatWsStatus.error);

      // 첫 재시도(1초 후)에서 공급자를 다시 호출한다 = 새 티켓 발급.
      await tester.pump(const Duration(seconds: 2));
      expect(attempts.length, greaterThanOrEqualTo(2));

      client.debugHandleTermination('done');
      await client.disconnect();
      await tester.pump(const Duration(seconds: 5));
      final count = attempts.length;
      await tester.pump(const Duration(seconds: 5));
      expect(attempts.length, count);
      await client.dispose();
    });
  });
}
