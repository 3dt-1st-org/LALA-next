import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/main.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

void main() {
  testWidgets('loads public readiness before auth is configured', (
    tester,
  ) async {
    await tester.pumpWidget(
      LalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('LALA Next'), findsOneWidget);
    expect(find.text('ok'), findsWidgets);
    expect(find.text('skeleton'), findsWidgets);
    expect(find.text('public only'), findsOneWidget);
    expect(find.text('Add auth to load nearby places.'), findsOneWidget);
  });

  testWidgets('loads authenticated API panels with the reference contract', (
    tester,
  ) async {
    await tester.pumpWidget(
      LalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(
          baseUri: 'http://api.test',
          bearerToken: 'test-token',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('static bearer'), findsOneWidget);
    expect(find.text('Suwon Hwaseong'), findsOneWidget);
    expect(find.text('22C'), findsOneWidget);
    expect(find.textContaining('Morning landmark walk'), findsOneWidget);
    expect(find.text('Docent story for Suwon Hwaseong.'), findsOneWidget);
    expect(find.text('ready test-request-id'), findsOneWidget);
    expect(find.text('places test-request-id'), findsOneWidget);
    expect(find.text('plan test-request-id'), findsOneWidget);
    expect(find.text('docent test-request-id'), findsOneWidget);
  });

  testWidgets('keeps public readiness visible when authenticated load fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      LalaApp(
        backendFactory: (config) =>
            FakeBackend(config, failAuthenticatedLoad: true),
        initialConfig: const LalaAppConfig(
          baseUri: 'http://api.test',
          bearerToken: 'test-token',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('ok'), findsWidgets);
    expect(find.text('skeleton'), findsWidgets);
    expect(find.text('static bearer'), findsOneWidget);
    expect(
      find.text('UPSTREAM_UNAVAILABLE: Authenticated route failed.'),
      findsOneWidget,
    );
    expect(find.text('No places returned.'), findsOneWidget);
  });

  testWidgets('refresh uses edited backend configuration', (tester) async {
    final configs = <LalaAppConfig>[];

    await tester.pumpWidget(
      LalaApp(
        backendFactory: (config) {
          configs.add(config);
          return FakeBackend(config);
        },
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Base URL'),
      'http://10.0.0.5:8080',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Migration API key'),
      'migration-key',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Refresh'));
    await tester.pumpAndSettle();

    expect(configs.last.baseUri, 'http://10.0.0.5:8080');
    expect(configs.last.apiKey, 'migration-key');
    expect(find.text('migration key'), findsOneWidget);
  });

  testWidgets('surfaces OAuth JWT auth mode separately from static bearer', (
    tester,
  ) async {
    await tester.pumpWidget(
      LalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(
          baseUri: 'http://api.test',
          bearerToken: 'eyJhbGciOiJSUzI1NiJ9.eyJzY3AiOiJsYWxhIn0.signature',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('oauth jwt'), findsOneWidget);
    expect(find.text('Suwon Hwaseong'), findsOneWidget);
  });

  testWidgets('fetches docent audio only after explicit tap', (tester) async {
    final backend = FakeBackend(
      const LalaAppConfig(
        baseUri: 'http://api.test',
        bearerToken: 'test-token',
      ),
    );

    await tester.pumpWidget(
      LalaApp(
        backendFactory: (_) => backend,
        initialConfig: const LalaAppConfig(
          baseUri: 'http://api.test',
          bearerToken: 'test-token',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(backend.audioRequests, isEmpty);
    expect(find.text('Fetch audio'), findsOneWidget);

    final audioButton = find.widgetWithText(FilledButton, 'Fetch audio');
    await tester.ensureVisible(audioButton);
    await tester.pumpAndSettle();
    await tester.tap(audioButton);
    await tester.pumpAndSettle();

    expect(backend.audioRequests, ['Docent story for Suwon Hwaseong.']);
    expect(find.text('4 bytes'), findsOneWidget);
    expect(find.text('docent_audio:test-audio-cache'), findsOneWidget);
    expect(find.text('audio audio-request-id'), findsOneWidget);
  });
}

class FakeBackend implements LalaBackend {
  FakeBackend(this.config, {this.failAuthenticatedLoad = false});

  final LalaAppConfig config;
  final bool failAuthenticatedLoad;
  final List<String> audioRequests = <String>[];

  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getHealth() async {
    return _envelope(<String, dynamic>{
      'status': 'ok',
      'service': 'lala-next-api',
      'version': 'test',
    });
  }

  @override
  Future<LalaEnvelope<LalaReadiness>> getReadiness() async {
    final authMode = config.authMode;
    return _envelope(
      LalaReadiness(
        status: 'ok',
        checks: {
          'client_auth': authMode.hasClientAuth ? 'configured' : 'missing',
          'client_identity': authMode == LalaAuthMode.none
              ? 'missing'
              : authMode == LalaAuthMode.oauthJwt
              ? 'oauth-configured'
              : 'static',
          'jwt_validation': authMode == LalaAuthMode.oauthJwt
              ? 'configured'
              : 'skipped',
          'db': 'skipped',
          'worker_contracts': 'configured',
        },
        mode: const LalaRuntimeMode(
          overall: 'skeleton',
          data: 'skeleton',
          ai: 'skeleton',
          speech: 'skeleton',
          worker: 'dry-run',
        ),
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async {
    if (failAuthenticatedLoad) {
      throw const LalaApiException(
        code: 'UPSTREAM_UNAVAILABLE',
        message: 'Authenticated route failed.',
        statusCode: 503,
        retryable: true,
        requestId: 'failed-auth-route',
      );
    }
    return _envelope(
      LalaPlacesResponse(
        count: 1,
        places: [_place()],
        query: LalaPlacesQuery(
          lat: config.lat,
          lng: config.lng,
          radiusM: config.radiusM,
          category: 'all',
          language: 'ko',
        ),
        source: 'skeleton',
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaWeather>> getWeather() async {
    return _envelope(_weather());
  }

  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() async {
    return _envelope(
      LalaIntervention(
        center: LalaCoordinate(lat: config.lat, lng: config.lng),
        radiusM: config.radiusM,
        shouldIntervene: false,
        reason: 'Weather is fine.',
        recommendedAction: 'Keep the current route.',
        source: 'skeleton',
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() async {
    return _envelope(
      LalaDailyPlan(
        language: 'ko',
        center: LalaCoordinate(lat: config.lat, lng: config.lng),
        weather: _weather(),
        slots: [
          LalaPlanSlot(
            period: 'morning',
            title: 'Morning landmark walk',
            place: _place(),
          ),
        ],
        source: 'skeleton',
        requestHash:
            'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
        cacheKey: 'daily_plan:abcdef0123456789abcdef0123456789',
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaDocentScript>> createDocentScript({
    required LalaPlace place,
  }) async {
    return _envelope(
      LalaDocentScript(
        placeId: place.placeId,
        category: place.category,
        language: 'ko',
        mode: 'brief',
        script: 'Docent story for ${place.name}.',
        source: 'skeleton',
        requestHash:
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        cacheKey: 'docent_script:0123456789abcdef0123456789abcdef',
      ),
    );
  }

  @override
  Future<LalaAudioResponse> createDocentAudio({required String script}) async {
    audioRequests.add(script);
    return LalaAudioResponse(
      bytes: Uint8List.fromList([0x49, 0x44, 0x33, 0x04]),
      requestId: 'audio-request-id',
      contentType: 'audio/mpeg',
      requestHash:
          'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210',
      cacheKey: 'docent_audio:test-audio-cache',
    );
  }

  @override
  void close() {}
}

LalaEnvelope<T> _envelope<T>(T data) {
  return LalaEnvelope<T>(
    ok: true,
    data: data,
    meta: const {'request_id': 'test-request-id'},
    error: null,
    statusCode: 200,
    requestId: 'test-request-id',
  );
}

LalaPlace _place() {
  return const LalaPlace(
    placeId: 'suwon-hwaseong',
    name: 'Suwon Hwaseong',
    category: 'attraction',
    lat: 37.287,
    lng: 127.011,
    address: 'Suwon',
    distanceM: 420,
    source: 'skeleton',
  );
}

LalaWeather _weather() {
  return const LalaWeather(
    lat: 37.2636,
    lng: 127.0286,
    temp: '22C',
    icon: 'partly-cloudy',
    dust: LalaDust(pm10: '31', pm25: '14', grade: 'normal', gradeKo: '보통'),
    forecast: [
      LalaForecastItem(time: '15:00', temp: '22C', icon: 'partly-cloudy'),
    ],
    outdoorStatus: 'good',
    force: false,
    source: 'skeleton',
    location: 'Suwon',
  );
}
