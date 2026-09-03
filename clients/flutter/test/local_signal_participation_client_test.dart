import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:test/test.dart';

void main() {
  test('Local Signal participation uses the governed API contract', () async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..httpClientAdapter = _Adapter((request) async {
        requests.add(request);
        if (request.uri.path.endsWith('/comments') && request.method == 'GET') {
          return _json(<String, Object?>{
            'items': <Object?>[],
            'next_cursor': null,
            'has_more': false,
            'context': <String, Object?>{'language': 'ko'},
          });
        }
        return _json(<String, Object?>{
          'id': _signalId,
          'kind': 'place_tip',
          'status': 'draft',
          'moderation_state': 'unreviewed',
          'visibility': 'private',
          'source_language': 'ko',
          'title': '제목',
          'body': '본문',
          'locality_level': 'district',
          'locality_code': null,
          'commercial_disclosure': 'none',
          'observation_date': '2026-09-03',
          'place_links': <Object?>[],
        });
      });
    final client = LalaApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      bearerToken: 'test-token',
      dio: dio,
    );
    addTearDown(client.close);

    await client.getLocalSignal(signalId: _signalId, language: 'ko');
    await client.getLocalSignalComments(signalId: _signalId, language: 'ko');
    await client.createLocalSignalDraft(draft: _draft);
    await client.updateLocalSignalDraft(signalId: _signalId, patch: _draft);
    await client.submitLocalSignalDraft(signalId: _signalId);
    await client.setLocalSignalReaction(
      signalId: _signalId,
      reactionType: 'useful',
      active: true,
    );
    await client.setLocalSignalReaction(
      signalId: _signalId,
      reactionType: 'useful',
      active: false,
    );
    await client.setLocalSignalSaved(signalId: _signalId, active: true);
    await client.setLocalSignalSaved(signalId: _signalId, active: false);
    await client.createLocalSignalComment(
      signalId: _signalId,
      sourceLanguage: 'ko',
      body: '댓글',
    );
    await client.reportLocalSignal(
      signalId: _signalId,
      reasonCode: 'misleading_place',
    );
    await client.deleteLocalSignalDraft(signalId: _signalId);

    expect(
      requests.map((request) => '${request.method} ${request.uri.path}'),
      <String>[
        'GET /api/v1/community/signals/$_signalId',
        'GET /api/v1/community/signals/$_signalId/comments',
        'POST /api/v1/community/signals',
        'PATCH /api/v1/community/signals/$_signalId',
        'POST /api/v1/community/signals/$_signalId/submit',
        'PUT /api/v1/community/signals/$_signalId/reactions/useful',
        'DELETE /api/v1/community/signals/$_signalId/reactions/useful',
        'PUT /api/v1/community/signals/$_signalId/save',
        'DELETE /api/v1/community/signals/$_signalId/save',
        'POST /api/v1/community/signals/$_signalId/comments',
        'POST /api/v1/community/signals/$_signalId/reports',
        'DELETE /api/v1/community/signals/$_signalId',
      ],
    );
    expect(requests[1].uri.queryParameters['language'], 'ko');
    expect(requests[1].uri.queryParameters['limit'], '20');
    expect(requests[2].data, _draft);
    expect(requests[9].data, <String, Object?>{
      'source_language': 'ko',
      'body': '댓글',
    });
    expect(requests[10].data, <String, Object?>{
      'reason_code': 'misleading_place',
    });
    for (final request in requests) {
      expect(request.headers['Authorization'], 'Bearer test-token');
    }
  });
}

const String _signalId = '11111111-1111-4111-8111-111111111111';
const Map<String, Object?> _draft = <String, Object?>{
  'kind': 'place_tip',
  'source_language': 'ko',
  'title': '제목',
  'body': '본문',
  'locality_level': 'district',
  'commercial_disclosure': 'none',
  'observation_date': '2026-09-03',
  'aggregate_opt_in': false,
};

class _Adapter implements HttpClientAdapter {
  _Adapter(this.responder);

  final Future<ResponseBody> Function(RequestOptions) responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      responder(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, Object?> data) {
  final payload = utf8.encode(
    jsonEncode(<String, Object?>{
      'ok': true,
      'data': data,
      'meta': <String, Object?>{'request_id': 'test-request'},
      'error': null,
    }),
  );
  return ResponseBody(
    Stream<Uint8List>.value(Uint8List.fromList(payload)),
    200,
    headers: <String, List<String>>{
      'content-type': <String>['application/json; charset=utf-8'],
    },
  );
}
