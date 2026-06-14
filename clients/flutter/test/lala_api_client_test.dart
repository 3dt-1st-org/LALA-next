import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:test/test.dart';

void main() {
  test('auth mode classifies OAuth JWT, static bearer, and API key', () {
    expect(
      LalaAuthMode.fromCredentials(
        bearerToken: 'eyJhbGciOiJSUzI1NiJ9.eyJscpIjoibGF sYSJ9.signature',
      ),
      LalaAuthMode.bearerToken,
    );
    expect(
      LalaAuthMode.fromCredentials(
        bearerToken: 'eyJhbGciOiJSUzI1NiJ9.eyJzY3AiOiJsYWxhIn0.signature',
      ),
      LalaAuthMode.oauthJwt,
    );
    expect(
      LalaAuthMode.fromCredentials(bearerToken: 'static-token'),
      LalaAuthMode.bearerToken,
    );
    expect(
      LalaAuthMode.fromCredentials(apiKey: 'migration-key'),
      LalaAuthMode.apiKey,
    );
    expect(LalaAuthMode.fromCredentials(), LalaAuthMode.none);

    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      bearerToken: 'eyJhbGciOiJSUzI1NiJ9.eyJzY3AiOiJsYWxhIn0.signature',
      apiKey: 'migration-key',
      httpClient: MockClient((request) async => _jsonResponse({})),
    );
    expect(client.authMode, LalaAuthMode.oauthJwt);
    expect(client.authMode.label, 'oauth jwt');
  });

  test(
    'public health and readiness checks do not require client auth',
    () async {
      final paths = <String>[];
      final client = LalaApiClient(
        baseUri: Uri.parse('http://api.example.test/base'),
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          expect(request.headers.containsKey('authorization'), isFalse);
          expect(request.headers.containsKey('x-api-key'), isFalse);
          if (request.url.path.endsWith('/healthz')) {
            return http.Response(
              jsonEncode({
                'ok': true,
                'data': {
                  'status': 'ok',
                  'service': 'lala-next-api',
                  'version': '0.1.0',
                },
                'meta': {'request_id': 'health-request-id'},
                'error': null,
              }),
              200,
              headers: {'x-request-id': 'health-request-id'},
            );
          }
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'status': 'degraded',
                'checks': {
                  'client_auth': 'missing',
                  'db': 'skipped',
                  'worker_contracts': 'configured',
                },
                'mode': {
                  'overall': 'skeleton',
                  'data': 'skeleton',
                  'ai': 'skeleton',
                  'speech': 'skeleton',
                  'worker': 'dry-run',
                },
              },
              'meta': {'request_id': 'ready-request-id'},
              'error': null,
            }),
            200,
            headers: {'x-request-id': 'ready-request-id'},
          );
        }),
      );

      final health = await client.getHealth();
      final readiness = await client.getReadiness();

      expect(paths, ['/base/healthz', '/base/readyz']);
      expect(health.data?['status'], 'ok');
      expect(readiness.data?.status, 'degraded');
      expect(readiness.data?.checks['worker_contracts'], 'configured');
      expect(readiness.data?.mode.overall, 'skeleton');
      expect(readiness.data?.mode.isSkeleton, isTrue);
      expect(readiness.data?.mode.isDbBacked, isFalse);
      expect(readiness.requestId, 'ready-request-id');
    },
  );

  test(
    'getPlaces sends bearer auth, request id, and query parameters',
    () async {
      late http.Request captured;
      final client = LalaApiClient(
        baseUri: Uri.parse('http://api.example.test/base'),
        bearerToken: '  bearer-token  ',
        apiKey: 'migration-key',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'count': 1,
                'places': [
                  {
                    'place_id': 'skeleton-suwon-hwaseong',
                    'name': '수원화성',
                    'name_ko': '수원화성',
                    'name_en': 'Suwon Hwaseong',
                    'category': 'event',
                    'lat': 37.2,
                    'lng': 127.0,
                    'address': '경기도 수원시',
                    'distance_m': 1000,
                    'source': 'skeleton',
                  },
                ],
                'query': {
                  'lat': 37.2,
                  'lng': 127.0,
                  'radius_m': 1200,
                  'category': 'event',
                  'language': 'ko',
                },
                'source': 'skeleton',
              },
              'meta': {'request_id': 'server-request-id'},
              'error': null,
            }),
            200,
            headers: {
              'content-type': 'application/json',
              'x-request-id': 'server-request-id',
            },
          );
        }),
      );

      final envelope = await client.getPlaces(
        lat: 37.2,
        lng: 127.0,
        radiusM: 1200,
        category: 'event',
        lang: 'ko',
        requestId: 'client-request-id',
      );

      expect(captured.method, 'GET');
      expect(captured.url.path, '/base/api/v1/places');
      expect(captured.url.queryParameters['lat'], '37.2');
      expect(captured.url.queryParameters['lng'], '127.0');
      expect(captured.url.queryParameters['radius_m'], '1200');
      expect(captured.url.queryParameters['category'], 'event');
      expect(captured.headers['authorization'], 'Bearer bearer-token');
      expect(captured.headers.containsKey('x-api-key'), isFalse);
      expect(captured.headers['x-request-id'], 'client-request-id');
      expect(envelope.ok, isTrue);
      expect(envelope.requestId, 'server-request-id');
      expect(envelope.data?.source, 'skeleton');
      expect(envelope.data?.count, 1);
      expect(envelope.data?.query.radiusM, 1200);
      expect(envelope.data?.places.first.placeId, 'skeleton-suwon-hwaseong');
      expect(envelope.data?.places.first.nameKo, '수원화성');
    },
  );

  test('createDocentScript falls back to migration API key auth', () async {
    late http.Request captured;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      apiKey: '  migration-key  ',
      httpClient: MockClient((request) async {
        captured = request;
        expect(jsonDecode(request.body)['place_id'], 'demo-place');
        return http.Response(
          jsonEncode({
            'ok': true,
            'data': {
              'place_id': 'demo-place',
              'category': 'attraction',
              'language': 'ko',
              'mode': 'brief',
              'script': 'hello',
              'source': 'skeleton',
              'generated_at': '2026-06-11T00:00:00+00:00',
              'ttl_sec': 604800,
              'request_hash':
                  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
              'cache_key': 'docent_script:0123456789abcdef0123456789abcdef',
            },
            'meta': {'request_id': 'script-request-id'},
            'error': null,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final envelope = await client.createDocentScript(
      placeId: 'demo-place',
      category: 'attraction',
      language: 'ko',
      mode: 'brief',
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/v1/docents/script');
    expect(captured.headers['x-api-key'], 'migration-key');
    expect(captured.headers.containsKey('authorization'), isFalse);
    expect(captured.headers['content-type'], contains('application/json'));
    expect(envelope.data?.placeId, 'demo-place');
    expect(envelope.data?.script, 'hello');
    expect(envelope.data?.ttlSec, 604800);
    expect(envelope.data?.requestHash, startsWith('012345'));
    expect(envelope.data?.cacheKey, startsWith('docent_script:'));
  });

  test(
    'typed API response models parse weather, plans, and intervention',
    () async {
      final client = LalaApiClient(
        baseUri: Uri.parse('http://api.example.test'),
        bearerToken: 'typed-token',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/v1/weather') {
            return _jsonResponse({
              'ok': true,
              'data': _weatherPayload(),
              'meta': {'request_id': 'weather-request-id'},
              'error': null,
            });
          }
          if (request.url.path == '/api/v1/plans/daily') {
            return _jsonResponse({
              'ok': true,
              'data': {
                'language': 'ko',
                'center': {'lat': 37.2, 'lng': 127.0},
                'weather': _weatherPayload(),
                'slots': [
                  {
                    'period': 'morning',
                    'title': 'Start near a landmark',
                    'place': _placePayload(),
                  },
                  {
                    'period': 'afternoon',
                    'title': 'Adjust by weather',
                    'weather_hint': 'good',
                  },
                ],
                'source': 'skeleton',
                'request_hash':
                    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
                'cache_key': 'daily_plan:abcdef0123456789abcdef0123456789',
              },
              'meta': {'request_id': 'plan-request-id'},
              'error': null,
            });
          }
          return _jsonResponse({
            'ok': true,
            'data': {
              'center': {'lat': 37.2, 'lng': 127.0},
              'radius_m': 1000,
              'should_intervene': false,
              'reason': 'Weather-aware placeholder.',
              'recommended_action': 'Show nearby alternatives.',
              'source': 'skeleton',
            },
            'meta': {'request_id': 'intervention-request-id'},
            'error': null,
          });
        }),
      );

      final weather = await client.getWeather();
      final plan = await client.createDailyPlan();
      final intervention = await client.getIntervention(radiusM: 1000);

      expect(weather.data?.dust.gradeKo, '보통');
      expect(weather.data?.forecast.first.icon, 'partly-cloudy');
      expect(plan.data?.center.lat, 37.2);
      expect(plan.data?.weather.outdoorStatus, 'good');
      expect(plan.data?.slots.first.place?.name, '수원화성');
      expect(plan.data?.slots.last.weatherHint, 'good');
      expect(plan.data?.requestHash, startsWith('abcdef'));
      expect(plan.data?.cacheKey, startsWith('daily_plan:'));
      expect(intervention.data?.shouldIntervene, isFalse);
      expect(intervention.data?.recommendedAction, 'Show nearby alternatives.');
    },
  );

  test('createDocentAudio returns mpeg bytes and request id', () async {
    late http.Request captured;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      bearerToken: 'audio-token',
      httpClient: MockClient((request) async {
        captured = request;
        expect(jsonDecode(request.body)['script'], 'audio script');
        return http.Response.bytes(
          [0x49, 0x44, 0x33],
          200,
          headers: {
            'content-type': 'audio/mpeg',
            'x-request-id': 'audio-request-id',
            'x-lala-request-hash':
                'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210',
            'x-lala-cache-key': 'docent_audio:fedcba9876543210fedcba9876543210',
          },
        );
      }),
    );

    final audio = await client.createDocentAudio(script: 'audio script');

    expect(captured.headers['accept'], contains('audio/mpeg'));
    expect(captured.headers['authorization'], 'Bearer audio-token');
    expect(audio.bytes, [0x49, 0x44, 0x33]);
    expect(audio.requestId, 'audio-request-id');
    expect(audio.contentType, 'audio/mpeg');
    expect(audio.requestHash, startsWith('fedcba'));
    expect(audio.cacheKey, startsWith('docent_audio:'));
  });

  test(
    'JSON error envelope becomes LalaApiException without body leakage',
    () async {
      final client = LalaApiClient(
        baseUri: Uri.parse('http://api.example.test'),
        bearerToken: 'bad-token',
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'ok': false,
              'data': null,
              'meta': {'request_id': 'error-request-id'},
              'error': {
                'code': 'UNAUTHORIZED',
                'message': 'Invalid client credentials.',
                'retryable': false,
              },
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        client.getWeather(),
        throwsA(
          isA<LalaApiException>()
              .having((error) => error.code, 'code', 'UNAUTHORIZED')
              .having((error) => error.statusCode, 'statusCode', 401)
              .having((error) => error.retryable, 'retryable', isFalse)
              .having(
                (error) => error.requestId,
                'requestId',
                'error-request-id',
              ),
        ),
      );
    },
  );

  test('network timeout becomes retryable LalaApiException', () async {
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      bearerToken: 'slow-token',
      httpClient: MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return _jsonResponse({
          'ok': true,
          'data': _weatherPayload(),
          'meta': {'request_id': 'late-server-request-id'},
          'error': null,
        });
      }),
    );

    await expectLater(
      client.getWeather(
        requestId: 'client-timeout-id',
        timeout: const Duration(milliseconds: 1),
      ),
      throwsA(
        isA<LalaApiException>()
            .having((error) => error.code, 'code', 'REQUEST_TIMEOUT')
            .having((error) => error.statusCode, 'statusCode', 0)
            .having((error) => error.retryable, 'retryable', isTrue)
            .having(
              (error) => error.requestId,
              'requestId',
              'client-timeout-id',
            ),
      ),
    );
  });

  test('/api/v1 routes require one client auth strategy', () async {
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      httpClient: MockClient((request) async {
        fail('authenticated route should fail before sending a request');
      }),
    );

    await expectLater(client.getPlaces(), throwsArgumentError);
  });
}

http.Response _jsonResponse(Map<String, Object?> payload) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(payload)),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Map<String, Object?> _placePayload() {
  return {
    'place_id': 'skeleton-suwon-hwaseong',
    'name': '수원화성',
    'name_ko': '수원화성',
    'name_en': 'Suwon Hwaseong',
    'category': 'attraction',
    'lat': 37.2,
    'lng': 127.0,
    'address': '경기도 수원시',
    'distance_m': 1000,
    'source': 'skeleton',
  };
}

Map<String, Object?> _weatherPayload() {
  return {
    'lat': 37.2,
    'lng': 127.0,
    'temp': '11',
    'icon': 'partly-cloudy',
    'dust': {'pm10': '37', 'pm25': '26', 'grade': 'normal', 'grade_ko': '보통'},
    'forecast': [
      {
        'time': '2026-06-11T12:00:00+09:00',
        'temp': '12',
        'icon': 'partly-cloudy',
      },
    ],
    'outdoor_status': 'good',
    'force': false,
    'source': 'skeleton',
  };
}
