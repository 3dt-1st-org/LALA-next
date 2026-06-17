import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/main.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

void main() {
  testWidgets('loads public demo panels before auth is configured', (
    tester,
  ) async {
    await tester.pumpWidget(
      LalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('전체'), findsOneWidget);
    expect(find.text('명소'), findsAtLeastNWidgets(1));
    expect(find.text('대시보드'), findsNothing);
    expect(find.text('추천 장소 보기'), findsOneWidget);
    expect(find.textContaining('KAKAO_JAVASCRIPT_KEY'), findsOneWidget);
    expect(find.text('로컬 점수'), findsNothing);
    expect(find.text('내국인 소비'), findsNothing);
    expect(find.text('수요 분산'), findsNothing);
    expect(find.text('문화 연계'), findsNothing);
    expect(find.text('날씨 적합'), findsNothing);
    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
    expect(find.text('86'), findsNothing);
    expect(find.textContaining('14°C'), findsWidgets);
    expect(find.text('정보 더 듣기'), findsOneWidget);
    expect(find.text('오늘 코스에 추가'), findsOneWidget);
    expect(find.text('TourAPI'), findsNothing);
    expect(find.textContaining('조선 왕실'), findsOneWidget);

    final evidenceButton = find.widgetWithText(TextButton, '점수/근거');
    await tester.ensureVisible(evidenceButton);
    await tester.tap(evidenceButton);
    await tester.pumpAndSettle();

    expect(find.text('로컬 점수'), findsOneWidget);
    expect(find.text('내국인 소비'), findsOneWidget);
    expect(find.text('수요 분산'), findsOneWidget);
    expect(find.text('문화 연계'), findsOneWidget);
    expect(find.text('날씨 적합'), findsOneWidget);
    expect(find.text('86'), findsAtLeastNWidgets(1));
    expect(find.text('TourAPI'), findsOneWidget);
  });

  testWidgets('filters places from category chips and toggles map modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      LalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('맛집').first);
    await tester.pumpAndSettle();

    expect(find.text('행궁동 카페거리'), findsAtLeastNWidgets(1));
    expect(find.text('행궁동 카페거리 도슨트'), findsOneWidget);

    final voiceToggle = find.byKey(const ValueKey('voice-toggle'));
    expect(
      find.descendant(of: voiceToggle, matching: find.text('ON')),
      findsOneWidget,
    );
    await tester.tap(voiceToggle);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: voiceToggle, matching: find.text('OFF')),
      findsOneWidget,
    );

    final autoToggle = find.byKey(const ValueKey('auto-docent-toggle'));
    expect(
      find.descendant(of: autoToggle, matching: find.text('OFF')),
      findsOneWidget,
    );
    await tester.tap(autoToggle);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: autoToggle, matching: find.text('ON')),
      findsOneWidget,
    );
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

    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
    expect(find.textContaining('14°C'), findsWidgets);
    expect(find.textContaining('조선 왕실'), findsOneWidget);
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

    expect(
      find.text('UPSTREAM_UNAVAILABLE: Authenticated route failed.'),
      findsNothing,
    );
    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
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

    await tester.tap(find.byIcon(Icons.settings).first);
    await tester.pumpAndSettle();

    expect(find.text('개인정보 동의 안내'), findsOneWidget);
    expect(find.text('위치기반 정보 제공 동의'), findsOneWidget);
    expect(find.text('언어'), findsOneWidget);
    expect(find.text('글꼴 크기'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('개발 연결'),
      320,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('개발 연결'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Base URL'),
      'http://10.0.0.5:8080',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Migration API key'),
      'migration-key',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Kakao JavaScript key'),
      'kakao-js-key',
    );
    final refreshButton = find.widgetWithText(FilledButton, 'Refresh');
    await tester.ensureVisible(refreshButton);
    await tester.pumpAndSettle();
    await tester.tap(refreshButton);
    await tester.pumpAndSettle();

    expect(configs.last.baseUri, 'http://10.0.0.5:8080');
    expect(configs.last.apiKey, 'migration-key');
    expect(configs.last.kakaoJavascriptKey, 'kakao-js-key');
  });

  testWidgets('settings language switch updates map filter labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      LalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Attractions'), findsOneWidget);
    expect(find.text('Daily Plan'), findsOneWidget);
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

    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
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
    expect(find.text('정보 더 듣기'), findsOneWidget);

    final audioButton = find.widgetWithText(FilledButton, '정보 더 듣기');
    await tester.ensureVisible(audioButton);
    await tester.pumpAndSettle();
    await tester.tap(audioButton);
    await tester.pumpAndSettle();

    expect(backend.audioRequests, [
      '화성행궁은 조선 왕실의 이동 궁궐로, 수원화성과 함께 걷기 좋은 코스입니다.',
    ]);
    expect(find.text('4 bytes'), findsOneWidget);
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
        count: 3,
        places: [_place(), _culturePlace(), _restaurantPlace()],
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
        place: _place(),
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() async {
    return _envelope(
      LalaDailyPlan(
        language: 'ko',
        center: LalaCoordinate(lat: config.lat, lng: config.lng),
        radiusM: config.radiusM,
        weather: _weather(),
        slots: [
          LalaPlanSlot(period: 'morning', title: '화성행궁 산책 코스', place: _place()),
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
        script: '화성행궁은 조선 왕실의 이동 궁궐로, 수원화성과 함께 걷기 좋은 코스입니다.',
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
    placeId: 'hwaseong-haenggung',
    name: '화성행궁',
    category: 'attraction',
    lat: 37.2819,
    lng: 127.0142,
    address: '경기도 수원시 팔달구 정조로 825',
    distanceM: 145,
    source: 'skeleton',
    score: LalaPlaceScore(
      finalScore: 0.86,
      formulaVersion: 'local-value-v1',
      components: LalaPlaceScoreComponents(
        localSpendingScore: 0.82,
        demandDispersionScore: 0.78,
        weatherFitScore: 0.74,
        reviewQualityScore: null,
        cultureRelevanceScore: 0.91,
      ),
      dataBasis: 'demo_fallback',
      features: {
        'missing_signals': <String>['card_spending_snapshot'],
      },
    ),
  );
}

LalaPlace _culturePlace() {
  return const LalaPlace(
    placeId: 'suwon-hwaseong',
    name: '수원화성',
    category: 'culture_venue',
    lat: 37.2870,
    lng: 127.0110,
    address: '경기도 수원시 장안구 영화동',
    distanceM: 620,
    source: 'skeleton',
    score: LalaPlaceScore(
      finalScore: 0.82,
      formulaVersion: 'local-value-v1',
      components: LalaPlaceScoreComponents(
        localSpendingScore: 0.68,
        demandDispersionScore: 0.73,
        weatherFitScore: 0.76,
        reviewQualityScore: null,
        cultureRelevanceScore: 0.96,
      ),
      dataBasis: 'demo_fallback',
      features: {
        'signals': <String>['tour_api', 'culture_data'],
      },
    ),
  );
}

LalaPlace _restaurantPlace() {
  return const LalaPlace(
    placeId: 'haenggung-cafe-street',
    name: '행궁동 카페거리',
    category: 'restaurant',
    lat: 37.2828,
    lng: 127.0101,
    address: '경기도 수원시 팔달구 행궁동',
    distanceM: 780,
    source: 'skeleton',
    score: LalaPlaceScore(
      finalScore: 0.78,
      formulaVersion: 'local-value-v1',
      components: LalaPlaceScoreComponents(
        localSpendingScore: 0.88,
        demandDispersionScore: 0.54,
        weatherFitScore: 0.70,
        reviewQualityScore: null,
        cultureRelevanceScore: 0.62,
      ),
      dataBasis: 'demo_fallback',
      features: {
        'signals': <String>['card_spending', 'local_business'],
      },
    ),
  );
}

LalaWeather _weather() {
  return const LalaWeather(
    lat: 37.2636,
    lng: 127.0286,
    temp: '14°C',
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
