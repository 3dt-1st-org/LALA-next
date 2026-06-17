import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    expect(find.textContaining('카카오 지도 키'), findsOneWidget);
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
    expect(find.textContaining('조선 왕실'), findsAtLeastNWidgets(1));

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
    expect(find.text('카드 소비'), findsOneWidget);
    expect(find.text('문화행사 데이터'), findsOneWidget);
    expect(find.textContaining('날씨'), findsWidgets);
  });

  testWidgets('filters places from category chips and toggles map modes', (
    tester,
  ) async {
    final configs = <LalaAppConfig>[];
    final backends = <FakeBackend>[];
    await tester.pumpWidget(
      LalaApp(
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
    await tester.tap(autoToggle);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: autoToggle, matching: find.text('켬')),
      findsOneWidget,
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
      LalaApp(
        backendFactory: (_) => backend,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();
    expect(backend.weatherRequests, 1);

    await tester.tap(find.byKey(const ValueKey('weather-pill-hit-target')));
    await tester.pumpAndSettle();

    expect(backend.weatherRequests, 2);
    expect(find.text('날씨'), findsOneWidget);
    expect(find.text('날씨 추이'), findsOneWidget);
    expect(find.text('15시'), findsAtLeastNWidgets(1));
    expect(find.text('22°'), findsOneWidget);
    expect(find.text('PM10'), findsOneWidget);
  });

  testWidgets('food tour pill opens restaurant tour sheet', (tester) async {
    final backend = FakeBackend(
      const LalaAppConfig(baseUri: 'http://api.test'),
    );
    await tester.pumpWidget(
      LalaApp(
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
      LalaApp(
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
      LalaApp(
        backendFactory: (config) => FakeBackend(config, shouldIntervene: true),
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('날씨가 바뀌었어요'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('intervention-toast-plan')));
    await tester.pumpAndSettle();
    expect(find.text('오늘 일정'), findsOneWidget);

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
        LalaApp(
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
      LalaApp(
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
      LalaApp(
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
    await tester.pumpWidget(
      LalaApp(
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
    await tester.pumpWidget(
      LalaApp(
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
      find.byKey(const ValueKey('kakao-map-fallback-center-37.2819-127.0142')),
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
    var backendCreations = 0;
    await tester.pumpWidget(
      LalaApp(
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
    var backendCreations = 0;
    await tester.pumpWidget(
      LalaApp(
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
      LalaApp(
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
    expect(find.text('추천 장소 보기'), findsOneWidget);
  });

  testWidgets('recommendation rail collapses and place cards select detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      LalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('수원화성'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('obang-border-hwaseong-haenggung')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('kakao-map-fallback-center-37.2819-127.0142')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('tour-stop-action-hwaseong-haenggung')),
    );
    await tester.pumpAndSettle();

    expect(find.text('장소 상세'), findsNothing);
    expect(find.text('화성행궁 도슨트'), findsOneWidget);

    await tester.tap(find.text('추천 장소 보기'));
    await tester.pumpAndSettle();

    expect(find.text('수원화성'), findsNothing);
    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));

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
      find.byKey(const ValueKey('obang-border-suwon-hwaseong')),
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

  testWidgets('cluster marker focuses its member recommendations', (
    tester,
  ) async {
    await tester.pumpWidget(
      LalaApp(
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
      find.byKey(
        const ValueKey('kakao-map-marker-cluster-restaurant:6710:22862'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('kakao-map-marker-cluster-restaurant:6710:22862'),
        ),
        matching: find.text('맛'),
      ),
      findsNothing,
    );
    expect(find.text('화성행궁 도슨트'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('kakao-map-marker-cluster-restaurant:6710:22862'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('클러스터 맛집 A 도슨트'), findsOneWidget);
    expect(find.text('화성행궁 도슨트'), findsNothing);
    expect(find.text('클러스터 맛집 A'), findsAtLeastNWidgets(1));
  });

  testWidgets('location consent off surfaces the map permission overlay', (
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
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('닫기').first);
    await tester.pumpAndSettle();

    expect(find.text('위치기반 추천이 꺼져 있어요'), findsOneWidget);
    expect(find.text('설정에서 켜기'), findsOneWidget);
    expect(find.text('다시 확인'), findsOneWidget);

    await tester.tap(find.text('설정에서 켜기'));
    await tester.pumpAndSettle();

    expect(find.text('설정'), findsOneWidget);
    expect(find.text('위치기반 정보 제공 동의'), findsOneWidget);
  });

  testWidgets('location consent retry restores map recommendations', (
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
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('닫기').first);
    await tester.pumpAndSettle();

    expect(find.text('위치기반 추천이 꺼져 있어요'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('location-consent-retry')));
    await tester.pumpAndSettle();

    expect(find.text('위치기반 추천이 꺼져 있어요'), findsNothing);
    expect(find.text('추천 장소 보기'), findsOneWidget);
    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
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
    expect(find.textContaining('조선 왕실'), findsAtLeastNWidgets(1));
  });

  testWidgets('surfaces fallback state when authenticated load fails', (
    tester,
  ) async {
    var backendCreations = 0;
    await tester.pumpWidget(
      LalaApp(
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

    expect(find.text('요청을 처리하지 못했습니다.'), findsOneWidget);
    expect(
      find.text('UPSTREAM_UNAVAILABLE: Authenticated route failed.'),
      findsNothing,
    );
    expect(find.textContaining('데모 기준'), findsWidgets);
    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
    expect(find.byKey(const ValueKey('map-error-retry')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('map-error-retry')));
    await tester.pumpAndSettle();

    expect(backendCreations, 3);
    expect(
      find.text('UPSTREAM_UNAVAILABLE: Authenticated route failed.'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('map-error-retry')), findsNothing);
    expect(find.textContaining('조선 왕실'), findsAtLeastNWidgets(1));
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
      find.widgetWithText(TextField, '기본 주소'),
      'http://10.0.0.5:8080',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '마이그레이션 키'),
      'migration-key',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '카카오 지도 키'),
      'kakao-js-key',
    );
    final refreshButton = find.widgetWithText(FilledButton, '새로고침');
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
      LalaApp(
        backendFactory: FakeBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings).first);
    await tester.pumpAndSettle();

    expect(find.text('한국어'), findsOneWidget);
    expect(find.text('영어'), findsOneWidget);
    expect(find.text('Korean'), findsNothing);
    expect(find.text('English'), findsNothing);

    await tester.tap(find.text('영어'));
    await tester.pumpAndSettle();

    expect(find.text('Korean'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('한국어'), findsNothing);
    expect(find.text('영어'), findsNothing);
  });

  testWidgets('english language setting does not mix Korean place copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      LalaApp(
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
    expect(find.text('Listen'), findsOneWidget);
    expect(find.textContaining('화성행궁'), findsNothing);
    expect(find.textContaining('경기도'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Details'));
    await tester.pumpAndSettle();

    expect(find.text('Details'), findsWidgets);
    expect(find.text('Suwon'), findsAtLeastNWidgets(1));
    expect(find.text('Local context'), findsOneWidget);
    expect(find.text('1 linked events'), findsOneWidget);
    expect(find.text('Card spend KRW 14,000,000'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Show signals'));
    await tester.pumpAndSettle();

    expect(find.text('Card spend KRW 14,000,000'), findsOneWidget);
    expect(find.text('Local score'), findsOneWidget);
    expect(find.textContaining('화성행궁'), findsNothing);
    expect(find.textContaining('경기도'), findsNothing);
  });

  testWidgets(
    'event detail shows legacy metadata without opening score signals',
    (tester) async {
      await tester.pumpWidget(
        LalaApp(
          backendFactory: (config) =>
              FakeBackend(config, places: [_eventPlace()]),
          initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('행사 · 진행 중'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '상세'));
      await tester.pumpAndSettle();

      expect(find.text('행사 정보'), findsOneWidget);
      expect(find.text('진행 중'), findsOneWidget);
      expect(find.text('2026년 06월 01일 ~ 2026년 08월 31일'), findsOneWidget);
      expect(find.text('행사 상세 보기'), findsOneWidget);
      expect(find.text('로컬 점수'), findsNothing);
      expect(find.text('내국인 소비'), findsNothing);
    },
  );

  testWidgets('event detail follows English language setting', (tester) async {
    await tester.pumpWidget(
      LalaApp(
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
  });

  testWidgets(
    'english mode uses neutral copy when English place data is absent',
    (tester) async {
      await tester.pumpWidget(
        LalaApp(
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
        LalaApp(
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
      LalaApp(
        backendFactory: (config) =>
            FakeBackend(config, places: [_bilingualPlace()]),
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('화성행궁'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Hwaseong'), findsNothing);
    expect(find.textContaining('Suwon-si'), findsNothing);

    await tester.tap(find.byIcon(Icons.settings).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('영어'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();

    expect(find.text('Hwaseong Haenggung'), findsAtLeastNWidgets(1));
    expect(find.textContaining('화성행궁'), findsNothing);
    expect(find.textContaining('경기도'), findsNothing);
  });

  testWidgets('selected language removes bilingual intervention copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      LalaApp(
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

    await tester.tap(find.byKey(const ValueKey('planner-pill-hit-target')));
    await tester.pumpAndSettle();
    expect(find.textContaining('화성행궁 산책'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Hwaseong walk'), findsNothing);
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('영어'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();

    expect(find.textContaining('Weather is good'), findsAtLeastNWidgets(1));
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
  });

  testWidgets('localized API errors follow the selected language only', (
    tester,
  ) async {
    await tester.pumpWidget(
      LalaApp(
        backendFactory: BilingualLoadFailureBackend.new,
        initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('장소를 불러오지 못했어요'), findsOneWidget);
    expect(find.textContaining('Places failed'), findsNothing);
    expect(_visibleMixedLanguageTexts(tester), isEmpty);

    await tester.tap(find.byIcon(Icons.settings).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('영어'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();

    expect(find.textContaining('Places failed'), findsOneWidget);
    expect(find.textContaining('장소를 불러오지 못했어요'), findsNothing);
    expect(_visibleMixedLanguageTexts(tester), isEmpty);
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
      LalaApp(
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
    expect(find.text('4 bytes'), findsOneWidget);
    expect(find.textContaining('상세 도슨트입니다'), findsAtLeastNWidgets(1));
    expect(find.widgetWithText(FilledButton, '정보 더 듣기'), findsNothing);
  });
}

class FakeBackend implements LalaBackend {
  FakeBackend(
    this.config, {
    this.failAuthenticatedLoad = false,
    this.shouldIntervene = false,
    this.places,
  });

  final LalaAppConfig config;
  final bool failAuthenticatedLoad;
  final bool shouldIntervene;
  final List<LalaPlace>? places;
  final List<String> docentScriptRequests = <String>[];
  final List<String> audioRequests = <String>[];
  int weatherRequests = 0;
  int dailyPlanRequests = 0;

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
          category: config.category,
          language: config.lang,
        ),
        source: 'skeleton',
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaWeather>> getWeather() async {
    weatherRequests += 1;
    return _envelope(_weather());
  }

  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() async {
    final place = (places ?? [_place()]).first;
    return _envelope(
      LalaIntervention(
        center: LalaCoordinate(lat: config.lat, lng: config.lng),
        radiusM: config.radiusM,
        shouldIntervene: shouldIntervene,
        reason: 'Weather is fine.',
        recommendedAction: 'Keep the current route.',
        source: 'skeleton',
        place: place,
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() async {
    dailyPlanRequests += 1;
    final place = (places ?? [_place()]).first;
    return _envelope(
      LalaDailyPlan(
        language: 'ko',
        center: LalaCoordinate(lat: config.lat, lng: config.lng),
        radiusM: config.radiusM,
        weather: _weather(),
        slots: [
          LalaPlanSlot(period: 'morning', title: '화성행궁 산책 코스', place: place),
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
    String mode = 'brief',
  }) async {
    docentScriptRequests.add('$mode:${place.placeId}');
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
        source: 'skeleton',
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
        source: 'skeleton',
        requestHash:
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        cacheKey: 'docent_script:0123456789abcdef0123456789abcdef',
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
    source: 'skeleton',
    upstreamSource: 'tour_api',
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
    source: 'skeleton',
    upstreamSource: 'tour_api',
    score: const LalaPlaceScore(
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
        'primary_source': 'tour_api',
        'input_sources': <String>['travel.places', 'culture.events'],
        'culture_event_count': 2,
      },
    ),
  );
}

LalaPlace _restaurantPlace({int distanceM = 780}) {
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
    distanceM: distanceM,
    source: 'skeleton',
    upstreamSource: 'tour_api',
    score: const LalaPlaceScore(
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
    source: 'skeleton',
    upstreamSource: 'tour_api',
    score: const LalaPlaceScore(
      finalScore: 0.77,
      formulaVersion: 'local-value-v1',
      components: LalaPlaceScoreComponents(
        localSpendingScore: 0.89,
        demandDispersionScore: 0.61,
        weatherFitScore: 0.72,
        reviewQualityScore: null,
        cultureRelevanceScore: 0.58,
      ),
      dataBasis: 'demo_fallback',
      features: {
        'primary_source': 'tour_api',
        'input_sources': <String>['travel.places'],
      },
    ),
  );
}

LalaPlace _eventPlace() {
  return const LalaPlace(
    placeId: 'demo-suwon-night-walk',
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
    source: 'public_mvp_snapshot',
    upstreamSource: 'dev_seed',
    score: LalaPlaceScore(
      finalScore: 0.79,
      formulaVersion: 'local-value-v1',
      components: LalaPlaceScoreComponents(
        localSpendingScore: 0.95,
        demandDispersionScore: 0.59,
        weatherFitScore: 0.72,
        reviewQualityScore: null,
        cultureRelevanceScore: 0.90,
      ),
      dataBasis: 'public_mvp_snapshot',
      features: {
        'primary_source': 'dev_seed',
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
    source: 'public_mvp_snapshot',
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
    source: 'public_mvp_snapshot',
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
    source: 'public_mvp_snapshot',
    upstreamSource: 'tour_api',
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
