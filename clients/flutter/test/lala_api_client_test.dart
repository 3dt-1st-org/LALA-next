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
                  'overall': 'degraded',
                  'data': 'unavailable',
                  'ai': 'disabled',
                  'speech': 'disabled',
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
      expect(readiness.data?.mode.overall, 'degraded');
      expect(readiness.data?.mode.isPublicCache, isFalse);
      expect(readiness.data?.mode.isDbBacked, isFalse);
      expect(readiness.data?.mode.isDegraded, isTrue);
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
                    'place_id': 'tour-api-126508',
                    'name': '수원화성',
                    'name_ko': '수원화성',
                    'name_en': 'Suwon Hwaseong',
                    'category': 'event',
                    'lat': 37.2,
                    'lng': 127.0,
                    'address': '경기도 수원시',
                    'distance_m': 1000,
                    'source': 'db',
                    'upstream_source': 'tour_api',
                    'event_start_date': '2026-06-01',
                    'event_end_date': '2026-08-31',
                    'event_url': 'https://example.test/events/suwon',
                    'is_ongoing': true,
                    'is_approximate_location': false,
                    'score': {
                      'final_score': 0.84,
                      'formula_version': 'local-value-v2',
                      'components': {
                        'local_spending_score': 0.9,
                        'small_merchant_fit_score': 0.72,
                        'demand_dispersion_score': 0.8,
                        'weather_fit_score': 0.7,
                        'review_quality_score': null,
                        'culture_relevance_score': 0.8,
                        'accessibility_fit_score': 0.64,
                      },
                      'data_basis': 'analytics.place_score_snapshots',
                      'features': {
                        'missing_signals': ['card_spending_snapshot'],
                      },
                    },
                  },
                ],
                'query': {
                  'lat': 37.2,
                  'lng': 127.0,
                  'radius_m': 1200,
                  'category': 'event',
                  'language': 'en',
                },
                'source': 'db',
                'location_engine': 'postgis',
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
        lang: 'en',
        includeScores: true,
        requestId: 'client-request-id',
      );

      expect(captured.method, 'GET');
      expect(captured.url.path, '/base/api/v1/places');
      expect(captured.url.queryParameters['lat'], '37.2');
      expect(captured.url.queryParameters['lng'], '127.0');
      expect(captured.url.queryParameters['radius_m'], '1200');
      expect(captured.url.queryParameters['category'], 'event');
      expect(captured.url.queryParameters['lang'], 'en');
      expect(captured.url.queryParameters['include_scores'], 'true');
      expect(captured.headers['authorization'], 'Bearer bearer-token');
      expect(captured.headers.containsKey('x-api-key'), isFalse);
      expect(captured.headers['x-request-id'], 'client-request-id');
      expect(envelope.ok, isTrue);
      expect(envelope.requestId, 'server-request-id');
      expect(envelope.data?.source, 'db');
      expect(envelope.data?.locationEngine, 'postgis');
      expect(envelope.data?.count, 1);
      expect(envelope.data?.query.radiusM, 1200);
      expect(envelope.data?.places.first.placeId, 'tour-api-126508');
      expect(envelope.data?.places.first.nameKo, '수원화성');
      expect(envelope.data?.places.first.upstreamSource, 'tour_api');
      expect(envelope.data?.places.first.eventStartDate, '2026-06-01');
      expect(envelope.data?.places.first.eventEndDate, '2026-08-31');
      expect(envelope.data?.places.first.eventUrl,
          'https://example.test/events/suwon');
      expect(envelope.data?.places.first.isOngoing, isTrue);
      expect(envelope.data?.places.first.isApproximateLocation, isFalse);
      expect(envelope.data?.places.first.score?.percent, 84);
      expect(
        envelope.data?.places.first.score?.dataBasis,
        'analytics.place_score_snapshots',
      );
      expect(
        envelope.data?.places.first.score?.components.smallMerchantFitScore,
        0.72,
      );
      expect(
        envelope.data?.places.first.score?.components.accessibilityFitScore,
        0.64,
      );
      expect(
        envelope.data?.places.first.score?.components.reviewQualityScore,
        isNull,
      );
    },
  );

  test('createDocentScript falls back to migration API key auth', () async {
    late http.Request captured;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      apiKey: '  migration-key  ',
      httpClient: MockClient((request) async {
        captured = request;
        expect(jsonDecode(request.body)['place_id'], 'tour-api-3066000');
        expect(jsonDecode(request.body)['place_name'], '중랑아트센터');
        expect(jsonDecode(request.body)['address'], 'Seoul test address');
        expect(jsonDecode(request.body)['region_ko'], '중구');
        expect(jsonDecode(request.body)['region_en'], 'Jung-gu');
        expect(jsonDecode(request.body)['distance_m'], 321);
        expect(jsonDecode(request.body)['source'], 'db');
        expect(jsonDecode(request.body)['upstream_source'], 'tour_api');
        expect(jsonDecode(request.body)['final_score'], 0.86);
        expect(jsonDecode(request.body)['local_spending_score'], 0.82);
        expect(jsonDecode(request.body)['small_merchant_fit_score'], 0.76);
        expect(jsonDecode(request.body)['demand_dispersion_score'], 0.78);
        expect(jsonDecode(request.body)['weather_fit_score'], 0.74);
        expect(jsonDecode(request.body)['culture_relevance_score'], 0.91);
        expect(jsonDecode(request.body)['weather_temp'], '21.6');
        expect(jsonDecode(request.body)['weather_outdoor_status'], 'good');
        expect(jsonDecode(request.body)['dust_grade'], 'normal');
        expect(jsonDecode(request.body)['dust_pm10'], '31');
        expect(jsonDecode(request.body)['dust_pm25'], '14');
        expect(jsonDecode(request.body)['dust_pm10_grade'], 'normal');
        expect(jsonDecode(request.body)['dust_pm25_grade'], 'good');
        return http.Response(
          jsonEncode({
            'ok': true,
            'data': {
              'place_id': 'tour-api-3066000',
              'category': 'attraction',
              'language': 'ko',
              'mode': 'brief',
              'script': 'hello',
              'source': 'rule_based_curation',
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
      placeId: 'tour-api-3066000',
      placeName: ' 중랑아트센터 ',
      address: ' Seoul test address ',
      regionKo: ' 중구 ',
      regionEn: ' Jung-gu ',
      distanceM: 321,
      source: ' db ',
      upstreamSource: ' tour_api ',
      finalScore: 0.86,
      localSpendingScore: 0.82,
      smallMerchantFitScore: 0.76,
      demandDispersionScore: 0.78,
      weatherFitScore: 0.74,
      cultureRelevanceScore: 0.91,
      weatherTemp: ' 21.6 ',
      weatherOutdoorStatus: ' good ',
      dustGrade: ' normal ',
      dustPm10: ' 31 ',
      dustPm25: ' 14 ',
      dustPm10Grade: ' normal ',
      dustPm25Grade: ' good ',
      category: 'attraction',
      language: 'ko',
      mode: 'brief',
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/v1/docents/script');
    expect(captured.headers['x-api-key'], 'migration-key');
    expect(captured.headers.containsKey('authorization'), isFalse);
    expect(captured.headers['content-type'], contains('application/json'));
    expect(envelope.data?.placeId, 'tour-api-3066000');
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
                'radius_m': 3000,
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
                    'weather_hint': 'unknown',
                  },
                ],
                'source': 'db',
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
              'reason': 'Weather is suitable for this local route.',
              'recommended_action': 'Show nearby alternatives.',
              'place': _placePayload(),
              'source': 'db',
            },
            'meta': {'request_id': 'intervention-request-id'},
            'error': null,
          });
        }),
      );

      final weather = await client.getWeather();
      final plan = await client.createDailyPlan();
      final intervention = await client.getIntervention(radiusM: 1000);

      expect(weather.data?.dust.gradeKo, '확인 중');
      expect(weather.data?.dust.pm10Grade, 'unknown');
      expect(weather.data?.dust.pm25GradeKo, '확인 중');
      expect(weather.data?.forecast, isEmpty);
      expect(plan.data?.center.lat, 37.2);
      expect(plan.data?.radiusM, 3000);
      expect(plan.data?.weather.outdoorStatus, 'unknown');
      expect(plan.data?.slots.first.place?.name, '수원화성');
      expect(plan.data?.slots.last.weatherHint, 'unknown');
      expect(plan.data?.requestHash, startsWith('abcdef'));
      expect(plan.data?.cacheKey, startsWith('daily_plan:'));
      expect(intervention.data?.shouldIntervene, isFalse);
      expect(intervention.data?.recommendedAction, 'Show nearby alternatives.');
      expect(intervention.data?.place?.placeId, 'tour-api-126508');
    },
  );

  test('createDailyPlan sends the selected radius and language', () async {
    late http.Request captured;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      apiKey: 'migration-key',
      httpClient: MockClient((request) async {
        captured = request;
        return _jsonResponse({
          'ok': true,
          'data': {
            'language': 'en',
            'center': {'lat': 37.2, 'lng': 127.0},
            'radius_m': 42000,
            'weather': _weatherPayload(),
            'slots': [],
            'source': 'db',
            'request_hash':
                'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
            'cache_key': 'daily_plan:abcdef0123456789abcdef0123456789',
          },
          'meta': {'request_id': 'plan-request-id'},
          'error': null,
        });
      }),
    );

    await client.createDailyPlan(
      lat: 37.2,
      lng: 127.0,
      radiusM: 42000,
      language: 'en',
    );

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/v1/plans/daily');
    expect(body['radius_m'], 42000);
    expect(body['language'], 'en');
  });

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

  test(
      '/api/v1 routes can be sent without client auth when caller has no token',
      () async {
    late http.Request captured;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      httpClient: MockClient((request) async {
        captured = request;
        return _jsonResponse({
          'ok': true,
          'data': {
            'count': 0,
            'places': <Object?>[],
            'query': {
              'lat': 37.2636,
              'lng': 127.0286,
              'radius_m': 1000,
              'category': 'all',
              'language': 'ko',
            },
            'source': 'db',
          },
          'meta': {'request_id': 'no-token-request-id'},
          'error': null,
        });
      }),
    );

    final envelope = await client.getPlaces();

    expect(captured.headers.containsKey('authorization'), isFalse);
    expect(captured.headers.containsKey('x-api-key'), isFalse);
    expect(envelope.ok, isTrue);
    expect(envelope.requestId, 'no-token-request-id');
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
    'place_id': 'tour-api-126508',
    'name': '수원화성',
    'name_ko': '수원화성',
    'name_en': 'Suwon Hwaseong',
    'category': 'attraction',
    'lat': 37.2,
    'lng': 127.0,
    'address': '경기도 수원시',
    'distance_m': 1000,
    'source': 'db',
  };
}

Map<String, Object?> _weatherPayload() {
  return {
    'lat': 37.2,
    'lng': 127.0,
    'temp': '',
    'icon': 'unavailable',
    'dust': {
      'pm10': '',
      'pm25': '',
      'grade': 'unknown',
      'grade_ko': '확인 중',
      'pm10_grade': 'unknown',
      'pm10_grade_ko': '확인 중',
      'pm25_grade': 'unknown',
      'pm25_grade_ko': '확인 중',
    },
    'forecast': [],
    'outdoor_status': 'unknown',
    'force': false,
    'source': 'kma_ultra_srt_ncst+airkorea_sido_realtime',
  };
}
