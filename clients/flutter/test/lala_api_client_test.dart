import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:test/test.dart';

typedef _Responder = Future<ResponseBody> Function(RequestOptions);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.responder, this.sink);

  final _Responder responder;
  final void Function(RequestOptions) sink;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sink(options);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(
  _Responder responder, {
  void Function(RequestOptions)? sink,
}) {
  final dio = Dio();
  dio.httpClientAdapter = _Adapter(responder, sink ?? (_) {});
  return dio;
}

ResponseBody _body(
  List<int> data,
  int status, {
  Map<String, List<String>>? headers,
}) {
  final bytes = data is Uint8List ? data : Uint8List.fromList(data);
  final stream = Stream<Uint8List>.value(bytes);
  return ResponseBody(stream, status, headers: headers ?? const {});
}

ResponseBody _json(
  Map<String, Object?> payload, {
  int status = 200,
  Map<String, List<String>>? headers,
}) {
  final h = <String, List<String>>{
    'content-type': ['application/json; charset=utf-8'],
  };
  if (headers != null) {
    h.addAll(headers);
  }
  return _body(utf8.encode(jsonEncode(payload)), status, headers: h);
}

ResponseBody _empty({int status = 204}) => _body(const <int>[], status);

ResponseBody _audio(
  List<int> bytes, {
  required Map<String, List<String>> headers,
  int status = 200,
}) =>
    _body(bytes, status, headers: headers);

String? _h(RequestOptions options, String name) {
  final keys = options.headers.keys.cast<String>();
  for (final key in keys) {
    if (key.toLowerCase() == name.toLowerCase()) {
      return options.headers[key]?.toString();
    }
  }
  return null;
}

void main() {
  test('uses a fresh provider token for each sequential private request',
      () async {
    final tokens = <String>['first-token', 'second-token'];
    final capturedAuthorization = <String?>[];
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      accessTokenProvider: () async => tokens.removeAt(0),
      dio: _dio(
        (request) async {
          capturedAuthorization.add(_h(request, 'authorization'));
          return _placesResponse();
        },
      ),
    );

    await client.getPlaces(lat: 37.2, lng: 127.0);
    await client.getPlaces(lat: 37.2, lng: 127.0);

    expect(
        capturedAuthorization, ['Bearer first-token', 'Bearer second-token']);
  });

  test('provider token takes precedence over static bearer and API key',
      () async {
    late RequestOptions captured;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      bearerToken: 'static-bearer',
      apiKey: 'static-api-key',
      accessTokenProvider: () async => 'dynamic-token',
      dio: _dio(
        (request) async {
          captured = request;
          return _placesResponse();
        },
      ),
    );

    await client.getPlaces(lat: 37.2, lng: 127.0);

    expect(_h(captured, 'authorization'), 'Bearer dynamic-token');
    expect(_h(captured, 'x-api-key'), isNull);
    expect(client.authMode, LalaAuthMode.bearerToken);
    expect(client.hasDynamicAuth, isTrue);
  });

  test(
      'public health and readiness never invoke the provider or send credentials',
      () async {
    var providerCalls = 0;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      bearerToken: 'static-bearer',
      apiKey: 'static-api-key',
      accessTokenProvider: () async {
        providerCalls++;
        throw StateError('provider must not be called');
      },
      dio: _dio((request) async {
        expect(_h(request, 'authorization'), isNull);
        expect(_h(request, 'x-api-key'), isNull);
        if (request.uri.path.endsWith('/healthz')) {
          return _json({
            'ok': true,
            'data': <String, Object?>{},
            'meta': <String, Object?>{},
            'error': null,
          });
        }
        return _json({
          'ok': true,
          'data': {
            'status': 'ok',
            'checks': <String, String>{},
            'mode': <String, String>{},
          },
          'meta': <String, Object?>{},
          'error': null,
        });
      }),
    );

    await client.getHealth();
    await client.getReadiness();

    expect(providerCalls, 0);
  });

  test('blank provider token falls back to static bearer, API key, or no auth',
      () async {
    final capturedHeaders = <Map<String, String?>>[];
    final clients = [
      LalaApiClient(
        baseUri: Uri.parse('http://api.example.test'),
        bearerToken: 'static-bearer',
        apiKey: 'static-api-key',
        accessTokenProvider: () async => '  ',
        dio: _dio(
          (request) async {
            capturedHeaders.add(_allHeaders(request));
            return _placesResponse();
          },
        ),
      ),
      LalaApiClient(
        baseUri: Uri.parse('http://api.example.test'),
        apiKey: 'static-api-key',
        accessTokenProvider: () async => null,
        dio: _dio(
          (request) async {
            capturedHeaders.add(_allHeaders(request));
            return _placesResponse();
          },
        ),
      ),
      LalaApiClient(
        baseUri: Uri.parse('http://api.example.test'),
        accessTokenProvider: () async => null,
        dio: _dio(
          (request) async {
            capturedHeaders.add(_allHeaders(request));
            return _placesResponse();
          },
        ),
      ),
    ];

    for (final client in clients) {
      await client.getPlaces(lat: 37.2, lng: 127.0);
    }

    expect(capturedHeaders[0]['authorization'], 'Bearer static-bearer');
    expect(capturedHeaders[0].containsKey('x-api-key'), isFalse);
    expect(capturedHeaders[1]['x-api-key'], 'static-api-key');
    expect(capturedHeaders[1].containsKey('authorization'), isFalse);
    expect(capturedHeaders[2].containsKey('authorization'), isFalse);
    expect(capturedHeaders[2].containsKey('x-api-key'), isFalse);
  });

  test('provider errors become redacted retryable auth exceptions', () async {
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      accessTokenProvider: () async {
        throw StateError('secret-provider-token');
      },
      dio: _dio((request) async => _placesResponse()),
    );

    await expectLater(
      client.getPlaces(lat: 37.2, lng: 127.0),
      throwsA(
        isA<LalaApiException>()
            .having((error) => error.code, 'code', 'AUTH_TOKEN_UNAVAILABLE')
            .having((error) => error.statusCode, 'statusCode', 0)
            .having((error) => error.retryable, 'retryable', isTrue)
            .having(
                (error) => error.message, 'message', isNot(contains('secret')))
            .having((error) => error.toString(), 'toString',
                isNot(contains('secret'))),
      ),
    );
  });

  test('getMe parses the strict account response', () async {
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      dio: _dio((request) async {
        expect(request.method, 'GET');
        expect(request.uri.path, '/api/v1/me');
        return _json({
          'ok': true,
          'data': {
            'user_id': 'user-123',
            'created_at': '2026-07-10T00:00:00Z',
            'authenticated': true,
          },
          'meta': {'request_id': 'me-request-id'},
          'error': null,
        });
      }),
    );

    final envelope = await client.getMe();

    expect(envelope.data?.userId, 'user-123');
    expect(envelope.data?.createdAt, '2026-07-10T00:00:00Z');
    expect(envelope.data?.authenticated, isTrue);
    expect(envelope.requestId, 'me-request-id');
  });

  test('LalaMe rejects non-strict JSON field types', () {
    expect(
      () => LalaMe.fromJsonObject({
        'user_id': 123,
        'created_at': '2026-07-10T00:00:00Z',
        'authenticated': true,
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('getTravelPreferences preserves honest null for an empty profile',
      () async {
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      dio: _dio((request) async {
        expect(request.method, 'GET');
        expect(request.uri.path, '/api/v1/me/preferences');
        return _json({
          'ok': true,
          'data': null,
          'meta': {'source': 'unavailable'},
          'error': null,
        });
      }),
    );

    final envelope = await client.getTravelPreferences();

    expect(envelope.ok, isTrue);
    expect(envelope.data, isNull);
    expect(envelope.meta['source'], 'unavailable');
  });

  test('getTravelPreferences parses a revisioned server document', () async {
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      dio: _dio((request) async => _json({
            'ok': true,
            'data': {
              'preferences': {
                'version': 1,
                'soft': {'pace': 'relaxed'},
                'hard': <String, Object?>{},
                'locale': <String, Object?>{},
              },
              'revision': 3,
              'updated_at': '2026-09-02T00:00:00Z',
            },
            'meta': {'source': 'db'},
            'error': null,
          })),
    );

    final document = (await client.getTravelPreferences()).data;

    expect(document?.revision, 3);
    expect(document?.preferences['version'], 1);
    expect(document?.updatedAt, '2026-09-02T00:00:00Z');
  });

  test('putTravelPreferences sends the optimistic revision and dynamic auth',
      () async {
    late RequestOptions captured;
    final preferences = <String, dynamic>{
      'version': 1,
      'soft': <String, Object?>{},
      'hard': <String, Object?>{},
      'locale': <String, Object?>{},
    };
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      accessTokenProvider: () async => 'preferences-token',
      dio: _dio((request) async {
        captured = request;
        return _json({
          'ok': true,
          'data': {
            'preferences': preferences,
            'revision': 5,
            'updated_at': '2026-09-02T00:00:00Z',
          },
          'meta': {'source': 'db'},
          'error': null,
        });
      }),
    );

    final envelope = await client.putTravelPreferences(
      expectedRevision: 4,
      preferences: preferences,
    );

    expect(captured.method, 'PUT');
    expect(captured.uri.path, '/api/v1/me/preferences');
    expect(captured.data, {
      'expected_revision': 4,
      'preferences': preferences,
    });
    expect(_h(captured, 'authorization'), 'Bearer preferences-token');
    expect(envelope.data?.revision, 5);
  });

  test('deleteMe sends JSON confirmation and dynamic auth, accepting only 204',
      () async {
    late RequestOptions captured;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      accessTokenProvider: () async => 'delete-token',
      dio: _dio(
        (request) async {
          captured = request;
          return _empty(status: 204);
        },
      ),
    );

    await client.deleteMe(confirmation: 'delete-my-account');

    expect(captured.method, 'DELETE');
    expect(captured.uri.path, '/api/v1/me');
    expect(captured.data, {'confirmation': 'delete-my-account'});
    expect(_h(captured, 'authorization'), 'Bearer delete-token');
    expect(_h(captured, 'content-type'), contains('application/json'));
  });

  test('deleteMe rejects an unexpected successful status as INVALID_RESPONSE',
      () async {
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      dio: _dio((request) async => _json({
            'ok': true,
            'data': null,
            'meta': <String, Object?>{},
            'error': null,
          })),
    );

    await expectLater(
      client.deleteMe(confirmation: 'delete-my-account'),
      throwsA(
        isA<LalaApiException>()
            .having((error) => error.code, 'code', 'INVALID_RESPONSE')
            .having((error) => error.statusCode, 'statusCode', 200),
      ),
    );
  });

  test('deleteMe preserves a JSON error envelope as a typed exception',
      () async {
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      dio: _dio((request) async {
        return _json(
          {
            'ok': false,
            'data': null,
            'meta': {'request_id': 'delete-error-id'},
            'error': {
              'code': 'CONFIRMATION_REQUIRED',
              'message': 'Confirmation is required.',
              'retryable': false,
            },
          },
          status: 400,
          headers: {
            'content-type': ['application/json'],
          },
        );
      }),
    );

    await expectLater(
      client.deleteMe(confirmation: 'wrong-confirmation'),
      throwsA(
        isA<LalaApiException>()
            .having((error) => error.code, 'code', 'CONFIRMATION_REQUIRED')
            .having((error) => error.statusCode, 'statusCode', 400)
            .having((error) => error.requestId, 'requestId', 'delete-error-id'),
      ),
    );
  });

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
      dio: _dio((request) async => _json({})),
    );
    expect(client.authMode, LalaAuthMode.oauthJwt);
    expect(client.authMode.label, 'oauth jwt');
  });

  test('public health and readiness checks do not require client auth',
      () async {
    final paths = <String>[];
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test/base'),
      dio: _dio((request) async {
        paths.add(request.uri.path);
        expect(_h(request, 'authorization'), isNull);
        expect(_h(request, 'x-api-key'), isNull);
        if (request.uri.path.endsWith('/healthz')) {
          return _json(
            {
              'ok': true,
              'data': {
                'status': 'ok',
                'service': 'lala-next-api',
                'version': '0.1.0',
              },
              'meta': {'request_id': 'health-request-id'},
              'error': null,
            },
            headers: {
              'x-request-id': ['health-request-id'],
            },
          );
        }
        return _json(
          {
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
          },
          headers: {
            'x-request-id': ['ready-request-id'],
          },
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
  });

  test('getPlaces sends bearer auth, request id, and query parameters',
      () async {
    late RequestOptions captured;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test/base'),
      bearerToken: '  bearer-token  ',
      apiKey: 'migration-key',
      dio: _dio((request) async {
        captured = request;
        return _json(
          {
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
                'limit': 80,
                'category': 'event',
                'language': 'en',
              },
              'source': 'db',
              'location_engine': 'postgis',
              'data_as_of': '2026-06-19T02:24:44.557686+00:00',
            },
            'meta': {'request_id': 'server-request-id'},
            'error': null,
          },
          headers: {
            'x-request-id': ['server-request-id'],
          },
        );
      }),
    );

    final envelope = await client.getPlaces(
      lat: 37.2,
      lng: 127.0,
      radiusM: 1200,
      limit: 80,
      category: 'event',
      lang: 'en',
      includeScores: true,
      requestId: 'client-request-id',
    );

    expect(captured.method, 'GET');
    expect(captured.uri.path, '/base/api/v1/places');
    expect(captured.uri.queryParameters['lat'], '37.2');
    expect(captured.uri.queryParameters['lng'], '127.0');
    expect(captured.uri.queryParameters['radius_m'], '1200');
    expect(captured.uri.queryParameters['limit'], '80');
    expect(captured.uri.queryParameters['category'], 'event');
    expect(captured.uri.queryParameters['lang'], 'en');
    expect(captured.uri.queryParameters['include_scores'], 'true');
    expect(_h(captured, 'authorization'), 'Bearer bearer-token');
    expect(_h(captured, 'x-api-key'), isNull);
    expect(_h(captured, 'x-request-id'), 'client-request-id');
    expect(envelope.ok, isTrue);
    expect(envelope.requestId, 'server-request-id');
    expect(envelope.data?.source, 'db');
    expect(envelope.data?.locationEngine, 'postgis');
    expect(envelope.data?.dataAsOf, '2026-06-19T02:24:44.557686+00:00');
    expect(envelope.data?.count, 1);
    expect(envelope.data?.query.radiusM, 1200);
    expect(envelope.data?.query.limit, 80);
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
  });

  test('getLocalSignals keeps the public query contract and opaque cursor',
      () async {
    late RequestOptions captured;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test/base'),
      accessTokenProvider: () async => 'guest-read-token',
      dio: _dio((request) async {
        captured = request;
        return _json({
          'ok': true,
          'data': {
            'items': [
              {
                'id': 'signal-1',
                'kind': 'place_tip',
                'source_language': 'ko',
                'title': '공개 신호',
                'body': '날짜가 있는 first-party body',
                'locality_level': 'district',
                'locality_code': 'busan-haeundae',
                'commercial_disclosure': 'none',
                'place_links': [
                  {'place_id': 'place-1', 'relation': 'nearby'},
                ],
              },
            ],
            'next_cursor': 'opaque-next-cursor',
            'has_more': true,
            'context': {'language': 'ko'},
          },
          'meta': <String, Object?>{},
          'error': null,
        });
      }),
    );

    final response = await client.getLocalSignals(
      language: 'ko',
      region: 'busan-haeundae',
      placeId: 'place-1',
      kind: 'place_tip',
      sort: 'recent',
      limit: 20,
      cursor: 'opaque-cursor',
    );

    expect(captured.method, 'GET');
    expect(captured.uri.path, '/base/api/v1/community/signals');
    expect(captured.uri.queryParameters, {
      'language': 'ko',
      'region': 'busan-haeundae',
      'place_id': 'place-1',
      'kind': 'place_tip',
      'sort': 'recent',
      'limit': '20',
      'cursor': 'opaque-cursor',
    });
    expect(_h(captured, 'authorization'), 'Bearer guest-read-token');
    expect(response.data?['items'], isA<List<Object?>>());
    expect(response.data?['next_cursor'], 'opaque-next-cursor');
  });

  test('createDocentScript falls back to migration API key auth', () async {
    late RequestOptions captured;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      apiKey: '  migration-key  ',
      dio: _dio((request) async {
        captured = request;
        expect((request.data as Map)['place_id'], 'tour-api-3066000');
        expect((request.data as Map)['place_name'], '중랑아트센터');
        expect((request.data as Map)['address'], 'Seoul test address');
        expect((request.data as Map)['region_ko'], '중구');
        expect((request.data as Map)['region_en'], 'Jung-gu');
        expect((request.data as Map)['distance_m'], 321);
        expect((request.data as Map)['source'], 'db');
        expect((request.data as Map)['upstream_source'], 'tour_api');
        expect((request.data as Map)['final_score'], 0.86);
        expect((request.data as Map)['local_spending_score'], 0.82);
        expect((request.data as Map)['small_merchant_fit_score'], 0.76);
        expect((request.data as Map)['demand_dispersion_score'], 0.78);
        expect((request.data as Map)['weather_fit_score'], 0.74);
        expect((request.data as Map)['culture_relevance_score'], 0.91);
        expect((request.data as Map)['weather_temp'], '21.6');
        expect((request.data as Map)['weather_icon'], 'partly-cloudy');
        expect((request.data as Map)['weather_outdoor_status'], 'good');
        expect((request.data as Map)['dust_grade'], 'normal');
        expect((request.data as Map)['dust_pm10'], '31');
        expect((request.data as Map)['dust_pm25'], '14');
        expect((request.data as Map)['dust_pm10_grade'], 'normal');
        expect((request.data as Map)['dust_pm25_grade'], 'good');
        return _json({
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
        });
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
      weatherIcon: ' partly-cloudy ',
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
    expect(captured.uri.path, '/api/v1/docents/script');
    expect(_h(captured, 'x-api-key'), 'migration-key');
    expect(_h(captured, 'authorization'), isNull);
    expect(_h(captured, 'content-type'), contains('application/json'));
    expect(envelope.data?.placeId, 'tour-api-3066000');
    expect(envelope.data?.script, 'hello');
    expect(envelope.data?.ttlSec, 604800);
    expect(envelope.data?.requestHash, startsWith('012345'));
    expect(envelope.data?.cacheKey, startsWith('docent_script:'));
    // Additive grounding parse (issue #120 §5): absent server fields stay absent.
    expect(envelope.data?.groundingCount, isNull);
    expect(envelope.data?.groundingSources, isEmpty);
  });

  test('docent script parses grounding_count and grounding_sources additively',
      () async {
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      dio: _dio((request) async {
        return _json({
          'ok': true,
          'data': {
            'place_id': 'grounded-place',
            'category': 'culture_venue',
            'language': 'ko',
            'mode': 'brief',
            'script': '근거 있는 도슨트 스크립트',
            'source': 'openai',
            'generated_at': '2026-09-01T00:00:00+00:00',
            'grounding_count': 3,
            'grounding_sources': [
              'place_profile',
              'culture_event',
              'community_post',
            ],
            'request_hash':
                '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
            'cache_key': 'docent_script:grounded',
          },
          'meta': {'request_id': 'grounded-request-id'},
          'error': null,
        });
      }),
    );

    final envelope = await client.createDocentScript(
      placeId: 'grounded-place',
      placeName: '근거 장소',
      address: '주소',
      source: 'db',
      category: 'culture_venue',
      language: 'ko',
    );

    expect(envelope.data?.groundingCount, 3);
    expect(envelope.data?.groundingSources, <String>[
      'place_profile',
      'culture_event',
      'community_post',
    ]);
  });

  test('typed API response models parse weather, plans, and intervention',
      () async {
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      bearerToken: 'typed-token',
      dio: _dio((request) async {
        if (request.uri.path == '/api/v1/weather') {
          return _json({
            'ok': true,
            'data': _weatherPayload(),
            'meta': {'request_id': 'weather-request-id'},
            'error': null,
          });
        }
        if (request.uri.path == '/api/v1/plans/daily') {
          return _json({
            'ok': true,
            'data': {
              'language': 'ko',
              'center': {'lat': 37.2, 'lng': 127.0},
              'radius_m': 3000,
              'weather': _weatherPayload(),
              'slots': [
                {
                  'period': 'morning',
                  'title': 'Morning',
                  'place': _placePayload(),
                  'weather_hint': 'unknown',
                  'recommendation_reason': 'Recommended as a local attraction',
                  'unavailable_reason': null,
                },
                {
                  'period': 'lunch',
                  'title': 'Lunch',
                  'weather_hint': 'unknown',
                  'unavailable_reason': 'Not enough nearby options',
                },
                {
                  'period': 'afternoon',
                  'title': 'Afternoon',
                  'weather_hint': 'unknown',
                  'unavailable_reason': 'Not enough nearby options',
                },
                {
                  'period': 'dinner',
                  'title': 'Dinner',
                  'weather_hint': 'unknown',
                  'unavailable_reason': 'Not enough nearby options',
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
        return _json({
          'ok': true,
          'data': {
            'center': {'lat': 37.2, 'lng': 127.0},
            'radius_m': 1000,
            'should_intervene': false,
            'reason': 'Weather is suitable for this local route.',
            'recommended_action': 'Show nearby alternatives.',
            'place': _placePayload(),
            'source': 'db',
            'original_slot': {
              'period': 'afternoon',
              'title': 'Afternoon',
              'place': _placePayload(),
              'weather_hint': 'good',
            },
            'alternative_slot': null,
            'trigger_type': null,
            'trigger_factors': <Map<String, dynamic>>[],
            'distance_comparison': null,
            'user_decision': 'pending',
            'apply_state': 'not_applied',
            'history': <Map<String, dynamic>>[],
          },
          'meta': {'request_id': 'intervention-request-id'},
          'error': null,
        });
      }),
    );

    final weather = await client.getWeather(lat: 37.2, lng: 127.0);
    final plan = await client.createDailyPlan(lat: 37.2, lng: 127.0);
    final intervention = await client.getIntervention(
      lat: 37.2,
      lng: 127.0,
      radiusM: 1000,
    );

    expect(weather.data?.dust.gradeKo, '확인 중');
    expect(weather.data?.dust.pm10Grade, 'unknown');
    expect(weather.data?.dust.pm25GradeKo, '확인 중');
    expect(weather.data?.forecast, isEmpty);
    expect(plan.data?.center.lat, 37.2);
    expect(plan.data?.radiusM, 3000);
    expect(plan.data?.weather.outdoorStatus, 'unknown');
    expect(plan.data?.slots.first.place?.name, '수원화성');
    expect(plan.data?.slots.last.weatherHint, 'unknown');
    // P5A: 4-period contract + new honest-unavailable authority fields.
    expect(plan.data?.slots.map((s) => s.period).toList(), [
      'morning',
      'lunch',
      'afternoon',
      'dinner',
    ]);
    expect(plan.data?.slots.length, 4);
    expect(
      plan.data?.slots.first.recommendationReason,
      'Recommended as a local attraction',
    );
    expect(plan.data?.slots.first.unavailableReason, isNull);
    expect(plan.data?.slots.first.startTime, isNull);
    expect(plan.data?.slots.first.openingHoursValid, isNull);
    expect(plan.data?.slots.first.swappableAlternatives, isEmpty);
    expect(plan.data?.slots.last.place, isNull);
    expect(
      plan.data?.slots.last.unavailableReason,
      'Not enough nearby options',
    );
    expect(plan.data?.requestHash, startsWith('abcdef'));
    expect(plan.data?.cacheKey, startsWith('daily_plan:'));
    expect(intervention.data?.shouldIntervene, isFalse);
    expect(intervention.data?.recommendedAction, 'Show nearby alternatives.');
    expect(intervention.data?.place?.placeId, 'tour-api-126508');
    // P5B: original/alternative + trigger + decision boundary parsing.
    expect(intervention.data?.originalSlot?.period, 'afternoon');
    expect(intervention.data?.originalSlot?.place?.placeId, 'tour-api-126508');
    expect(intervention.data?.alternativeSlot, isNull);
    expect(intervention.data?.triggerType, isNull);
    expect(intervention.data?.triggerFactors, isEmpty);
    expect(intervention.data?.distanceComparison, isNull);
    expect(intervention.data?.userDecision, 'pending');
    expect(intervention.data?.applyState, 'not_applied');
    expect(intervention.data?.history, isEmpty);
  });

  test('createDailyPlan sends the selected radius and language', () async {
    late RequestOptions captured;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      apiKey: 'migration-key',
      dio: _dio((request) async {
        captured = request;
        return _json({
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

    final body = captured.data as Map;
    expect(captured.method, 'POST');
    expect(captured.uri.path, '/api/v1/plans/daily');
    expect(body['radius_m'], 42000);
    expect(body['language'], 'en');
  });

  test('createDocentAudio returns mpeg bytes and request id', () async {
    late RequestOptions captured;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      bearerToken: 'audio-token',
      dio: _dio((request) async {
        captured = request;
        expect((request.data as Map)['script'], 'audio script');
        return _audio(
          [0x49, 0x44, 0x33],
          headers: {
            'content-type': ['audio/mpeg'],
            'x-request-id': ['audio-request-id'],
            'x-lala-request-hash': [
              'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210',
            ],
            'x-lala-cache-key': [
              'docent_audio:fedcba9876543210fedcba9876543210',
            ],
          },
        );
      }),
    );

    final audio = await client.createDocentAudio(script: 'audio script');

    expect(_h(captured, 'accept'), contains('audio/mpeg'));
    expect(_h(captured, 'authorization'), 'Bearer audio-token');
    expect(audio.bytes, [0x49, 0x44, 0x33]);
    expect(audio.requestId, 'audio-request-id');
    expect(audio.contentType, 'audio/mpeg');
    expect(audio.requestHash, startsWith('fedcba'));
    expect(audio.cacheKey, startsWith('docent_audio:'));
  });

  test('createDocentAudio uses the current provider token exactly once',
      () async {
    var providerCalls = 0;
    var currentToken = 'stale-audio-token';
    late RequestOptions captured;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      bearerToken: 'static-audio-token',
      apiKey: 'static-api-key',
      accessTokenProvider: () async {
        providerCalls++;
        return '  $currentToken  ';
      },
      dio: _dio((request) async {
        captured = request;
        return _audio(
          [0x49, 0x44, 0x33],
          headers: {
            'content-type': ['audio/mpeg'],
          },
        );
      }),
    );

    currentToken = 'fresh-audio-token';
    await client.createDocentAudio(script: 'dynamic audio script');

    expect(providerCalls, 1);
    expect(_h(captured, 'authorization'), 'Bearer fresh-audio-token');
    expect(_h(captured, 'x-api-key'), isNull);
  });

  test('JSON error envelope becomes LalaApiException without body leakage',
      () async {
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      bearerToken: 'bad-token',
      dio: _dio((request) async {
        return _json(
          {
            'ok': false,
            'data': null,
            'meta': {'request_id': 'error-request-id'},
            'error': {
              'code': 'UNAUTHORIZED',
              'message': 'Invalid client credentials.',
              'retryable': false,
            },
          },
          status: 401,
          headers: {
            'content-type': ['application/json'],
          },
        );
      }),
    );

    await expectLater(
      client.getWeather(lat: 37.2, lng: 127.0),
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
  });

  test('network timeout becomes retryable LalaApiException', () async {
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      bearerToken: 'slow-token',
      dio: _dio((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return _json({
          'ok': true,
          'data': _weatherPayload(),
          'meta': {'request_id': 'late-server-request-id'},
          'error': null,
        });
      }),
    );

    await expectLater(
      client.getWeather(
        lat: 37.2,
        lng: 127.0,
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

  test('getWeather default budget tolerates the backend DB+AirKorea cold path',
      () {
    // The weather endpoint does a DB lookup plus an external AirKorea call in
    // sequence; a cold response (~8.5s observed in production) outlasts the
    // generic 8s readTimeout. Its default budget must therefore be larger than
    // readTimeout, or the map pins a permanent "weather preparing" pill because
    // the swallowed REQUEST_TIMEOUT leaves the client with no weather.
    fakeAsync((async) {
      final client = LalaApiClient(
        baseUri: Uri.parse('http://api.example.test'),
        dio: _dio((request) async {
          await Future<void>.delayed(const Duration(seconds: 9));
          return _json({
            'ok': true,
            'data': _weatherPayload(),
            'meta': {'request_id': 'slow-weather-id'},
            'error': null,
          });
        }),
      );

      LalaEnvelope<LalaWeather>? result;
      Object? error;
      unawaited(
        client.getWeather(lat: 37.2, lng: 127.0).then((value) {
          result = value;
        }).catchError((Object e) {
          error = e;
        }),
      );

      // 9s > readTimeout (8s) but < weatherTimeout (16s): a read-sized budget
      // would have timed out here; the weather-sized budget resolves.
      async.elapse(const Duration(seconds: 9));
      expect(error, isNull);
      expect(result, isNotNull);
      expect(
        result?.data?.source,
        'kma_ultra_srt_ncst+airkorea_sido_realtime',
      );
      client.close();
    });
  });

  test(
      '/api/v1 routes can be sent without client auth when caller has no token',
      () async {
    late RequestOptions captured;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      dio: _dio((request) async {
        captured = request;
        return _json({
          'ok': true,
          'data': {
            'count': 0,
            'places': <Object?>[],
            'query': {
              'lat': 37.5665,
              'lng': 126.978,
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

    final envelope = await client.getPlaces(lat: 37.5665, lng: 126.978);

    expect(_h(captured, 'authorization'), isNull);
    expect(_h(captured, 'x-api-key'), isNull);
    expect(envelope.ok, isTrue);
    expect(envelope.requestId, 'no-token-request-id');
  });

  // --- ONMU P3c: 커뮤니티 채팅 REST + WebSocket URI 테스트 ---

  test('getChatRooms parses rooms list with pagination query', () async {
    late RequestOptions captured;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      dio: _dio(
        (request) async {
          captured = request;
          return _json({
            'ok': true,
            'data': {
              'count': 2,
              'total': 5,
              'rooms': [
                {
                  'id': '11111111-1111-1111-1111-111111111111',
                  'name': '수원 채팅방',
                  'created_at': '2026-07-20T10:00:00Z',
                },
                {
                  'id': '22222222-2222-2222-2222-222222222222',
                  'name': 'general',
                  'created_at': '2026-07-21T11:30:00Z',
                },
              ],
            },
            'meta': <String, Object?>{},
            'error': null,
          });
        },
      ),
    );

    final envelope = await client.getChatRooms(limit: 10, offset: 20);

    expect(captured.method, 'GET');
    expect(captured.uri.path, '/api/v1/community/chat/rooms');
    expect(captured.uri.queryParameters['limit'], '10');
    expect(captured.uri.queryParameters['offset'], '20');
    expect(envelope.data?.count, 2);
    expect(envelope.data?.total, 5);
    expect(envelope.data?.rooms.length, 2);
    expect(
        envelope.data?.rooms.first.id, '11111111-1111-1111-1111-111111111111');
    expect(envelope.data?.rooms.first.name, '수원 채팅방');
    expect(envelope.data?.rooms.last.createdAt, '2026-07-21T11:30:00Z');
  });

  test('createChatRoom sends JSON name with OAuth bearer auth', () async {
    late RequestOptions captured;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      accessTokenProvider: () async => 'oauth-room-token',
      dio: _dio(
        (request) async {
          captured = request;
          return _json({
            'ok': true,
            'data': {
              'id': '33333333-3333-3333-3333-333333333333',
              'name': '새방',
              'created_at': '2026-07-22T09:00:00Z',
            },
            'meta': <String, Object?>{},
            'error': null,
          });
        },
      ),
    );

    final envelope = await client.createChatRoom(name: '새방');

    expect(captured.method, 'POST');
    expect(captured.uri.path, '/api/v1/community/chat/rooms');
    expect(captured.data, {'name': '새방'});
    expect(_h(captured, 'authorization'), 'Bearer oauth-room-token');
    expect(_h(captured, 'content-type'), contains('application/json'));
    expect(envelope.data?.id, '33333333-3333-3333-3333-333333333333');
    expect(envelope.data?.name, '새방');
  });

  test('getChatMessages parses messages and tolerates null author', () async {
    late RequestOptions captured;
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      dio: _dio(
        (request) async {
          captured = request;
          return _json({
            'ok': true,
            'data': {
              'count': 2,
              'total': 2,
              'messages': [
                {
                  'id': 'm1',
                  'room_id': 'room-1',
                  'author_user_id': null,
                  'body': '익명 인사',
                  'created_at': '2026-07-22T09:01:00Z',
                },
                {
                  'id': 'm2',
                  'room_id': 'room-1',
                  'author_user_id': 'user-42',
                  'body': '안녕!',
                  'created_at': '2026-07-22T09:02:00Z',
                },
              ],
            },
            'meta': <String, Object?>{},
            'error': null,
          });
        },
      ),
    );

    final envelope =
        await client.getChatMessages(roomId: 'room-1', limit: 50, offset: 0);

    expect(captured.method, 'GET');
    expect(captured.uri.path, '/api/v1/community/chat/rooms/room-1/messages');
    expect(captured.uri.queryParameters['limit'], '50');
    expect(envelope.data?.messages.length, 2);
    expect(envelope.data?.messages.first.authorUserId, isNull);
    expect(envelope.data?.messages.first.body, '익명 인사');
    expect(envelope.data?.messages.last.authorUserId, 'user-42');
  });

  test('chatWebSocketUri builds ws/wss URI with token query param', () {
    final insecure = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test:8080'),
    );
    final wsUri = insecure.chatWebSocketUri(
      roomId: 'room-9',
      token: 'abc.def.ghi',
    );
    expect(wsUri.scheme, 'ws');
    expect(wsUri.host, 'api.example.test');
    expect(wsUri.port, 8080);
    expect(wsUri.path, '/api/v1/community/chat/rooms/room-9/ws');
    expect(wsUri.queryParameters['token'], 'abc.def.ghi');

    final secure =
        LalaApiClient(baseUri: Uri.parse('https://api.example.test'));
    final wssUri = secure.chatWebSocketUri(roomId: 'r', token: 't');
    expect(wssUri.scheme, 'wss');
    expect(wssUri.path, '/api/v1/community/chat/rooms/r/ws');
  });

  test('resolveWebSocketToken prefers provider token then static bearer',
      () async {
    final withProvider = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      bearerToken: 'static-bearer',
      accessTokenProvider: () async => 'dynamic-token',
    );
    expect(await withProvider.resolveWebSocketToken(), 'dynamic-token');

    final staticOnly = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      bearerToken: '  static-bearer  ',
    );
    expect(await staticOnly.resolveWebSocketToken(), 'static-bearer');

    final none = LalaApiClient(baseUri: Uri.parse('http://api.example.test'));
    expect(await none.resolveWebSocketToken(), '');
  });

  // V5-A planning action models + endpoints.

  test('V5-A action models parse their wire shapes and stay null-honest', () {
    final saved = LalaSavedPlace.fromJsonObject(const {
      'place_id': 'p1',
      'source': 'db',
      'saved_at': '2026-08-14T00:00:00Z',
    });
    expect(saved.placeId, 'p1');
    expect(saved.source, 'db');
    expect(saved.savedAt, '2026-08-14T00:00:00Z');

    final toggle = LalaSaveToggleResult.fromJsonObject(const {
      'place_id': 'p1',
      'saved': false,
      'changed': false,
    });
    expect(toggle.saved, isFalse);
    expect(toggle.changed, isFalse);

    final visit = LalaSlotVisit.fromJsonObject(const {
      'slot_period': 'morning',
      'status': 'visited',
      'place_id': null,
      'reason_code': null,
      'use_for_recommendations': true,
      'visited_at': null,
      'confirmed_at': '2026-09-03T00:00:00Z',
    });
    expect(visit.slotPeriod, 'morning');
    expect(visit.status, 'visited');
    expect(visit.placeId, isNull);
    expect(visit.useForRecommendations, isTrue);
    expect(visit.confirmedAt, '2026-09-03T00:00:00Z');

    final savesData = LalaSavedPlacesData.fromJsonObject(
        const {'items': <Map<String, dynamic>>[]});
    expect(savesData.items, isEmpty);

    final visitsData = LalaSlotVisitsData.fromJsonObject(const {
      'items': <Map<String, dynamic>>[
        {'slot_period': 'lunch', 'status': 'planned'},
      ],
    });
    expect(visitsData.items.single.slotPeriod, 'lunch');
    expect(visitsData.items.single.status, 'planned');

    // A persisted plan with no embedded plan degrades to a null plan field.
    final persisted = LalaPersistedPlan.fromJsonObject(const {
      'plan_date': '2026-08-14',
      'schema_version': 1,
      'plan': null,
      'updated_at': null,
    });
    expect(persisted.planDate, '2026-08-14');
    expect(persisted.schemaVersion, 1);
    expect(persisted.plan, isNull);

    final summaries = LalaPersistedPlansData.fromJsonObject(const {
      'items': [
        {
          'plan_date': '2026-08-14',
          'schema_version': 1,
          'region': '서울',
          'slot_count': 4,
          'visited_count': 2,
          'updated_at': null,
        },
      ],
    });
    expect(summaries.items.single.region, '서울');
    expect(summaries.items.single.slotCount, 4);
    expect(summaries.items.single.visitedCount, 2);

    final override = LalaTripPreferenceOverrideDocument.fromJsonObject(const {
      'plan_date': '2026-08-14',
      'schema_version': 1,
      'revision': 3,
      'override': {'version': 1, 'pace': 'relaxed'},
      'updated_at': '2026-09-03T00:00:00Z',
    });
    expect(override.revision, 3);
    expect(override.override['pace'], 'relaxed');
  });

  test('listSavedPlaces sends bearer auth and parses saved-place items',
      () async {
    final requests = <RequestOptions>[];
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      bearerToken: 'save-token',
      dio: _dio(
        (request) async => _json({
          'ok': true,
          'data': {
            'items': [
              {'place_id': 'p1', 'source': 'db', 'saved_at': null},
              {
                'place_id': 'p2',
                'source': 'public_mvp_snapshot',
                'saved_at': null
              },
            ],
          },
          'meta': {'request_id': 'saves-id'},
          'error': null,
        }),
        sink: requests.add,
      ),
    );

    final envelope = await client.listSavedPlaces();

    expect(requests.single.method, 'GET');
    expect(requests.single.uri.path, '/api/v1/me/saved-places');
    expect(requests.single.headers['authorization'], 'Bearer save-token');
    expect(envelope.data?.items.map((p) => p.placeId), ['p1', 'p2']);
    expect(envelope.data?.items.first.savedAt, isNull);
  });

  test('savePlace sends a PUT with the source body to the place path',
      () async {
    final requests = <RequestOptions>[];
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      bearerToken: 'save-token',
      dio: _dio(
        (request) async => _json({
          'ok': true,
          'data': {'place_id': 'p1', 'saved': true, 'changed': true},
          'meta': {'request_id': 'save-id'},
          'error': null,
        }),
        sink: requests.add,
      ),
    );

    final envelope = await client.savePlace(placeId: 'p1', source: 'db');

    expect(requests.single.method, 'PUT');
    expect(requests.single.uri.path, '/api/v1/me/saved-places/p1');
    expect(envelope.data?.saved, isTrue);
    expect(envelope.data?.changed, isTrue);
  });

  test('loadPersistedPlan stays honest-null when the plan is absent', () async {
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      bearerToken: 'plan-token',
      dio: _dio((request) async => _json({
            'ok': true,
            'data': null,
            'meta': {'request_id': 'plan-id'},
            'error': null,
          })),
    );

    final envelope = await client.loadPersistedPlan(planDate: '2026-08-14');

    expect(envelope.ok, isTrue);
    expect(envelope.data, isNull); // honest null, never a thrown parse
  });

  test('past plans and trip overrides use scoped planning paths', () async {
    final requests = <RequestOptions>[];
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      bearerToken: 'plan-token',
      dio: _dio(
        (request) async {
          if (request.method == 'GET' && request.uri.path.endsWith('/plans')) {
            return _json({
              'ok': true,
              'data': {'items': <Object?>[]},
              'meta': {'request_id': 'plans-id'},
              'error': null,
            });
          }
          return _json({
            'ok': true,
            'data': {
              'plan_date': '2026-08-14',
              'schema_version': 1,
              'revision': 1,
              'override': {'version': 1, 'pace': 'balanced'},
              'updated_at': '2026-09-03T00:00:00Z',
            },
            'meta': {'request_id': 'override-id'},
            'error': null,
          });
        },
        sink: requests.add,
      ),
    );

    final plans = await client.listPersistedPlans(
      before: '2026-09-01',
      limit: 10,
    );
    final saved = await client.putTripPreferenceOverride(
      planDate: '2026-08-14',
      expectedRevision: 0,
      override: const {'version': 1, 'pace': 'balanced'},
    );

    expect(plans.data?.items, isEmpty);
    expect(requests.first.uri.path, '/api/v1/me/plans');
    expect(requests.first.uri.queryParameters['before'], '2026-09-01');
    expect(requests.first.uri.queryParameters['limit'], '10');
    expect(requests.last.uri.path,
        '/api/v1/me/plans/2026-08-14/preferences');
    expect(requests.last.data, {
      'expected_revision': 0,
      'override': {'version': 1, 'pace': 'balanced'},
    });
    expect(saved.data?.revision, 1);
  });

  test('checkInSlot PUTs the status body to the slot visit path', () async {
    final requests = <RequestOptions>[];
    final client = LalaApiClient(
      baseUri: Uri.parse('http://api.example.test'),
      bearerToken: 'visit-token',
      dio: _dio(
        (request) async => _json({
          'ok': true,
          'data': {
            'slot_period': 'morning',
            'place_id': 'p1',
            'status': 'visited',
            'reason_code': null,
            'use_for_recommendations': false,
            'visited_at': null,
            'confirmed_at': null,
          },
          'meta': {'request_id': 'visit-id'},
          'error': null,
        }),
        sink: requests.add,
      ),
    );

    final envelope = await client.checkInSlot(
      planDate: '2026-08-14',
      slotPeriod: 'morning',
      placeId: 'p1',
    );

    expect(requests.single.method, 'PUT');
    expect(
        requests.single.uri.path, '/api/v1/me/plans/2026-08-14/visits/morning');
    expect(envelope.data?.status, 'visited');
    expect(envelope.data?.slotPeriod, 'morning');
    expect(requests.single.data, {
      'status': 'visited',
      'place_id': 'p1',
      'use_for_recommendations': false,
    });
  });
}

ResponseBody _placesResponse() {
  return _json({
    'ok': true,
    'data': {
      'count': 0,
      'places': <Object?>[],
      'query': {
        'lat': 37.2,
        'lng': 127.0,
        'radius_m': 1000,
        'limit': 60,
        'category': 'all',
        'language': 'ko',
      },
      'source': 'db',
      'location_engine': 'postgis',
    },
    'meta': <String, Object?>{},
    'error': null,
  });
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

Map<String, String?> _allHeaders(RequestOptions options) {
  final result = <String, String?>{};
  for (final key in options.headers.keys.cast<String>()) {
    result[key.toLowerCase()] = options.headers[key]?.toString();
  }
  return result;
}
