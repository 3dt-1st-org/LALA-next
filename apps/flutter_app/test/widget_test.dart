import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/kakao_map_fallback.dart';
import 'package:lala_next_app/kakao_map_models.dart';
import 'package:lala_next_app/main.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

void main() {
  test('map move reload policy follows the legacy places threshold', () {
    expect(
      shouldReloadPlacesForMapMove(
        hasAnyPlaces: false,
        lastFetchLat: 37.2636,
        lastFetchLng: 127.0286,
        currentLat: 37.2636,
        currentLng: 127.0286,
      ),
      isTrue,
    );
    expect(
      shouldReloadPlacesForMapMove(
        hasAnyPlaces: true,
        lastFetchLat: 37.2636,
        lastFetchLng: 127.0286,
        currentLat: 37.2640,
        currentLng: 127.0290,
      ),
      isFalse,
    );
    expect(
      shouldReloadPlacesForMapMove(
        hasAnyPlaces: true,
        lastFetchLat: 37.2636,
        lastFetchLng: 127.0286,
        currentLat: 37.2670,
        currentLng: 127.0320,
      ),
      isTrue,
    );
  });

  test('weather reload policy follows the legacy distance and age gates', () {
    final lastFetchAt = DateTime(2026, 6, 18, 10);
    final now = lastFetchAt.add(const Duration(minutes: 5));

    expect(
      shouldReloadWeatherForMapMove(
        force: true,
        hasWeather: true,
        lastFetchAt: lastFetchAt,
        lastFetchLat: 37.2636,
        lastFetchLng: 127.0286,
        currentLat: 37.2636,
        currentLng: 127.0286,
        now: now,
      ),
      isTrue,
    );
    expect(
      shouldReloadWeatherForMapMove(
        force: false,
        hasWeather: true,
        lastFetchAt: lastFetchAt,
        lastFetchLat: 37.2636,
        lastFetchLng: 127.0286,
        currentLat: 37.2640,
        currentLng: 127.0290,
        now: now,
      ),
      isFalse,
    );
    expect(
      shouldReloadWeatherForMapMove(
        force: false,
        hasWeather: true,
        lastFetchAt: lastFetchAt,
        lastFetchLat: 37.2636,
        lastFetchLng: 127.0286,
        currentLat: 37.2636,
        currentLng: 127.0286,
        now: lastFetchAt.add(const Duration(minutes: 10)),
      ),
      isTrue,
    );
    expect(
      shouldReloadWeatherForMapMove(
        force: false,
        hasWeather: true,
        lastFetchAt: lastFetchAt,
        lastFetchLat: 37.2636,
        lastFetchLng: 127.0286,
        currentLat: 37.3600,
        currentLng: 127.1200,
        now: now,
      ),
      isTrue,
    );
  });

  test('single retry loader retries once only when allowed', () async {
    var attempts = 0;
    final result = await loadWithSingleRetry(
      () async {
        attempts += 1;
        if (attempts == 1) {
          throw StateError('temporary');
        }
        return 'ok';
      },
      shouldRetry: true,
      retryDelay: Duration.zero,
    );

    expect(result, 'ok');
    expect(attempts, 2);
  });

  test(
    'single retry loader surfaces the first failure when retry is disabled',
    () async {
      var attempts = 0;

      await expectLater(
        () => loadWithSingleRetry(
          () async {
            attempts += 1;
            throw StateError('temporary');
          },
          shouldRetry: false,
          retryDelay: Duration.zero,
        ),
        throwsA(isA<StateError>()),
      );

      expect(attempts, 1);
    },
  );

  test('map clustering waits for dense point count and zoom threshold', () {
    final places = [
      _clusterRestaurant('cluster-food-a', '클러스터 맛집 A', 210),
      _clusterRestaurant('cluster-food-b', '클러스터 맛집 B', 260),
      _clusterRestaurant('cluster-food-c', '클러스터 맛집 C', 310),
    ];

    final defaultLevelMarkers = clusterMapPlacesForMap(
      places: places,
      selected: null,
      mapLevel: 4,
      language: 'ko',
    );
    expect(defaultLevelMarkers.where((marker) => marker.isCluster), isEmpty);
    expect(
      defaultLevelMarkers.map((marker) => marker.id),
      containsAll(['cluster-food-a', 'cluster-food-b', 'cluster-food-c']),
    );

    final mediumZoomMarkers = clusterMapPlacesForMap(
      places: places,
      selected: null,
      mapLevel: 7,
      language: 'ko',
    );
    expect(mediumZoomMarkers.where((marker) => marker.isCluster), isEmpty);

    final densePlaces = List<LalaPlace>.generate(
      30,
      (index) => _clusterRestaurant(
        'cluster-food-$index',
        '클러스터 맛집 ${index + 1}',
        210 + index,
      ),
    );
    final defaultDenseMarkers = clusterMapPlacesForMap(
      places: densePlaces,
      selected: null,
      mapLevel: 7,
      language: 'ko',
    );
    expect(defaultDenseMarkers.where((marker) => marker.isCluster), isEmpty);
    expect(
      defaultDenseMarkers.map((marker) => marker.id),
      containsAll(densePlaces.map((place) => place.placeId)),
    );

    final zoomedOutMarkers = clusterMapPlacesForMap(
      places: densePlaces,
      selected: null,
      mapLevel: 8,
      language: 'ko',
    );
    expect(zoomedOutMarkers.where((marker) => marker.isCluster), isEmpty);

    final veryDensePlaces = List<LalaPlace>.generate(
      90,
      (index) => _clusterRestaurant(
        'very-dense-food-$index',
        '클러스터 맛집 ${index + 1}',
        210 + index,
      ),
    );
    final zoomedFarOutMarkers = clusterMapPlacesForMap(
      places: veryDensePlaces,
      selected: null,
      mapLevel: 9,
      language: 'ko',
    );
    expect(zoomedFarOutMarkers.where((marker) => marker.isCluster), isEmpty);
    expect(
      zoomedFarOutMarkers.map((marker) => marker.id),
      veryDensePlaces.take(60).map((place) => place.placeId),
    );

    final fullyZoomedOutMarkers = clusterMapPlacesForMap(
      places: veryDensePlaces,
      selected: null,
      mapLevel: 10,
      language: 'ko',
    );
    expect(
      fullyZoomedOutMarkers
          .where((marker) => !marker.isCluster)
          .map((marker) => marker.id),
      veryDensePlaces.take(36).map((place) => place.placeId),
    );
    expect(
      fullyZoomedOutMarkers.where((marker) => marker.isCluster),
      hasLength(1),
    );
    final cluster = fullyZoomedOutMarkers.singleWhere(
      (marker) => marker.isCluster,
    );
    expect(cluster.clusterCount, 24);
    expect(
      cluster.clusterMemberIds,
      veryDensePlaces.skip(36).take(24).map((place) => place.placeId).toList(),
    );
  });

  test(
    'map clustering keeps nearest places expanded when API order shifts',
    () {
      final places = List<LalaPlace>.generate(
        90,
        (index) => _clusterRestaurant(
          'distance-sorted-food-$index',
          '거리 맛집 ${index + 1}',
          200 + index,
        ),
      ).reversed.toList(growable: false);

      final markers = clusterMapPlacesForMap(
        places: places,
        selected: null,
        mapLevel: 10,
        language: 'ko',
      );

      final pinIds = markers
          .where((marker) => !marker.isCluster)
          .map((marker) => marker.id)
          .toList();

      expect(
        pinIds,
        containsAll(
          List.generate(36, (index) => 'distance-sorted-food-$index'),
        ),
      );
      expect(markers.where((marker) => marker.isCluster), hasLength(1));
    },
  );

  testWidgets('map fallback does not invent places when data is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 390,
          height: 640,
          child: KakaoMapFallbackView(
            message: '현재 지도를 표시할 수 없습니다.',
            language: 'ko',
            centerLat: 37.2636,
            centerLng: 127.0286,
            places: <KakaoMapPlace>[],
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('kakao-map-marker-fallback-center')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('kakao-map-marker-fallback-food')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('kakao-map-marker-fallback-culture')),
      findsNothing,
    );
    expect(find.text('로컬 맛집'), findsNothing);
    expect(find.text('문화 행사'), findsNothing);
    expect(find.text('현재 지도를 표시할 수 없습니다.'), findsOneWidget);
  });

  testWidgets('map fallback renders only supplied real places', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 390,
          height: 640,
          child: KakaoMapFallbackView(
            message: '현재 지도를 표시할 수 없습니다.',
            language: 'ko',
            centerLat: 37.2636,
            centerLng: 127.0286,
            places: <KakaoMapPlace>[
              KakaoMapPlace(
                id: 'official-place',
                name: '공식 장소',
                category: 'attraction',
                lat: 37.2636,
                lng: 127.0286,
                selected: true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('kakao-map-marker-official-place')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('kakao-map-marker-fallback-food')),
      findsNothing,
    );
    expect(find.text('공식 장소'), findsOneWidget);
  });

  testWidgets('loads live db-backed panels without authentication', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('전체'), findsOneWidget);
    expect(find.text('명소'), findsAtLeastNWidgets(1));
    expect(find.text('대시보드'), findsNothing);
    expect(find.text('추천 장소 접기'), findsOneWidget);
    expect(find.textContaining('현재 지도를 표시할 수 없습니다'), findsOneWidget);
    expect(find.text('로컬 점수'), findsNothing);
    expect(find.text('내국인 소비'), findsNothing);
    expect(find.text('수요 분산'), findsNothing);
    expect(find.text('문화 연계'), findsNothing);
    expect(find.text('날씨 적합'), findsNothing);
    expect(find.textContaining('관광 수요 분산'), findsNothing);
    expect(find.textContaining('공식 문화데이터'), findsNothing);
    expect(find.textContaining('지역 소비 신호'), findsNothing);
    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
    expect(find.text('86'), findsNothing);
    expect(find.textContaining('14°C'), findsWidgets);
    expect(find.text('정보 더 듣기'), findsOneWidget);
    expect(find.text('하루 일정 보기'), findsOneWidget);
    expect(find.text('한국관광공사'), findsNothing);
    expect(find.textContaining('조선 왕실'), findsAtLeastNWidgets(1));

    final addToPlanButton = find.widgetWithText(OutlinedButton, '하루 일정 보기');
    await tester.ensureVisible(addToPlanButton);
    await tester.pumpAndSettle();
    await tester.tap(addToPlanButton);
    await tester.pumpAndSettle();

    expect(find.text('하루 일정'), findsAtLeastNWidgets(1));
    expect(find.textContaining('화성행궁'), findsAtLeastNWidgets(1));

    await tester.tap(find.byTooltip('닫기').first);
    await tester.pumpAndSettle();

    final evidenceButton = find.widgetWithText(TextButton, '점수/근거');
    await tester.ensureVisible(evidenceButton);
    await tester.tap(evidenceButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('detail-place-hero-image')), findsNothing);
    expect(find.text('로컬 점수'), findsOneWidget);
    expect(find.text('내국인 소비'), findsOneWidget);
    expect(find.text('수요 분산'), findsOneWidget);
    expect(find.text('문화 연계'), findsOneWidget);
    expect(find.text('날씨 적합'), findsOneWidget);
    expect(find.text('86'), findsAtLeastNWidgets(1));
    expect(find.text('한국관광공사'), findsOneWidget);
    expect(find.text('카드 소비'), findsOneWidget);
    expect(find.text('문화행사 데이터'), findsOneWidget);
    expect(find.textContaining('날씨'), findsWidgets);
    expect(find.textContaining('스냅샷'), findsNothing);
    expect(find.textContaining('데모'), findsNothing);
  });

  testWidgets('requests current location before loading recommendations', (
    tester,
  ) async {
    final configs = <LalaAppConfig>[];
    final backends = <FakeBackend>[];
    final locationProvider = FakeLocationProvider(
      const LalaLocationResult.found(LalaLocation(lat: 37.5665, lng: 126.9780)),
    );

    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) {
          configs.add(config);
          final backend = FakeBackend(config);
          backends.add(backend);
          return backend;
        },
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        locationProvider: locationProvider,
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('현재 위치에서 시작할게요'), findsNothing);
    expect(find.byKey(const ValueKey('location-start-confirm')), findsNothing);
    expect(locationProvider.requests, 1);
    expect(configs, isNotEmpty);
    expect(configs.last.lat, 37.5665);
    expect(configs.last.lng, 126.9780);
    expect(backends.first.placesRequestConfigs, isEmpty);
    expect(backends.last.placesRequestConfigs.single.lat, 37.5665);
    expect(backends.last.placesRequestConfigs.single.lng, 126.9780);
    expect(backends.last.weatherRequestConfigs.single.lat, 37.5665);
    expect(backends.last.weatherRequestConfigs.single.lng, 126.9780);
    expect(backends.last.interventionRequestConfigs.single.lat, 37.5665);
    expect(backends.last.interventionRequestConfigs.single.lng, 126.9780);
    expect(backends.last.dailyPlanRequestConfigs.single.lat, 37.5665);
    expect(backends.last.dailyPlanRequestConfigs.single.lng, 126.9780);
    expect(
      backends.last.docentScriptRequests.single,
      'brief:hwaseong-haenggung',
    );
    expect(find.text('추천 장소 접기'), findsOneWidget);
    expect(find.text('날씨 데이터 준비 중'), findsNothing);
  });

  testWidgets('can keep the explicit location start prompt when configured', (
    tester,
  ) async {
    final locationProvider = FakeLocationProvider(
      const LalaLocationResult.found(LalaLocation(lat: 37.5665, lng: 126.9780)),
    );

    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        locationProvider: locationProvider,
        requireLocationStartConfirmation: true,
      ),
    );

    await tester.pump();

    expect(find.text('현재 위치에서 시작할게요'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('location-start-confirm')),
      findsOneWidget,
    );
    expect(locationProvider.requests, 0);

    await tester.tap(find.byKey(const ValueKey('location-start-confirm')));
    await tester.pumpAndSettle();

    expect(locationProvider.requests, 1);
    expect(find.text('추천 장소 접기'), findsOneWidget);
  });

  testWidgets('continues location recommendations when readiness is slow', (
    tester,
  ) async {
    final backends = <FakeBackend>[];
    final locationProvider = FakeLocationProvider(
      const LalaLocationResult.found(LalaLocation(lat: 37.5665, lng: 126.9780)),
    );

    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) {
          final backend = FakeBackend(config, failReadinessLoad: true);
          backends.add(backend);
          return backend;
        },
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        locationProvider: locationProvider,
      ),
    );

    await tester.pumpAndSettle();

    expect(locationProvider.requests, 1);
    expect(backends.last.placesRequestConfigs.single.lat, 37.5665);
    expect(backends.last.weatherRequestConfigs.single.lat, 37.5665);
    expect(backends.last.dailyPlanRequests, 1);
    expect(find.text('추천 장소 접기'), findsOneWidget);
    expect(find.textContaining('요청을 처리하지 못했습니다'), findsNothing);
  });

  testWidgets('loads core startup requests in parallel', (tester) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) => FakeBackend(
          config,
          healthDelay: const Duration(milliseconds: 200),
          readinessDelay: const Duration(milliseconds: 200),
          placesDelay: const Duration(milliseconds: 200),
        ),
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(find.text('추천 장소 접기'), findsOneWidget);
    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
  });

  testWidgets(
    'pending map state shows no hard-coded venues and renders real places on load',
    (tester) async {
      await tester.pumpWidget(
        TestLalaApp(
          backendFactory: (config) =>
              FakeBackend(config, placesDelay: const Duration(seconds: 5)),
          initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      // 모바일 비주얼 계약 remediation B: 응답 전에는 하드코딩 시작 추천(venue/핀)이 없다.
      expect(find.text('히말라야정원'), findsNothing);
      expect(find.text('나혜석거리'), findsNothing);
      expect(find.text('경기아트센터'), findsNothing);
      expect(find.text('제3회 발달장애인 문화예술페스티벌'), findsNothing);
      // 정직한 대기 메시지는 노출되어도 좋다.
      expect(find.text('추천을 준비 중입니다'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // 실제 응답 도착 후에만 실제 장소가 렌더된다.
      expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'shows current location startup state while permission is pending',
    (tester) async {
      final locationProvider = PendingLocationProvider();

      await tester.pumpWidget(
        TestLalaApp(
          backendFactory: FakeBackend.new,
          initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
          locationProvider: locationProvider,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('현재 위치로 시작할게요'), findsOneWidget);
      expect(find.text('위치 권한 확인 중'), findsOneWidget);
      expect(locationProvider.requests, 1);

      locationProvider.complete(
        const LalaLocationResult.found(
          LalaLocation(lat: 37.5665, lng: 126.9780),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('현재 위치로 시작할게요'), findsNothing);
      expect(find.text('추천 장소 접기'), findsOneWidget);
    },
  );

  testWidgets(
    'slow location startup falls back to default recommendations first',
    (tester) async {
      final locationProvider = PendingLocationProvider();

      await tester.pumpWidget(
        TestLalaApp(
          backendFactory: FakeBackend.new,
          initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
          locationProvider: locationProvider,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      expect(locationProvider.requests, 1);
      expect(find.text('추천 장소 접기'), findsOneWidget);
      expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
      expect(find.text('위치 권한 확인 중'), findsNothing);
    },
  );

  testWidgets('surfaces retry when browser location is unavailable', (
    tester,
  ) async {
    final backends = <FakeBackend>[];
    final locationProvider = FakeLocationProvider(
      const LalaLocationResult.unavailable(),
    );

    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) {
          final backend = FakeBackend(config);
          backends.add(backend);
          return backend;
        },
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        locationProvider: locationProvider,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('현재 위치를 확인해야 추천을 볼 수 있어요'), findsOneWidget);
    expect(find.text('재시도'), findsOneWidget);
    expect(find.text('지역 선택'), findsOneWidget);
    expect(backends.length, 2);
    expect(backends.first.placesRequestConfigs, isEmpty);
    expect(backends.last.placesRequestConfigs.single.lat, 37.2636);
    expect(backends.last.placesRequestConfigs.single.lng, 127.0286);
    expect(backends.last.weatherRequestConfigs.single.lat, 37.2636);
    expect(backends.last.interventionRequestConfigs.single.lng, 127.0286);
    expect(backends.last.dailyPlanRequestConfigs.single.lat, 37.2636);

    await tester.tap(find.byKey(const ValueKey('location-fallback-retry')));
    await tester.pumpAndSettle();

    expect(locationProvider.requests, 2);
    expect(backends.last.placesRequestConfigs.single.lat, 37.2636);
  });

  testWidgets('browser location denial still loads public map data', (
    tester,
  ) async {
    final backends = <FakeBackend>[];
    final locationProvider = FakeLocationProvider(
      const LalaLocationResult.denied(),
    );

    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) {
          final backend = FakeBackend(config);
          backends.add(backend);
          return backend;
        },
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        locationProvider: locationProvider,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('현재 위치를 확인해야 추천을 볼 수 있어요'), findsOneWidget);
    expect(find.text('위치기반 추천이 꺼져 있어요'), findsNothing);
    expect(backends.length, 2);
    expect(backends.last.placesRequestConfigs.single.lat, 37.2636);
    expect(backends.last.weatherRequestConfigs.single.lng, 127.0286);
  });

  testWidgets('manual location selection loads recommendations explicitly', (
    tester,
  ) async {
    final backends = <FakeBackend>[];
    final locationProvider = FakeLocationProvider(
      const LalaLocationResult.unavailable(),
    );

    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) {
          final backend = FakeBackend(config);
          backends.add(backend);
          return backend;
        },
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        locationProvider: locationProvider,
      ),
    );
    await tester.pumpAndSettle();

    expect(backends.length, 2);
    expect(backends.first.placesRequestConfigs, isEmpty);
    expect(backends.last.placesRequestConfigs.single.lat, 37.2636);
    tester
        .widget<TextButton>(
          find.byKey(const ValueKey('location-manual-select')),
        )
        .onPressed
        ?.call();
    await tester.pumpAndSettle();

    expect(find.text('지역 선택'), findsWidgets);
    await tester.tap(
      find.byKey(const ValueKey('manual-location-option-seoul-jung')),
    );
    await tester.pumpAndSettle();

    expect(locationProvider.requests, 1);
    expect(backends.length, 3);
    expect(backends.first.placesRequestConfigs, isEmpty);
    expect(backends.last.placesRequestConfigs.single.lat, 37.55986);
    expect(backends.last.placesRequestConfigs.single.lng, 126.99398);
    expect(backends.last.weatherRequestConfigs.single.lat, 37.55986);
    expect(backends.last.interventionRequestConfigs.single.lng, 126.99398);
    expect(backends.last.dailyPlanRequestConfigs.single.lat, 37.55986);
    expect(find.text('현재 위치를 확인해야 추천을 볼 수 있어요'), findsNothing);
    expect(find.text('추천 장소 접기'), findsOneWidget);
  });

  testWidgets(
    'manual location sheet supports nationwide search and province filter',
    (tester) async {
      final backends = <FakeBackend>[];
      final locationProvider = FakeLocationProvider(
        const LalaLocationResult.unavailable(),
      );

      await tester.pumpWidget(
        TestLalaApp(
          backendFactory: (config) {
            final backend = FakeBackend(config);
            backends.add(backend);
            return backend;
          },
          initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
          locationProvider: locationProvider,
        ),
      );
      await tester.pumpAndSettle();

      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('location-manual-select')),
          )
          .onPressed
          ?.call();
      await tester.pumpAndSettle();

      expect(find.text('229개 지역'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('manual-location-search')),
        '세종',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('manual-location-option-sejong-sejong')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('manual-location-search')),
        '',
      );
      await tester.tap(
        find.byKey(const ValueKey('manual-location-province-busan')),
      );
      await tester.pumpAndSettle();
      expect(find.text('16개 지역'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('manual-location-option-busan-gangseo')),
      );
      await tester.pumpAndSettle();

      expect(backends.length, 3);
      expect(backends.last.placesRequestConfigs.single.lat, 35.15930);
      expect(backends.last.placesRequestConfigs.single.lng, 128.93300);
      expect(backends.last.weatherRequestConfigs.single.lat, 35.15930);
      expect(backends.last.dailyPlanRequestConfigs.single.lng, 128.93300);
    },
  );

  testWidgets('filters places from category chips and toggles map modes', (
    tester,
  ) async {
    // 계약 뷰포트(393x852)에서 컨트롤 스택과 유틸리티 행이 겹치지 않는다.
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final configs = <LalaAppConfig>[];
    final backends = <FakeBackend>[];
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) {
          configs.add(config);
          final backend = FakeBackend(config);
          backends.add(backend);
          return backend;
        },
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();
    expect(configs.last.category, 'all');

    await tester.tap(find.text('맛집').first);
    await tester.pumpAndSettle();

    expect(configs.last.category, 'restaurant');
    expect(
      backends.fold<int>(
        0,
        (total, backend) => total + backend.weatherRequests,
      ),
      1,
    );
    expect(find.text('행궁동 카페거리'), findsAtLeastNWidgets(1));
    expect(find.text('행궁동 카페거리 도슨트'), findsOneWidget);
    expect(find.textContaining('로컬 점수'), findsNothing);
    expect(find.textContaining('지역 소비 신호'), findsNothing);
    final restaurantRailCard = find.byKey(
      const ValueKey('tour-stop-action-haenggung-cafe-street'),
    );
    // remediation C2: photo-forward 레일 카드는 이름 오버레이만(지역/거래 메타는 독 상세로).
    expect(
      find.descendant(
        of: restaurantRailCard,
        matching: find.text('행궁동 카페거리'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rail-place-image-haenggung-cafe-street')),
      findsNothing,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('recommendation-rail-list')))
          .height,
      126,
    );
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey('map-rail-place-card-haenggung-cafe-street'),
            ),
          )
          .width,
      148,
    );

    final voiceToggle = find.byKey(const ValueKey('voice-toggle'));
    expect(
      find.descendant(of: voiceToggle, matching: find.text('켬')),
      findsOneWidget,
    );
    await tester.tap(voiceToggle);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: voiceToggle, matching: find.text('끔')),
      findsOneWidget,
    );

    final autoToggle = find.byKey(const ValueKey('auto-docent-toggle'));
    expect(
      find.descendant(of: autoToggle, matching: find.text('끔')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: autoToggle,
        matching: find.byIcon(Icons.auto_awesome),
      ),
      findsOneWidget,
    );
    // 모바일 비주얼 계약: 대형 중앙 컨트롤(74dp) 제거 — 44dp 타겟으로 축소.
    expect(
      tester.getSize(autoToggle).shortestSide,
      lessThanOrEqualTo(52),
    );
    final bottomDockRect = tester.getRect(
      find.byKey(const ValueKey('map-bottom-dock')),
    );
    final autoToggleRect = tester.getRect(autoToggle);
    final dockDocentPreview = find.byKey(const ValueKey('dock-docent-preview'));
    final dockDocentPreviewRect = tester.getRect(dockDocentPreview);
    expect(autoToggleRect.bottom, lessThan(bottomDockRect.top));
    expect(dockDocentPreview, findsOneWidget);
    expect(dockDocentPreviewRect.top, greaterThan(bottomDockRect.top));
    expect(find.byKey(const ValueKey('map-guidance-panel')), findsNothing);
    await tester.tap(autoToggle);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: autoToggle, matching: find.text('켬')),
      findsOneWidget,
    );
  });

  testWidgets('place photos render only from official image URLs', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) => FakeBackend(
          config,
          places: [
            _place(),
            _restaurantPlace(
              imageUrl: 'https://tong.visitkorea.or.kr/cms/resource/photo.jpg',
            ),
          ],
        ),
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('rail-place-image-hwaseong-haenggung')),
      findsNothing,
    );

    await tester.tap(find.text('맛집').first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('rail-place-image-haenggung-cafe-street')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('recommendation-rail-list')))
          .height,
      126,
    );
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey('map-rail-place-card-haenggung-cafe-street'),
            ),
          )
          .width,
      148,
    );
  });

  testWidgets('weather pill opens a forecast chart sheet', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend(
      const LalaAppConfig(baseUri: 'http://api.test'),
    );

    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (_) => backend,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();
    expect(backend.weatherRequests, 1);
    final weatherPillText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('weather-pill-hit-target')),
        matching: find.text('14°C · PM10 31 보통 · PM2.5 14 좋음'),
      ),
    );
    expect(weatherPillText.maxLines, 2);

    await tester.tap(find.byKey(const ValueKey('weather-pill-hit-target')));
    await tester.pumpAndSettle();

    expect(backend.weatherRequests, 2);
    expect(find.text('날씨'), findsOneWidget);
    expect(find.text('날씨 추이'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('weather-source-chip')),
        matching: find.text('실시간 날씨'),
      ),
      findsOneWidget,
    );
    expect(find.text('15시'), findsAtLeastNWidgets(1));
    expect(find.text('22°'), findsOneWidget);
    expect(find.text('미세먼지(PM10)'), findsOneWidget);
    expect(find.text('초미세먼지(PM2.5)'), findsOneWidget);
    expect(find.text('31㎍/m³ · 보통'), findsOneWidget);
    expect(find.text('14㎍/m³ · 좋음'), findsOneWidget);
  });

  testWidgets('unavailable weather is not shown as real conditions', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) =>
            FakeBackend(config, weather: _weather(source: 'unavailable')),
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('날씨 데이터 준비 중'), findsOneWidget);
    expect(find.textContaining('14°'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('weather-pill-hit-target')));
    await tester.pumpAndSettle();

    expect(find.text('날씨'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('weather-unavailable-card')),
      findsOneWidget,
    );
    expect(find.text('날씨 추이'), findsNothing);
    expect(find.text('PM10'), findsNothing);
    expect(find.textContaining('14°'), findsNothing);
  });

  testWidgets('food tour pill opens restaurant tour sheet', (tester) async {
    final backend = FakeBackend(
      const LalaAppConfig(baseUri: 'http://api.test'),
    );
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (_) => backend,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tour-pill-hit-target')), findsNothing);

    await tester.tap(find.text('맛집').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tour-pill-hit-target')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tour-pill-hit-target')));
    await tester.pumpAndSettle();

    expect(find.text('맛집 투어'), findsAtLeastNWidgets(1));
    expect(find.textContaining('가까운 맛집'), findsOneWidget);
    expect(find.text('행궁동 카페거리'), findsAtLeastNWidgets(1));
    expect(find.textContaining('소비 신호'), findsAtLeastNWidgets(1));
    expect(find.text('투어 도슨트 스크립트'), findsOneWidget);
    expect(find.textContaining('행궁동 카페거리에서 시작'), findsOneWidget);
    expect(find.text('도슨트 음성으로 듣기'), findsOneWidget);

    final audioButton = find.widgetWithText(FilledButton, '오디오 준비');
    await tester.ensureVisible(audioButton);
    await tester.pumpAndSettle();
    await tester.tap(audioButton);
    await tester.pumpAndSettle();

    expect(backend.audioRequests, hasLength(1));
    expect(backend.audioRequests.single, contains('행궁동 카페거리'));
    expect(find.text('투어 음성 준비됨'), findsOneWidget);
    expect(find.text('오디오 캐시 4바이트'), findsOneWidget);
    expect(find.textContaining('bytes 오디오'), findsNothing);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voice-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tour-pill-hit-target')));
    await tester.pumpAndSettle();

    expect(find.text('투어 음성 준비됨'), findsNothing);
    expect(find.text('오디오 캐시 4바이트'), findsNothing);
    expect(find.text('도슨트 음성으로 듣기'), findsOneWidget);
  });

  testWidgets('food tour tags open the selected restaurant detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tour-pill-hit-target')), findsNothing);

    await tester.tap(find.text('맛집').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tour-pill-hit-target')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('tour-tag-haenggung-cafe-street')),
    );
    await tester.pumpAndSettle();

    expect(find.text('장소 상세'), findsOneWidget);
    expect(find.text('행궁동 카페거리 도슨트'), findsAtLeastNWidgets(1));
  });

  testWidgets('weather intervention toast opens planner and can dismiss', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) => FakeBackend(config, shouldIntervene: true),
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('날씨가 바뀌었어요'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('intervention-toast-plan')));
    await tester.pumpAndSettle();
    expect(find.text('하루 일정'), findsAtLeastNWidgets(1));

    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('intervention-toast-close')));
    await tester.pumpAndSettle();
    expect(find.textContaining('날씨가 바뀌었어요'), findsNothing);
  });

  testWidgets(
    'weather intervention toast auto-dismisses after legacy timeout',
    (tester) async {
      await tester.pumpWidget(
        TestLalaApp(
          backendFactory: (config) =>
              FakeBackend(config, shouldIntervene: true),
          initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('날씨가 바뀌었어요'), findsOneWidget);

      await tester.pump(const Duration(seconds: 8));
      await tester.pump();

      expect(find.textContaining('날씨가 바뀌었어요'), findsNothing);
    },
  );

  testWidgets('planner sheet shows weather header and regenerates plan', (
    tester,
  ) async {
    final backend = FakeBackend(
      const LalaAppConfig(baseUri: 'http://api.test'),
    );

    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (_) => backend,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();
    expect(backend.dailyPlanRequests, 1);

    await tester.tap(find.byKey(const ValueKey('planner-pill-hit-target')));
    await tester.pumpAndSettle();

    expect(find.text('수원'), findsAtLeastNWidgets(1));
    expect(find.textContaining('14°C'), findsWidgets);
    expect(find.text('일정 재생성'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('planner-regenerate')));
    await tester.pumpAndSettle();
    expect(find.text('하루 일정 재생성'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '다시 생성'));
    await tester.pumpAndSettle();
    expect(backend.dailyPlanRequests, 2);
  });

  testWidgets('planner slot cards select their place detail', (tester) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-pill-hit-target')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('planner-slot-hwaseong-haenggung')),
    );
    await tester.pumpAndSettle();

    expect(find.text('장소 상세'), findsOneWidget);
    expect(find.text('화성행궁 도슨트'), findsAtLeastNWidgets(1));
  });

  testWidgets('auto docent on keeps the nearest place in map guidance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) => FakeBackend(
          config,
          places: [_place(), _restaurantPlace(distanceM: 80), _culturePlace()],
        ),
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('auto-docent-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('장소 상세'), findsNothing);
    expect(
      find.byKey(const ValueKey('kakao-map-fallback-center-37.2828-127.0101')),
      findsOneWidget,
    );
    expect(find.text('로컬 맥락'), findsNothing);
    expect(find.text('장소 연계 행사 1건'), findsNothing);
    expect(find.text('카드 소비 1,400만원'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('auto-docent-toggle')),
        matching: find.text('켬'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('auto docent ignores places outside the legacy trigger radius', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) => FakeBackend(
          config,
          places: [_place(), _restaurantPlace(distanceM: 120), _culturePlace()],
        ),
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('auto-docent-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('장소 상세'), findsNothing);
    expect(
      find.byKey(const ValueKey('kakao-map-fallback-center-37.2636-127.0286')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('kakao-map-marker-hwaseong-haenggung')),
        matching: find.byIcon(Icons.account_balance),
      ),
      findsOneWidget,
    );
    expect(find.text('화성행궁 도슨트'), findsAtLeastNWidgets(1));
    expect(find.text('행궁동 카페거리 도슨트'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('auto-docent-toggle')),
        matching: find.text('켬'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('auto docent re-evaluates the nearest place after refresh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var backendCreations = 0;
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) {
          backendCreations += 1;
          return FakeBackend(
            config,
            places: backendCreations <= 2
                ? [_place(), _restaurantPlace(distanceM: 120), _culturePlace()]
                : [_place(), _restaurantPlace(distanceM: 80), _culturePlace()],
          );
        },
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('auto-docent-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('kakao-map-fallback-center-37.2828-127.0101')),
      findsNothing,
    );
    expect(find.text('장소 상세'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('location-refresh')));
    await tester.pumpAndSettle();

    expect(backendCreations, 3);
    expect(find.text('장소 상세'), findsNothing);
    expect(
      find.byKey(const ValueKey('kakao-map-fallback-center-37.2828-127.0101')),
      findsOneWidget,
    );
  });

  testWidgets('auto docent keeps context during the legacy cooldown window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var backendCreations = 0;
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) {
          backendCreations += 1;
          return FakeBackend(
            config,
            places: backendCreations <= 2
                ? [_place(), _restaurantPlace(distanceM: 80), _culturePlace()]
                : [
                    _place(),
                    _restaurantPlace(distanceM: 80),
                    _culturePlace(distanceM: 70),
                  ],
          );
        },
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('auto-docent-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('kakao-map-fallback-center-37.2828-127.0101')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('weather-pill')));
    await tester.pumpAndSettle();

    expect(backendCreations, 3);
    expect(
      find.byKey(const ValueKey('kakao-map-fallback-center-37.2828-127.0101')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('kakao-map-fallback-center-37.2870-127.0110')),
      findsNothing,
    );
  });

  testWidgets('my location control returns to the map recommendation context', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('수원화성'));
    await tester.pumpAndSettle();

    expect(find.text('장소 상세'), findsOneWidget);
    expect(find.text('수원화성 도슨트'), findsAtLeastNWidgets(1));

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('장소 상세'), findsNothing);
    expect(find.text('수원화성 도슨트'), findsAtLeastNWidgets(1));

    await tester.tap(find.byKey(const ValueKey('location-refresh')));
    await tester.pumpAndSettle();

    expect(find.text('수원화성 도슨트'), findsNothing);
    expect(find.text('화성행궁 도슨트'), findsAtLeastNWidgets(1));
    expect(find.text('추천 장소 접기'), findsOneWidget);
  });

  testWidgets('recommendation rail collapses and place cards select detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('수원화성'), findsOneWidget);
    // 단일 선택 테두리: 내부 category-border 키는 제거됨(외부 카드 키로 선택 카드 확인).
    expect(
      find.byKey(const ValueKey('map-rail-place-card-hwaseong-haenggung')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('kakao-map-fallback-center-37.2636-127.0286')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('tour-stop-action-hwaseong-haenggung')),
    );
    await tester.pumpAndSettle();

    expect(find.text('장소 상세'), findsNothing);
    expect(find.text('화성행궁 도슨트'), findsOneWidget);

    await tester.tap(find.text('추천 장소 접기'));
    await tester.pumpAndSettle();

    expect(find.text('수원화성'), findsNothing);
    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
    expect(find.text('추천 장소 보기'), findsOneWidget);

    await tester.tap(find.text('추천 장소 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수원화성'));
    await tester.pumpAndSettle();

    expect(find.text('장소 상세'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('kakao-map-fallback-center-37.2870-127.0110')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('map-rail-place-card-suwon-hwaseong')),
      findsOneWidget,
    );
    expect(find.text('수원화성 도슨트'), findsAtLeastNWidgets(1));
    expect(find.text('화성행궁 도슨트'), findsNothing);

    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
    final selectedRailCard = find.byKey(
      const ValueKey('tour-stop-action-suwon-hwaseong'),
    );
    final selectedRailCardTopLeft = tester.getTopLeft(selectedRailCard);
    await tester.tapAt(selectedRailCardTopLeft + const Offset(24, 24));
    await tester.pumpAndSettle();

    expect(find.text('장소 상세'), findsNothing);
    expect(find.text('화성행궁 도슨트'), findsAtLeastNWidgets(1));
    expect(find.text('수원화성 도슨트'), findsNothing);
  });

  testWidgets(
    'default map level keeps nearby recommendation markers expanded',
    (tester) async {
      await tester.pumpWidget(
        TestLalaApp(
          backendFactory: (config) => FakeBackend(
            config,
            places: [
              _place(),
              _clusterRestaurant('cluster-food-a', '클러스터 맛집 A', 210),
              _clusterRestaurant('cluster-food-b', '클러스터 맛집 B', 260),
              _clusterRestaurant('cluster-food-c', '클러스터 맛집 C', 310),
            ],
          ),
          initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('kakao-map-marker-cluster-food-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('kakao-map-marker-cluster-food-b')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('kakao-map-marker-cluster-food-c')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('kakao-map-marker-cluster-restaurant:6710:22862'),
        ),
        findsNothing,
      );
      expect(find.text('화성행궁 도슨트'), findsOneWidget);
    },
  );

  testWidgets('location consent off surfaces the map permission overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('닫기').first);
    await tester.pumpAndSettle();

    expect(find.text('위치기반 추천이 꺼져 있어요'), findsOneWidget);
    expect(find.text('위치 동의 켜기'), findsOneWidget);
    expect(find.text('다시 확인'), findsOneWidget);

    await tester.tap(find.text('위치 동의 켜기'));
    await tester.pumpAndSettle();

    expect(find.text('설정'), findsOneWidget);
    expect(find.text('위치기반 정보 제공 동의'), findsOneWidget);
  });

  testWidgets('location consent retry restores map recommendations', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('닫기').first);
    await tester.pumpAndSettle();

    expect(find.text('위치기반 추천이 꺼져 있어요'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('location-consent-retry')));
    await tester.pumpAndSettle();

    expect(find.text('위치기반 추천이 꺼져 있어요'), findsNothing);
    expect(find.text('추천 장소 접기'), findsOneWidget);
    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
  });

  testWidgets('loads authenticated API panels with the reference contract', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
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
    expect(find.textContaining('조선 왕실'), findsAtLeastNWidgets(1));
  });

  testWidgets('surfaces fallback state when authenticated load fails', (
    tester,
  ) async {
    var backendCreations = 0;
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) {
          backendCreations += 1;
          return FakeBackend(
            config,
            failAuthenticatedLoad: backendCreations == 2,
          );
        },
        initialConfig: const LalaAppConfig(
          baseUri: 'http://api.test',
          bearerToken: 'test-token',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('추천 연결이 잠시 지연되고 있어요'), findsOneWidget);
    expect(find.textContaining('요청을 처리하지 못했습니다'), findsNothing);
    expect(
      find.text('UPSTREAM_UNAVAILABLE: Authenticated route failed.'),
      findsNothing,
    );
    expect(find.text('추천 연결을 다시 확인하고 있어요'), findsOneWidget);
    expect(find.textContaining('데모'), findsNothing);
    expect(find.text('화성행궁'), findsNothing);
    expect(find.text('히말라야정원'), findsNothing);
    expect(find.text('나혜석거리'), findsNothing);
    expect(find.textContaining('자동으로 다시 시도합니다'), findsOneWidget);
    expect(find.byKey(const ValueKey('map-error-retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('dock-error-retry')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('map-error-retry')));
    await tester.pumpAndSettle();

    expect(backendCreations, 3);
    expect(
      find.text('UPSTREAM_UNAVAILABLE: Authenticated route failed.'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('map-error-retry')), findsNothing);
    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
    expect(find.textContaining('조선 왕실'), findsAtLeastNWidgets(1));
  });

  testWidgets('english fallback errors hide internal API details', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) =>
            FakeBackend(config, failAuthenticatedLoad: true),
        initialConfig: const LalaAppConfig(
          baseUri: 'http://api.test',
          bearerToken: 'test-token',
          lang: 'en',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.textContaining('Recommendations are taking longer than expected'),
      findsOneWidget,
    );
    expect(find.textContaining('Unable to complete the request'), findsNothing);
    expect(find.textContaining('UPSTREAM_UNAVAILABLE'), findsNothing);
    expect(find.textContaining('Authenticated route failed'), findsNothing);
    expect(find.text('Checking recommendations again'), findsOneWidget);
  });

  testWidgets('refresh retries place loading even after live places exist', (
    tester,
  ) async {
    final createdBackends = <FakeBackend>[];
    var backendCreations = 0;

    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) {
          backendCreations += 1;
          final backend = backendCreations == 3
              ? FailNTimesThenSucceedPlacesBackend(
                  config,
                  failuresBeforeSuccess: 1,
                )
              : FakeBackend(config);
          createdBackends.add(backend);
          return backend;
        },
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));

    await tester.tap(find.byKey(const ValueKey('location-refresh')));
    await tester.pumpAndSettle();

    expect(backendCreations, 3);
    expect(createdBackends.last, isA<FailNTimesThenSucceedPlacesBackend>());
    expect(
      (createdBackends.last as FailNTimesThenSucceedPlacesBackend)
          .getPlacesAttempts,
      2,
    );
    expect(find.textContaining('추천 장소를 불러오지 못했어요'), findsNothing);
    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
  });

  testWidgets('recommendation failures auto-recover in the background', (
    tester,
  ) async {
    var backendCreations = 0;

    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) {
          backendCreations += 1;
          if (backendCreations == 2) {
            return FailNTimesThenSucceedPlacesBackend(
              config,
              failuresBeforeSuccess: 2,
            );
          }
          return FakeBackend(config);
        },
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        recommendationRecoveryDelays: const <Duration>[
          Duration(milliseconds: 50),
        ],
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('화성행궁'), findsNothing);

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(backendCreations, 3);
    expect(find.textContaining('추천 연결이 잠시 지연되고 있어요'), findsNothing);
    expect(find.textContaining('추천 장소를 불러오지 못했어요'), findsNothing);
    expect(find.byKey(const ValueKey('map-error-retry')), findsNothing);
    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
  });

  testWidgets('settings hides developer connection controls', (tester) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) => FakeBackend(config),
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();

    expect(find.text('개인정보 동의 안내'), findsOneWidget);
    expect(find.text('위치기반 정보 제공 동의'), findsOneWidget);
    expect(find.text('언어'), findsOneWidget);
    expect(find.text('글꼴 크기'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('앱 정보'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('앱 정보'), findsOneWidget);
    expect(find.text('개발 연결'), findsNothing);
    expect(find.text('기본 주소'), findsNothing);
    expect(find.text('마이그레이션 키'), findsNothing);
    expect(find.text('카카오 지도 키'), findsNothing);

    await tester.tap(find.text('자세히 보기'));
    await tester.pumpAndSettle();

    expect(find.text('위치 기반 추천'), findsOneWidget);
    expect(find.text('공식 데이터 우선'), findsOneWidget);
    expect(find.textContaining('공식 기관 데이터와 공개 데이터'), findsOneWidget);
    expect(find.textContaining('공식 API'), findsNothing);
    expect(find.textContaining('스냅샷'), findsNothing);
    expect(find.textContaining('개발'), findsNothing);
  });

  testWidgets(
    'signed-out account action signs in through the injected gateway',
    (tester) async {
      final gateway = WidgetTestAuthGateway(
        accessTokenValue: 'fresh-access-token',
      );
      final configs = <LalaAppConfig>[];
      await tester.pumpWidget(
        TestLalaApp(
          backendFactory: (config) {
            configs.add(config);
            return FakeBackend(config);
          },
          initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
          authControllerFactory: (_) =>
              _widgetTestAuthController(gateway: gateway),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('settings-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('account-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('account-sign-in')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('account-sign-in')));
      await tester.pumpAndSettle();

      expect(gateway.signInCalls, 1);
      expect(find.text('로그인됨'), findsOneWidget);
      expect(find.textContaining('account-123'), findsNothing);
      expect(find.textContaining('계정 ID'), findsNothing);
      expect(configs.last.accessTokenProvider, isNotNull);
      expect(await configs.last.accessTokenProvider!(), 'fresh-access-token');
    },
  );

  testWidgets('signed-in account action signs out without closing the map', (
    tester,
  ) async {
    final gateway = WidgetTestAuthGateway(authenticated: true);
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        authControllerFactory: (_) =>
            _widgetTestAuthController(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('account-sign-out')));
    await tester.pumpAndSettle();

    expect(gateway.signOutCalls, 1);
    expect(find.byKey(const ValueKey('account-sign-in')), findsOneWidget);
    await tester.tap(find.byTooltip('닫기').first);
    await tester.pumpAndSettle();
    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
  });

  testWidgets('disabled auth shows unavailable status without login action', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        authControllerFactory: (_) => _widgetTestAuthController(enabled: false),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('account-panel')), findsOneWidget);
    expect(find.text('계정 로그인을 사용할 수 없어요'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-sign-in')), findsNothing);
  });

  testWidgets('account deletion requires confirmation and supports cancel', (
    tester,
  ) async {
    final accountApi = WidgetTestAccountApi();
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        authControllerFactory: (_) => _widgetTestAuthController(
          gateway: WidgetTestAuthGateway(authenticated: true),
          accountApi: accountApi,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('account-delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account-delete-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('account-delete-cancel')));
    await tester.pumpAndSettle();
    expect(accountApi.deleteConfirmations, isEmpty);

    await tester.tap(find.byKey(const ValueKey('account-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-delete-confirm')));
    await tester.pumpAndSettle();

    expect(accountApi.deleteConfirmations, ['delete-my-account']);
    expect(find.byKey(const ValueKey('account-sign-in')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-delete')), findsNothing);
  });

  testWidgets('account failures show localized safe copy without raw details', (
    tester,
  ) async {
    final gateway = WidgetTestAuthGateway(
      signInError: StateError('provider subject and secret token'),
    );
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        authControllerFactory: (_) =>
            _widgetTestAuthController(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-sign-in')));
    await tester.pumpAndSettle();

    expect(find.text('계정 요청을 완료하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    expect(find.textContaining('provider subject'), findsNothing);
    expect(find.byKey(const ValueKey('account-sign-in')), findsOneWidget);
  });

  testWidgets('disabled auth preserves guest map startup', (tester) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        authControllerFactory: (_) => _widgetTestAuthController(enabled: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
    expect(find.byKey(const ValueKey('settings-button')), findsOneWidget);
  });

  testWidgets('desktop map chrome keeps app controls at usable width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    final dockWidth = tester
        .getSize(find.byKey(const ValueKey('map-bottom-dock')))
        .width;
    final railWidth = tester
        .getSize(find.byKey(const ValueKey('recommendation-rail-list')))
        .width;
    final utilityWidth = tester
        .getSize(find.byKey(const ValueKey('map-utility-control-row')))
        .width;

    expect(dockWidth, lessThanOrEqualTo(760));
    expect(railWidth, lessThanOrEqualTo(780));
    expect(utilityWidth, lessThanOrEqualTo(760));
  });

  testWidgets(
    'mobile map layout keeps the rail, control stack and dock non-overlapping',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        TestLalaApp(
          backendFactory: FakeBackend.new,
          initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        ),
      );
      await tester.pumpAndSettle();

      // remediation C1: 5개 칩 중 문화 와 설정 아이콘이 393dp 에서 잘림 없이 보인다.
      expect(find.text('문화'), findsOneWidget);
      expect(find.text('전체'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-button')), findsOneWidget);

      final dockRect = tester.getRect(
        find.byKey(const ValueKey('map-bottom-dock')),
      );
      // 컨트롤 스택(음성 토글 = 최상단)은 도크 핸들 위에 위치(겹치지 않음).
      final voiceRect = tester.getRect(find.byKey(const ValueKey('voice-toggle')));
      expect(voiceRect.bottom, lessThanOrEqualTo(dockRect.top));

      // 추천 레일은 컨트롤 스택보다 위쪽 밴드에 있다(세로 영역이 겹치지 않음).
      final railRect = tester.getRect(
        find.byKey(const ValueKey('recommendation-rail-list')),
      );
      expect(railRect.bottom, lessThan(voiceRect.top));

      // 카테고리 행(문화 칩)은 레일 위에 위치(겹치지 않음).
      final cultureChip = tester.getRect(find.text('문화'));
      expect(cultureChip.bottom, lessThanOrEqualTo(railRect.top));
      // 문화 라벨이 화면 폭 안에 있다(잘림 아님).
      expect(cultureChip.right, lessThan(393));
    },
  );

  testWidgets('bottom navigation shows contracted Korean labels', (tester) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    // 계약: 하단 네비 한국어 라벨은 검색/지도/일정. 플랜 제거.
    expect(find.text('검색'), findsOneWidget);
    expect(find.text('지도'), findsOneWidget);
    expect(find.text('일정'), findsOneWidget);
    expect(find.text('플랜'), findsNothing);
  });

  testWidgets('place detail save control toggles local saved state', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '상세'));
    await tester.pumpAndSettle();

    expect(find.text('장소 상세'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byTooltip('저장'), findsOneWidget);

    await tester.tap(find.byTooltip('저장'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byTooltip('저장됨'), findsOneWidget);
  });

  testWidgets('settings language switch updates map filter labels', (
    tester,
  ) async {
    final configs = <LalaAppConfig>[];
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) {
          configs.add(config);
          return FakeBackend(config);
        },
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('영어'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Attractions'), findsOneWidget);
    expect(find.text('Daily Plan'), findsOneWidget);
    expect(find.text('전체'), findsNothing);
    expect(find.text('하루 일정'), findsNothing);
    expect(configs.last.lang, 'en');
  });

  testWidgets('settings language labels follow the selected language only', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();

    expect(find.text('한국어'), findsOneWidget);
    expect(find.text('영어'), findsOneWidget);
    expect(find.text('Korean'), findsNothing);
    expect(find.text('English'), findsNothing);
    expect(_visibleMixedLanguageTexts(tester), isEmpty);

    await tester.tap(find.text('영어'));
    await tester.pumpAndSettle();

    expect(find.text('Korean'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('한국어'), findsNothing);
    expect(find.text('영어'), findsNothing);
    expect(_visibleMixedLanguageTexts(tester), isEmpty);
  });

  testWidgets('english language setting does not mix Korean place copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(
          baseUri: 'http://api.test',
          lang: 'en',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hwaseong Haenggung'), findsAtLeastNWidgets(1));
    expect(find.text('Daily Plan'), findsOneWidget);
    expect(
      find.text('Loading the docent script. Please check again shortly.'),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('Listen'), findsNothing);
    expect(find.textContaining('화성행궁'), findsNothing);
    expect(find.textContaining('경기도'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Details'));
    await tester.pumpAndSettle();

    expect(find.text('Details'), findsWidgets);
    expect(find.byKey(const ValueKey('detail-place-hero-image')), findsNothing);
    expect(find.text('Suwon'), findsAtLeastNWidgets(1));
    expect(find.text('Local context'), findsOneWidget);
    expect(find.text('1 linked events'), findsOneWidget);
    expect(find.text('Card spend KRW 14,000,000'), findsNothing);

    final showSignalsButton = find.widgetWithText(
      OutlinedButton,
      'Show signals',
    );
    await tester.ensureVisible(showSignalsButton);
    await tester.pumpAndSettle();
    await tester.tap(showSignalsButton);
    await tester.pumpAndSettle();

    expect(find.text('Card spend KRW 14,000,000'), findsOneWidget);
    expect(find.text('Local score'), findsOneWidget);
    expect(find.text('LALA recommendation score'), findsOneWidget);
    expect(find.textContaining('화성행궁'), findsNothing);
    expect(find.textContaining('경기도'), findsNothing);
    expect(find.textContaining('snapshot'), findsNothing);
  });

  testWidgets('english food tour sheet keeps tour copy localized', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(
          baseUri: 'http://api.test',
          lang: 'en',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restaurants').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tour-pill-hit-target')));
    await tester.pumpAndSettle();

    expect(find.text('Food Tour'), findsAtLeastNWidgets(1));
    expect(find.textContaining('nearby food stops'), findsOneWidget);
    expect(find.textContaining('Official data'), findsWidgets);
    expect(find.text('Tour docent script'), findsOneWidget);
    expect(find.text('Listen as a docent audio guide'), findsOneWidget);
    expect(find.textContaining('맛집'), findsNothing);
    expect(find.textContaining('도슨트'), findsNothing);
    expect(_visibleMixedLanguageTexts(tester), isEmpty);
  });

  testWidgets(
    'event detail shows legacy metadata without opening score signals',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        TestLalaApp(
          backendFactory: (config) =>
              FakeBackend(config, places: [_eventPlace()]),
          initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        ),
      );
      await tester.pumpAndSettle();

      // remediation C2: photo-forward 레일 카드는 이름 오버레이만(행사 상태 라벨은 상세에서).
      expect(find.text('화성행궁 야간 산책'), findsWidgets);

      await tester.tap(find.widgetWithText(TextButton, '상세'));
      await tester.pumpAndSettle();

      expect(find.text('행사 정보'), findsOneWidget);
      expect(find.text('진행 중'), findsOneWidget);
      expect(find.text('2026년 06월 01일 ~ 2026년 08월 31일'), findsOneWidget);
      expect(find.text('행사 상세 보기'), findsOneWidget);
      expect(find.text('로컬 점수'), findsNothing);
      expect(find.text('내국인 소비'), findsNothing);

      final evidenceButton = find.widgetWithText(OutlinedButton, '점수/근거 보기');
      await tester.scrollUntilVisible(
        evidenceButton,
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(evidenceButton);
      await tester.pumpAndSettle();

      expect(find.text('실시간 추천'), findsWidgets);
      expect(find.textContaining('스냅샷'), findsNothing);
    },
  );

  testWidgets('snapshot fallback is not presented as official live data', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: SnapshotFallbackBackend.new,
        initialConfig: const LalaAppConfig(
          baseUri: 'http://api.test',
          lang: 'en',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Limited offline data'), findsWidgets);
    expect(find.textContaining('Official data'), findsNothing);
    expect(find.textContaining('snapshot'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Details'));
    await tester.pumpAndSettle();
    final showSignalsButton = find.widgetWithText(
      OutlinedButton,
      'Show signals',
    );
    await tester.scrollUntilVisible(
      showSignalsButton,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(showSignalsButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('Limited offline data'), findsWidgets);
    expect(find.textContaining('Official data'), findsNothing);
    expect(find.textContaining('snapshot'), findsNothing);
  });

  testWidgets('event detail follows English language setting', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) =>
            FakeBackend(config, places: [_eventPlace()]),
        initialConfig: const LalaAppConfig(
          baseUri: 'http://api.test',
          lang: 'en',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Details'));
    await tester.pumpAndSettle();

    expect(find.text('Event info'), findsOneWidget);
    expect(find.text('Ongoing'), findsOneWidget);
    expect(find.text('Jun 1, 2026 ~ Aug 31, 2026'), findsOneWidget);
    expect(find.text('Open event details'), findsOneWidget);
    expect(find.textContaining('행사'), findsNothing);

    final evidenceButton = find.widgetWithText(OutlinedButton, 'Show signals');
    await tester.scrollUntilVisible(
      evidenceButton,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(evidenceButton);
    await tester.pumpAndSettle();

    expect(find.text('Live recommendations'), findsWidgets);
    expect(find.textContaining('snapshot'), findsNothing);
  });

  testWidgets(
    'english mode uses neutral copy when English place data is absent',
    (tester) async {
      await tester.pumpWidget(
        TestLalaApp(
          backendFactory: (config) =>
              FakeBackend(config, places: [_koreanOnlyPlace()]),
          initialConfig: const LalaAppConfig(
            baseUri: 'http://api.test',
            lang: 'en',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Local place'), findsAtLeastNWidgets(1));
      expect(find.textContaining('호반아트리움'), findsNothing);
      expect(find.textContaining('경기도'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Details'));
      await tester.pumpAndSettle();

      expect(find.text('Nearby area'), findsAtLeastNWidgets(1));
      expect(find.textContaining('호반아트리움'), findsNothing);
      expect(find.textContaining('경기도'), findsNothing);
    },
  );

  testWidgets(
    'korean mode uses neutral copy when Korean place data is absent',
    (tester) async {
      await tester.pumpWidget(
        TestLalaApp(
          backendFactory: (config) =>
              FakeBackend(config, places: [_englishOnlyPlace()]),
          initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('이 장소'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Hoam Art Museum'), findsNothing);
      expect(find.textContaining('Everland-ro'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, '상세'));
      await tester.pumpAndSettle();

      expect(find.text('주변 지역'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Hoam Art Museum'), findsNothing);
      expect(find.textContaining('Everland-ro'), findsNothing);
    },
  );

  testWidgets('selected language removes bilingual place text', (tester) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (config) =>
            FakeBackend(config, places: [_bilingualPlace()]),
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Hwaseong'), findsNothing);
    expect(find.textContaining('Suwon-si'), findsNothing);
    expect(_visibleMixedLanguageTexts(tester), isEmpty);

    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('영어'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();

    expect(find.text('Hwaseong Haenggung'), findsAtLeastNWidgets(1));
    expect(find.textContaining('화성행궁'), findsNothing);
    expect(find.textContaining('경기도'), findsNothing);
    expect(find.textContaining('Hwaseong Haenggung / 화성행궁'), findsNothing);
    expect(find.textContaining('화성행궁 / Hwaseong Haenggung'), findsNothing);
    expect(_visibleMixedLanguageTexts(tester), isEmpty);
  });

  testWidgets('selected language removes bilingual intervention copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: BilingualInterventionBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Weather'), findsNothing);
    expect(find.textContaining('Keep'), findsNothing);
    expect(find.textContaining('Detailed'), findsNothing);
    expect(find.textContaining('날씨가 좋아요'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Hwaseong Haenggung connects'), findsNothing);
    expect(find.textContaining('화성행궁은'), findsAtLeastNWidgets(1));

    final audioButton = find.widgetWithText(FilledButton, '정보 더 듣기');
    await tester.ensureVisible(audioButton);
    await tester.pumpAndSettle();
    await tester.tap(audioButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('상세 도슨트입니다'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Detailed'), findsNothing);
    expect(find.textContaining('bytes'), findsNothing);
    expect(_visibleMixedLanguageTexts(tester), isEmpty);

    await tester.tap(find.byKey(const ValueKey('planner-pill-hit-target')));
    await tester.pumpAndSettle();
    expect(find.textContaining('화성행궁 산책'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Hwaseong walk'), findsNothing);
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('영어'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();

    expect(find.textContaining('Weather is good'), findsAtLeastNWidgets(1));
    expect(find.textContaining('PM10 31 Normal'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Keep walking'), findsAtLeastNWidgets(1));
    expect(find.textContaining('날씨가 좋아요'), findsNothing);
    expect(
      find.textContaining('Hwaseong Haenggung connects'),
      findsAtLeastNWidgets(1),
    );
    expect(find.textContaining('화성행궁은'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('planner-pill-hit-target')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hwaseong walk'), findsAtLeastNWidgets(1));
    expect(find.textContaining('화성행궁 산책'), findsNothing);
    expect(_visibleMixedLanguageTexts(tester), isEmpty);
  });

  testWidgets('placeholder docent scripts are not shown as real guidance', (
    tester,
  ) async {
    final backend = PlaceholderDocentBackend(
      const LalaAppConfig(baseUri: 'http://api.test'),
    );
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (_) => backend,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    expect(backend.docentScriptRequests, ['brief:hwaseong-haenggung']);
    expect(find.textContaining('도슨트 스크립트를 불러오는 중입니다'), findsAtLeastNWidgets(1));
    expect(find.textContaining('migration skeleton'), findsNothing);
    expect(find.textContaining('공식 관광·문화 데이터'), findsNothing);
    expect(find.textContaining('로컬 코스입니다'), findsNothing);
    expect(find.widgetWithText(FilledButton, '정보 더 듣기'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('영어'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Loading the docent script'),
      findsAtLeastNWidgets(1),
    );
    expect(find.textContaining('connects official tourism'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Listen'), findsNothing);
  });

  testWidgets('localized API errors follow the selected language only', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: BilingualLoadFailureBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('추천 연결이 잠시 지연되고 있어요'), findsOneWidget);
    expect(find.textContaining('Places failed'), findsNothing);
    expect(_visibleMixedLanguageTexts(tester), isEmpty);

    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('영어'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Recommendations are taking longer than expected'),
      findsOneWidget,
    );
    expect(find.textContaining('추천 연결이 잠시 지연되고 있어요'), findsNothing);
    expect(_visibleMixedLanguageTexts(tester), isEmpty);
  });

  testWidgets('surfaces OAuth JWT auth mode separately from static bearer', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
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

  testWidgets('fetches detail docent audio once after explicit tap', (
    tester,
  ) async {
    final backend = FakeBackend(
      const LalaAppConfig(
        baseUri: 'http://api.test',
        bearerToken: 'test-token',
      ),
    );

    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (_) => backend,
        initialConfig: const LalaAppConfig(
          baseUri: 'http://api.test',
          bearerToken: 'test-token',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(backend.docentScriptRequests, ['brief:hwaseong-haenggung']);
    expect(backend.audioRequests, isEmpty);
    expect(find.text('정보 더 듣기'), findsOneWidget);

    final audioButton = find.widgetWithText(FilledButton, '정보 더 듣기');
    await tester.ensureVisible(audioButton);
    await tester.pumpAndSettle();
    await tester.tap(audioButton);
    await tester.pumpAndSettle();

    expect(backend.docentScriptRequests, [
      'brief:hwaseong-haenggung',
      'detail:hwaseong-haenggung',
    ]);
    expect(backend.audioRequests, [
      '화성행궁 상세 도슨트입니다. 행궁동 골목, 수원화성 성곽, 주변 로컬 상권을 이어서 천천히 걸어보세요.',
    ]);
    expect(find.text('4바이트'), findsOneWidget);
    expect(find.text('4 bytes'), findsNothing);
    expect(find.textContaining('상세 도슨트입니다'), findsAtLeastNWidgets(1));
    expect(find.widgetWithText(FilledButton, '정보 더 듣기'), findsNothing);
  });

  testWidgets('speech disabled readiness hides docent audio controls', (
    tester,
  ) async {
    final backend = FakeBackend(
      const LalaAppConfig(baseUri: 'http://api.test'),
      liveSpeech: false,
    );

    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (_) => backend,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('조선 왕실'), findsAtLeastNWidgets(1));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('voice-toggle')),
        matching: find.text('끔'),
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, '정보 더 듣기'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('voice-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('voice-toggle')),
        matching: find.text('끔'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('맛집').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tour-pill-hit-target')));
    await tester.pumpAndSettle();

    expect(find.text('투어 도슨트 스크립트'), findsOneWidget);
    expect(find.text('도슨트 음성으로 듣기'), findsNothing);
    expect(find.widgetWithText(FilledButton, '오디오 준비'), findsNothing);
    expect(backend.audioRequests, isEmpty);
  });

  testWidgets('auxiliary plan and docent failures do not cover the map', (
    tester,
  ) async {
    final backend = FakeBackend(
      const LalaAppConfig(baseUri: 'http://api.test'),
      failDailyPlanLoad: true,
      failDocentScriptLoad: true,
    );

    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (_) => backend,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
    expect(find.text('요청을 처리하지 못했습니다.'), findsNothing);
    expect(
      find.text('요청을 처리하지 못했습니다. Unable to complete the request.'),
      findsNothing,
    );
    expect(backend.dailyPlanRequests, 1);
    expect(backend.docentScriptRequests, ['brief:hwaseong-haenggung']);
  });

  testWidgets('weather and intervention failures do not cover the map', (
    tester,
  ) async {
    final backend = FakeBackend(
      const LalaAppConfig(baseUri: 'http://api.test'),
      failWeatherLoad: true,
      failInterventionLoad: true,
    );

    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: (_) => backend,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
    expect(find.textContaining('요청을 처리하지 못했습니다'), findsNothing);
    expect(find.textContaining('추천 장소를 불러오지 못했어요'), findsNothing);
    expect(find.text('날씨 데이터 준비 중'), findsAtLeastNWidgets(1));
    expect(backend.weatherRequests, 1);
    expect(backend.interventionRequestConfigs, hasLength(1));
  });

  // --- ONMU P2: 온보딩 플로우 ---

  testWidgets(
    'onboarding redirects to splash when not completed and blocks the main shell',
    (tester) async {
      await tester.pumpWidget(
        TestLalaApp(
          backendFactory: FakeBackend.new,
          initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
          onboardingCompleted: false,
        ),
      );
      await tester.pump();

      // 메인 라우트가 스플래시로 차단된다. 메인 지도 콘텐츠는 보이지 않는다.
      expect(find.text('당신의 수원을 안내합니다'), findsOneWidget);
      expect(find.text('화성행궁'), findsNothing);

      // 스플래시는 아직 온보딩을 완료하지 않았다.
      expect(OnboardingState.isCompleted, isFalse);
    },
  );

  testWidgets('onboarding splash auto-advances to the tourist type start page', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        onboardingCompleted: false,
      ),
    );
    await tester.pump();

    expect(find.text('당신의 수원을 안내합니다'), findsOneWidget);

    // 2초 후 자동으로 start 단계로 이동한다.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('어떤 여행을\n계획 중인가요?'), findsOneWidget);
    expect(find.text('국내 여행'), findsOneWidget);
    expect(find.text('해외 방문'), findsOneWidget);
  });

  testWidgets(
    'onboarding foreign tourist defaults to english and reaches the map on skip',
    (tester) async {
      final locationProvider = FakeLocationProvider(
        const LalaLocationResult.found(
          LalaLocation(lat: 37.5665, lng: 126.9780),
        ),
      );
      await tester.pumpWidget(
        TestLalaApp(
          backendFactory: FakeBackend.new,
          initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
          locationProvider: locationProvider,
          onboardingCompleted: false,
        ),
      );
      await tester.pump();
      // 스플래시 건너뛰기.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // S1(한국어): 해외 방문 선택 → 선택 상태만 갱신(언어/이동 없음).
      await tester.tap(find.text('해외 방문'));
      await tester.pumpAndSettle();
      // "다음" 으로 유형+기본 언어(en) 기록 후 S2 로 이동.
      await tester.tap(find.widgetWithText(FilledButton, '다음'));
      await tester.pumpAndSettle();
      expect(OnboardingState.language, 'en');

      // 언어 단계(English): English 가 pre-select, Next 로 위치 단계로.
      expect(find.text('English'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Next'),
      );
      await tester.pumpAndSettle();

      // 위치 단계: "Not now" 스킵 → 온보딩 완료 → 메인 쉘(지도) 진입.
      expect(find.text('Use location'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(OnboardingState.isCompleted, isTrue);
      expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets('onboarding local tourist stays korean on location skip', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestLalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        onboardingCompleted: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // S1: 국내 여행 선택(기본 언어 ko) → 다음 → S2.
    await tester.tap(find.text('국내 여행'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '다음'));
    await tester.pumpAndSettle();
    expect(OnboardingState.language, 'ko');

    // S2(한국어): 다음 → S3.
    await tester.tap(find.widgetWithText(FilledButton, '다음'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('나중에 하기'));
    await tester.pumpAndSettle();

    expect(OnboardingState.isCompleted, isTrue);
    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
  });

  testWidgets(
    'onboarding location denial offers manual area selection then completes',
    (tester) async {
      final locationProvider = FakeLocationProvider(
        const LalaLocationResult.denied(),
      );
      await tester.pumpWidget(
        TestLalaApp(
          backendFactory: FakeBackend.new,
          initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
          locationProvider: locationProvider,
          onboardingCompleted: false,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // S1 국내 여행 → S2 다음 → S3 위치 단계.
      await tester.tap(find.text('국내 여행'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '다음'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '다음'));
      await tester.pumpAndSettle();

      // 현재 위치 사용 요청 → 거부. 수동 선택은 항상 노출되어 그대로 사용 가능.
      await tester.tap(find.text('현재 위치 사용'));
      await tester.pumpAndSettle();
      expect(find.text('지역 직접 선택'), findsOneWidget);
      expect(locationProvider.requests, 1);

      // 수동 지역 선택 시트에서 서울 중구를 선택하면 온보딩이 완료된다.
      await tester.tap(find.text('지역 직접 선택'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('manual-location-option-seoul-jung')),
      );
      await tester.pumpAndSettle();

      expect(OnboardingState.isCompleted, isTrue);
      expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
    },
  );
}

class TestLalaApp extends StatelessWidget {
  const TestLalaApp({
    required this.backendFactory,
    required this.initialConfig,
    this.locationProvider,
    this.requireLocationStartConfirmation = false,
    this.recommendationRecoveryDelays,
    this.authControllerFactory,
    this.onboardingCompleted = true,
    super.key,
  });

  final LalaBackendFactory backendFactory;
  final LalaAppConfig initialConfig;
  final LalaLocationProvider? locationProvider;
  final bool requireLocationStartConfirmation;
  final List<Duration>? recommendationRecoveryDelays;
  final LalaAuthControllerFactory? authControllerFactory;

  /// ONMU P2: 기존 라이브 지도 테스트는 온보딩이 완료된 상태를 가정한다.
  /// 온보딩 플로우 자체를 검증할 때만 false 로 넘겨 reset 한다.
  final bool onboardingCompleted;

  @override
  Widget build(BuildContext context) {
    if (onboardingCompleted) {
      OnboardingState.markCompleted();
    } else {
      OnboardingState.reset();
    }
    return LalaApp(
      backendFactory: backendFactory,
      initialConfig: initialConfig.copyWith(
        requireLocationStartConfirmation: requireLocationStartConfirmation,
      ),
      recommendationRecoveryDelays:
          recommendationRecoveryDelays ??
          const <Duration>[
            Duration(seconds: 8),
            Duration(seconds: 16),
            Duration(seconds: 30),
          ],
      locationProvider:
          locationProvider ??
          FakeLocationProvider(
            LalaLocationResult.found(
              LalaLocation(lat: initialConfig.lat, lng: initialConfig.lng),
            ),
          ),
      authControllerFactory: authControllerFactory ?? createLalaAuthController,
    );
  }
}

LalaAuthController _widgetTestAuthController({
  bool enabled = true,
  WidgetTestAuthGateway? gateway,
  WidgetTestAccountApi? accountApi,
}) {
  return LalaAuthController(
    config: LalaAuthConfig(
      endpoint: enabled ? 'https://auth.example.com' : '',
      appId: enabled ? 'public-client-id' : '',
      apiAudience: enabled ? 'https://api.example.com' : '',
      redirectUri: 'cloud.lalanext.lala://callback',
    ),
    gateway: gateway ?? WidgetTestAuthGateway(),
    accountApi: accountApi ?? WidgetTestAccountApi(),
  );
}

class WidgetTestAuthGateway implements LalaAuthGateway {
  WidgetTestAuthGateway({
    this.authenticated = false,
    this.accessTokenValue,
    this.signInError,
  });

  bool authenticated;
  final String? accessTokenValue;
  final Object? signInError;
  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  Future<bool> get isAuthenticated async => authenticated;

  @override
  Future<void> signIn() async {
    signInCalls += 1;
    if (signInError != null) {
      throw signInError!;
    }
    authenticated = true;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    authenticated = false;
  }

  @override
  Future<String?> accessToken(String resource) async => accessTokenValue;
}

class WidgetTestAccountApi implements LalaAccountApi {
  final List<String> deleteConfirmations = [];

  @override
  Future<LalaMe> getMe() async => const LalaMe(
    userId: 'account-123',
    createdAt: '2026-07-10T00:00:00Z',
    authenticated: true,
  );

  @override
  Future<void> deleteMe({required String confirmation}) async {
    deleteConfirmations.add(confirmation);
  }
}

class FakeLocationProvider implements LalaLocationProvider {
  FakeLocationProvider(this.result);

  final LalaLocationResult result;
  int requests = 0;

  @override
  Future<LalaLocationResult> requestCurrentLocation() async {
    requests += 1;
    return result;
  }
}

class PendingLocationProvider implements LalaLocationProvider {
  final Completer<LalaLocationResult> _completer =
      Completer<LalaLocationResult>();
  int requests = 0;

  @override
  Future<LalaLocationResult> requestCurrentLocation() {
    requests += 1;
    return _completer.future;
  }

  void complete(LalaLocationResult result) {
    _completer.complete(result);
  }
}

class FakeBackend implements LalaBackend {
  FakeBackend(
    this.config, {
    this.failAuthenticatedLoad = false,
    this.failReadinessLoad = false,
    this.failWeatherLoad = false,
    this.failInterventionLoad = false,
    this.failDailyPlanLoad = false,
    this.failDocentScriptLoad = false,
    this.shouldIntervene = false,
    this.liveSpeech = true,
    this.places,
    this.weather,
    this.healthDelay = Duration.zero,
    this.readinessDelay = Duration.zero,
    this.placesDelay = Duration.zero,
    this.weatherDelay = Duration.zero,
    this.interventionDelay = Duration.zero,
    this.dailyPlanDelay = Duration.zero,
    this.docentScriptDelay = Duration.zero,
  });

  final LalaAppConfig config;
  final bool failAuthenticatedLoad;
  final bool failReadinessLoad;
  final bool failWeatherLoad;
  final bool failInterventionLoad;
  final bool failDailyPlanLoad;
  final bool failDocentScriptLoad;
  final bool shouldIntervene;
  final bool liveSpeech;
  final List<LalaPlace>? places;
  final LalaWeather? weather;
  final Duration healthDelay;
  final Duration readinessDelay;
  final Duration placesDelay;
  final Duration weatherDelay;
  final Duration interventionDelay;
  final Duration dailyPlanDelay;
  final Duration docentScriptDelay;
  final List<String> docentScriptRequests = <String>[];
  final List<String> audioRequests = <String>[];
  final List<LalaAppConfig> placesRequestConfigs = <LalaAppConfig>[];
  final List<LalaAppConfig> weatherRequestConfigs = <LalaAppConfig>[];
  final List<LalaAppConfig> interventionRequestConfigs = <LalaAppConfig>[];
  final List<LalaAppConfig> dailyPlanRequestConfigs = <LalaAppConfig>[];
  int weatherRequests = 0;
  int dailyPlanRequests = 0;

  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getHealth() async {
    await _delayIfNeeded(healthDelay);
    return _envelope(<String, dynamic>{
      'status': 'ok',
      'service': 'lala-next-api',
      'version': 'test',
    });
  }

  @override
  Future<LalaEnvelope<LalaReadiness>> getReadiness() async {
    await _delayIfNeeded(readinessDelay);
    if (failReadinessLoad) {
      throw const LalaApiException(
        code: 'UPSTREAM_TIMEOUT',
        message: 'Readiness route timed out.',
        statusCode: 504,
        retryable: true,
        requestId: 'slow-readyz',
      );
    }
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
          'db': 'configured',
          'postgis': 'configured',
          'static_snapshot_fallback': 'disabled',
          'live_speech': liveSpeech ? 'enabled' : 'disabled',
          'worker_contracts': 'configured',
        },
        mode: LalaRuntimeMode(
          overall: 'ok',
          data: 'db-backed',
          ai: 'disabled',
          speech: liveSpeech ? 'live-azure' : 'disabled',
          worker: 'dry-run',
        ),
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async {
    placesRequestConfigs.add(config);
    await _delayIfNeeded(placesDelay);
    if (failAuthenticatedLoad) {
      throw const LalaApiException(
        code: 'UPSTREAM_UNAVAILABLE',
        message: 'Authenticated route failed.',
        statusCode: 503,
        retryable: true,
        requestId: 'failed-auth-route',
      );
    }
    final responsePlaces =
        places ?? [_place(), _culturePlace(), _restaurantPlace()];
    return _envelope(
      LalaPlacesResponse(
        count: responsePlaces.length,
        places: responsePlaces,
        query: LalaPlacesQuery(
          lat: config.lat,
          lng: config.lng,
          radiusM: config.radiusM,
          limit: config.placeLimit,
          category: config.category,
          language: config.lang,
        ),
        source: 'db',
        locationEngine: 'postgis',
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaWeather>> getWeather() async {
    weatherRequests += 1;
    weatherRequestConfigs.add(config);
    await _delayIfNeeded(weatherDelay);
    if (failWeatherLoad) {
      throw const LalaApiException(
        code: 'WEATHER_UNAVAILABLE',
        message: 'Weather route failed.',
        statusCode: 503,
        retryable: true,
        requestId: 'failed-weather-route',
      );
    }
    return _envelope(weather ?? _weather());
  }

  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() async {
    interventionRequestConfigs.add(config);
    await _delayIfNeeded(interventionDelay);
    if (failInterventionLoad) {
      throw const LalaApiException(
        code: 'INTERVENTION_UNAVAILABLE',
        message: 'Intervention route failed.',
        statusCode: 503,
        retryable: true,
        requestId: 'failed-intervention-route',
      );
    }
    final place = (places ?? [_place()]).first;
    return _envelope(
      LalaIntervention(
        center: LalaCoordinate(lat: config.lat, lng: config.lng),
        radiusM: config.radiusM,
        shouldIntervene: shouldIntervene,
        reason: 'Weather is fine.',
        recommendedAction: 'Keep the current route.',
        source: 'db',
        place: place,
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() async {
    dailyPlanRequests += 1;
    dailyPlanRequestConfigs.add(config);
    await _delayIfNeeded(dailyPlanDelay);
    if (failDailyPlanLoad) {
      throw const LalaApiException(
        code: 'DAILY_PLAN_UNAVAILABLE',
        message: 'Daily plan is temporarily unavailable.',
        statusCode: 503,
        retryable: true,
        requestId: 'failed-daily-plan',
      );
    }
    final place = (places ?? [_place()]).first;
    return _envelope(
      LalaDailyPlan(
        language: 'ko',
        center: LalaCoordinate(lat: config.lat, lng: config.lng),
        radiusM: config.radiusM,
        weather: weather ?? _weather(),
        slots: [
          LalaPlanSlot(period: 'morning', title: '화성행궁 산책 코스', place: place),
        ],
        source: 'db',
        requestHash:
            'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
        cacheKey: 'daily_plan:abcdef0123456789abcdef0123456789',
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaDocentScript>> createDocentScript({
    required LalaPlace place,
    LalaWeather? weather,
    String mode = 'brief',
  }) async {
    docentScriptRequests.add('$mode:${place.placeId}');
    await _delayIfNeeded(docentScriptDelay);
    if (failDocentScriptLoad) {
      throw const LalaApiException(
        code: 'DOCENT_UNAVAILABLE',
        message: 'Docent script is temporarily unavailable.',
        statusCode: 503,
        retryable: true,
        requestId: 'failed-docent-script',
      );
    }
    final script = mode == 'detail'
        ? '화성행궁 상세 도슨트입니다. 행궁동 골목, 수원화성 성곽, 주변 로컬 상권을 이어서 천천히 걸어보세요.'
        : '화성행궁은 조선 왕실의 이동 궁궐로, 수원화성과 함께 걷기 좋은 코스입니다.';
    return _envelope(
      LalaDocentScript(
        placeId: place.placeId,
        category: place.category,
        language: 'ko',
        mode: mode,
        script: script,
        source: 'rule_based_curation',
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

Future<void> _delayIfNeeded(Duration delay) async {
  if (delay > Duration.zero) {
    await Future<void>.delayed(delay);
  }
}

class SnapshotFallbackBackend extends FakeBackend {
  SnapshotFallbackBackend(super.config);

  @override
  Future<LalaEnvelope<LalaReadiness>> getReadiness() async {
    return _envelope(
      const LalaReadiness(
        status: 'ok',
        checks: {
          'client_auth': 'snapshot-fallback',
          'client_identity': 'snapshot-fallback',
          'db': 'skipped',
          'postgis': 'skipped',
          'static_snapshot_fallback': 'enabled',
          'public_data_snapshot': 'configured',
          'live_speech': 'disabled',
          'worker_contracts': 'configured',
        },
        mode: LalaRuntimeMode(
          overall: 'public-cache',
          data: 'public-cache',
          ai: 'disabled',
          speech: 'disabled',
          worker: 'dry-run',
        ),
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async {
    placesRequestConfigs.add(config);
    final responsePlaces = [_offlineFallbackPlace()];
    return _envelope(
      LalaPlacesResponse(
        count: responsePlaces.length,
        places: responsePlaces,
        query: LalaPlacesQuery(
          lat: config.lat,
          lng: config.lng,
          radiusM: config.radiusM,
          limit: config.placeLimit,
          category: config.category,
          language: config.lang,
        ),
        source: 'public_mvp_snapshot',
        locationEngine: 'static_snapshot',
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaWeather>> getWeather() async {
    return _envelope(_weather(source: 'public_mvp_snapshot'));
  }

  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() async {
    final place = _offlineFallbackPlace();
    return _envelope(
      LalaIntervention(
        center: LalaCoordinate(lat: config.lat, lng: config.lng),
        radiusM: config.radiusM,
        shouldIntervene: false,
        reason: 'Limited offline context.',
        recommendedAction: 'Review live data before routing.',
        source: 'public_mvp_snapshot',
        place: place,
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() async {
    final place = _offlineFallbackPlace();
    return _envelope(
      LalaDailyPlan(
        language: config.lang,
        center: LalaCoordinate(lat: config.lat, lng: config.lng),
        radiusM: config.radiusM,
        weather: _weather(source: 'public_mvp_snapshot'),
        slots: [
          LalaPlanSlot(
            period: 'morning',
            title: 'Offline review route',
            place: place,
          ),
        ],
        source: 'public_mvp_snapshot',
        requestHash:
            'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
        cacheKey: 'daily_plan:snapshot-fallback',
      ),
    );
  }
}

class BilingualInterventionBackend extends FakeBackend {
  BilingualInterventionBackend(super.config) : super(shouldIntervene: true);

  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() async {
    final place = (places ?? [_bilingualPlace()]).first;
    return _envelope(
      LalaIntervention(
        center: LalaCoordinate(lat: config.lat, lng: config.lng),
        radiusM: config.radiusM,
        shouldIntervene: true,
        reason: '날씨가 좋아요 Weather is good.',
        recommendedAction: '지금 코스를 유지하세요 Keep walking.',
        source: 'db',
        place: place,
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() async {
    dailyPlanRequests += 1;
    final place = (places ?? [_bilingualPlace()]).first;
    return _envelope(
      LalaDailyPlan(
        language: config.lang,
        center: LalaCoordinate(lat: config.lat, lng: config.lng),
        radiusM: config.radiusM,
        weather: _weather(),
        slots: [
          LalaPlanSlot(
            period: 'morning',
            title: '화성행궁 산책 Hwaseong walk',
            place: place,
          ),
        ],
        source: 'db',
        requestHash:
            'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
        cacheKey: 'daily_plan:abcdef0123456789abcdef0123456789',
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaDocentScript>> createDocentScript({
    required LalaPlace place,
    LalaWeather? weather,
    String mode = 'brief',
  }) async {
    docentScriptRequests.add('$mode:${place.placeId}');
    final script = mode == 'detail'
        ? '화성행궁 상세 도슨트입니다. Detailed docent for Hwaseong Haenggung.'
        : '화성행궁은 조선 왕실의 이동 궁궐입니다. Hwaseong Haenggung connects royal history and local streets.';
    return _envelope(
      LalaDocentScript(
        placeId: place.placeId,
        category: place.category,
        language: config.lang,
        mode: mode,
        script: script,
        source: 'rule_based_curation',
        requestHash:
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        cacheKey: 'docent_script:0123456789abcdef0123456789abcdef',
      ),
    );
  }
}

class PlaceholderDocentBackend extends FakeBackend {
  PlaceholderDocentBackend(super.config);

  @override
  Future<LalaEnvelope<LalaDocentScript>> createDocentScript({
    required LalaPlace place,
    LalaWeather? weather,
    String mode = 'brief',
  }) async {
    docentScriptRequests.add('$mode:${place.placeId}');
    return _envelope(
      LalaDocentScript(
        placeId: place.placeId,
        category: place.category,
        language: config.lang,
        mode: mode,
        script: 'This is a migration skeleton docent script.',
        source: 'rule_based_curation',
        requestHash:
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        cacheKey: 'docent_script:0123456789abcdef0123456789abcdef',
      ),
    );
  }
}

class FailNTimesThenSucceedPlacesBackend extends FakeBackend {
  FailNTimesThenSucceedPlacesBackend(
    super.config, {
    required this.failuresBeforeSuccess,
  });

  final int failuresBeforeSuccess;
  int getPlacesAttempts = 0;

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async {
    getPlacesAttempts += 1;
    placesRequestConfigs.add(config);
    await _delayIfNeeded(placesDelay);
    if (getPlacesAttempts <= failuresBeforeSuccess) {
      throw const LalaApiException(
        code: 'UPSTREAM_UNAVAILABLE',
        message: 'Authenticated route failed.',
        statusCode: 503,
        retryable: true,
        requestId: 'flaky-auth-route',
      );
    }
    final responsePlaces =
        places ?? [_place(), _culturePlace(), _restaurantPlace()];
    return _envelope(
      LalaPlacesResponse(
        count: responsePlaces.length,
        places: responsePlaces,
        query: LalaPlacesQuery(
          lat: config.lat,
          lng: config.lng,
          radiusM: config.radiusM,
          limit: config.placeLimit,
          category: config.category,
          language: config.lang,
        ),
        source: 'db',
        locationEngine: 'postgis',
      ),
    );
  }
}

class BilingualLoadFailureBackend extends FakeBackend {
  BilingualLoadFailureBackend(super.config);

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async {
    throw const LalaApiException(
      code: 'UPSTREAM_UNAVAILABLE',
      message: '장소를 불러오지 못했어요 Places failed.',
      statusCode: 503,
      retryable: true,
      requestId: 'bilingual-load-failure',
    );
  }
}

List<String> _visibleMixedLanguageTexts(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
      .where((text) => _hasMixedKoreanEnglish(text))
      .toList(growable: false);
}

bool _hasMixedKoreanEnglish(String value) {
  return RegExp(r'[가-힣]').hasMatch(value) &&
      RegExp(r'[A-Za-z]{3,}').hasMatch(value);
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
    nameKo: '화성행궁',
    nameEn: 'Hwaseong Haenggung',
    category: 'attraction',
    lat: 37.2819,
    lng: 127.0142,
    address: '경기도 수원시 팔달구 정조로 825',
    regionKo: '수원',
    regionEn: 'Suwon',
    distanceM: 145,
    source: 'db',
    upstreamSource: 'tour_api',
    score: LalaPlaceScore(
      finalScore: 0.86,
      formulaVersion: 'local-value-v2',
      components: LalaPlaceScoreComponents(
        localSpendingScore: 0.82,
        smallMerchantFitScore: 0.76,
        demandDispersionScore: 0.78,
        weatherFitScore: 0.74,
        reviewQualityScore: null,
        cultureRelevanceScore: 0.91,
        accessibilityFitScore: 0.62,
      ),
      dataBasis: 'analytics.place_score_snapshots',
      features: {
        'primary_source': 'tour_api',
        'input_sources': <String>[
          'travel.places',
          'economy.card_spending_area_monthly',
          'culture.events',
          'travel.weather_observations',
        ],
        'culture_event_count': 3,
        'place_event_count': 1,
        'region_spend_amount': 14000000.0,
        'region_transaction_count': 1700,
        'missing_signals': <String>['review_attribute_analysis'],
      },
    ),
  );
}

LalaPlace _offlineFallbackPlace() {
  return const LalaPlace(
    placeId: 'offline-review-place',
    name: 'Offline Review Place',
    nameKo: '오프라인 검토 장소',
    nameEn: 'Offline Review Place',
    category: 'attraction',
    lat: 37.5665,
    lng: 126.9780,
    address: 'Seoul Jung-gu',
    regionKo: '서울 중구',
    regionEn: 'Seoul Jung-gu',
    distanceM: 180,
    source: 'public_mvp_snapshot',
    upstreamSource: 'public_mvp_snapshot',
    score: LalaPlaceScore(
      finalScore: 0.62,
      formulaVersion: 'local-value-v2',
      components: LalaPlaceScoreComponents(
        localSpendingScore: 0.48,
        smallMerchantFitScore: null,
        demandDispersionScore: 0.52,
        weatherFitScore: 0.50,
        reviewQualityScore: null,
        cultureRelevanceScore: 0.64,
        accessibilityFitScore: 0.50,
      ),
      dataBasis: 'public_mvp_snapshot',
      features: {
        'primary_source': 'public_mvp_snapshot',
        'input_sources': <String>['public_mvp_snapshot'],
      },
    ),
  );
}

LalaPlace _culturePlace({int distanceM = 620}) {
  return LalaPlace(
    placeId: 'suwon-hwaseong',
    name: '수원화성',
    nameKo: '수원화성',
    nameEn: 'Suwon Hwaseong Fortress',
    category: 'culture_venue',
    lat: 37.2870,
    lng: 127.0110,
    address: '경기도 수원시 장안구 영화동',
    regionKo: '수원',
    regionEn: 'Suwon',
    distanceM: distanceM,
    source: 'db',
    upstreamSource: 'tour_api',
    score: const LalaPlaceScore(
      finalScore: 0.82,
      formulaVersion: 'local-value-v2',
      components: LalaPlaceScoreComponents(
        localSpendingScore: 0.68,
        smallMerchantFitScore: null,
        demandDispersionScore: 0.73,
        weatherFitScore: 0.76,
        reviewQualityScore: null,
        cultureRelevanceScore: 0.96,
        accessibilityFitScore: 0.70,
      ),
      dataBasis: 'analytics.place_score_snapshots',
      features: {
        'primary_source': 'tour_api',
        'input_sources': <String>['travel.places', 'culture.events'],
        'culture_event_count': 2,
      },
    ),
  );
}

LalaPlace _restaurantPlace({int distanceM = 780, String? imageUrl}) {
  return LalaPlace(
    placeId: 'haenggung-cafe-street',
    name: '행궁동 카페거리',
    nameKo: '행궁동 카페거리',
    nameEn: 'Haenggung Cafe Street',
    category: 'restaurant',
    lat: 37.2828,
    lng: 127.0101,
    address: '경기도 수원시 팔달구 행궁동',
    regionKo: '수원',
    regionEn: 'Suwon',
    imageUrl: imageUrl,
    distanceM: distanceM,
    source: 'db',
    upstreamSource: 'tour_api',
    score: const LalaPlaceScore(
      finalScore: 0.78,
      formulaVersion: 'local-value-v2',
      components: LalaPlaceScoreComponents(
        localSpendingScore: 0.88,
        smallMerchantFitScore: 0.82,
        demandDispersionScore: 0.54,
        weatherFitScore: 0.70,
        reviewQualityScore: null,
        cultureRelevanceScore: 0.62,
        accessibilityFitScore: 0.58,
      ),
      dataBasis: 'analytics.place_score_snapshots',
      features: {
        'primary_source': 'tour_api',
        'input_sources': <String>[
          'travel.places',
          'economy.card_spending_area_monthly',
        ],
      },
    ),
  );
}

LalaPlace _clusterRestaurant(String placeId, String name, int distanceM) {
  return LalaPlace(
    placeId: placeId,
    name: name,
    nameKo: name,
    nameEn: name.replaceAll('클러스터 맛집', 'Cluster Food'),
    category: 'restaurant',
    lat: 37.2800,
    lng: 127.0100,
    address: '경기도 수원시 팔달구 행궁동',
    regionKo: '수원',
    regionEn: 'Suwon',
    distanceM: distanceM,
    source: 'db',
    upstreamSource: 'tour_api',
    score: const LalaPlaceScore(
      finalScore: 0.77,
      formulaVersion: 'local-value-v2',
      components: LalaPlaceScoreComponents(
        localSpendingScore: 0.89,
        smallMerchantFitScore: 0.80,
        demandDispersionScore: 0.61,
        weatherFitScore: 0.72,
        reviewQualityScore: null,
        cultureRelevanceScore: 0.58,
        accessibilityFitScore: 0.56,
      ),
      dataBasis: 'analytics.place_score_snapshots',
      features: {
        'primary_source': 'tour_api',
        'input_sources': <String>['travel.places'],
      },
    ),
  );
}

LalaPlace _eventPlace() {
  return const LalaPlace(
    placeId: 'tour-api-suwon-night-walk',
    name: '화성행궁 야간 산책',
    nameKo: '화성행궁 야간 산책',
    nameEn: 'Hwaseong Haenggung Night Walk',
    category: 'event',
    lat: 37.2819,
    lng: 127.0142,
    address: '경기도 수원시 팔달구 행궁동',
    regionKo: '수원시',
    regionEn: 'Suwon',
    eventStartDate: '2026-06-01',
    eventEndDate: '2026-08-31',
    eventUrl: 'https://example.test/events/suwon-night-walk-2026',
    isOngoing: true,
    isApproximateLocation: false,
    distanceM: 180,
    source: 'db',
    upstreamSource: 'tour_api',
    score: LalaPlaceScore(
      finalScore: 0.79,
      formulaVersion: 'local-value-v2',
      components: LalaPlaceScoreComponents(
        localSpendingScore: 0.95,
        smallMerchantFitScore: null,
        demandDispersionScore: 0.59,
        weatherFitScore: 0.72,
        reviewQualityScore: null,
        cultureRelevanceScore: 0.90,
        accessibilityFitScore: 0.60,
      ),
      dataBasis: 'analytics.place_score_snapshots',
      features: {
        'primary_source': 'tour_api',
        'input_sources': <String>[
          'travel.places',
          'travel.place_events',
          'culture.events',
          'economy.card_spending_area_monthly',
        ],
        'place_event_count': 1,
        'culture_event_count': 13,
      },
    ),
  );
}

LalaPlace _koreanOnlyPlace() {
  return const LalaPlace(
    placeId: 'korean-only-place',
    name: '호반아트리움',
    nameKo: '호반아트리움',
    category: 'attraction',
    lat: 37.4260,
    lng: 127.0020,
    address: '경기도 과천시 사기막길 71-7',
    regionKo: '과천시',
    distanceM: 320,
    source: 'db',
    upstreamSource: 'tour_api',
  );
}

LalaPlace _englishOnlyPlace() {
  return const LalaPlace(
    placeId: 'english-only-place',
    name: 'Hoam Art Museum',
    nameEn: 'Hoam Art Museum',
    category: 'culture_venue',
    lat: 37.2930,
    lng: 127.2020,
    address: '38 Everland-ro 562beon-gil, Yongin-si, Gyeonggi-do',
    regionEn: 'Yongin',
    distanceM: 620,
    source: 'db',
    upstreamSource: 'tour_api',
  );
}

LalaPlace _bilingualPlace() {
  return const LalaPlace(
    placeId: 'bilingual-place',
    name: '화성행궁 Hwaseong Haenggung',
    category: 'attraction',
    lat: 37.2819,
    lng: 127.0142,
    address: '경기도 수원시 팔달구 Suwon-si, Gyeonggi-do',
    distanceM: 145,
    source: 'db',
    upstreamSource: 'tour_api',
  );
}

LalaWeather _weather({String source = 'db'}) {
  return LalaWeather(
    lat: 37.2636,
    lng: 127.0286,
    temp: '14°C',
    icon: 'partly-cloudy',
    dust: const LalaDust(
      pm10: '31',
      pm25: '14',
      grade: 'normal',
      gradeKo: '보통',
      pm10Grade: 'normal',
      pm10GradeKo: '보통',
      pm25Grade: 'good',
      pm25GradeKo: '좋음',
    ),
    forecast: [
      LalaForecastItem(time: '15:00', temp: '22C', icon: 'partly-cloudy'),
    ],
    outdoorStatus: 'good',
    force: false,
    source: source,
    location: 'Suwon',
    recordTime: '2026-06-18T09:00:00+09:00',
    locationMatch: true,
  );
}
