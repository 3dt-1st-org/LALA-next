// S-12 place detail accessibility gate: large-text safety on the compact
// first viewport, a labeled loading state, and an announced stale-context
// notice. These prove the text-scaling-safe action row (minimum height, no
// FittedBox shrink) instead of the pre-fix fixed 68px row.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/navigation/local_signal_action.dart';
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/core/state/saved_place_store.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_controller.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/place/presentation/pages/place_detail_page.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';

import '../docent/inert_docent_audio_player.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SavedPlaceStore.clear();
    OnboardingState.applySnapshot(
      const OnboardingSnapshot(completed: true, language: 'ko'),
    );
  });
  tearDown(() {
    SavedPlaceStore.clear();
    OnboardingState.reset();
  });

  Future<void> pumpDetail(
    WidgetTester tester, {
    TextScaler textScaler = TextScaler.noScaling,
    LalaBackendFactory? backendFactory,
  }) async {
    final docentController = DocentExperienceController(
      backendFactory: (_) => _DetailBackend(),
      baseConfig: const LalaAppConfig(baseUri: 'https://example.invalid'),
      player: InertDocentAudioPlayer(),
    );
    addTearDown(() async => docentController.dispose());
    final preferencesStore = TravelPreferencesStore();
    await preferencesStore.ensureLoaded();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: PlaceDetailPage(
          placeId: _place.placeId,
          initialPlace: _place,
          backendFactory: backendFactory ?? (_) => _DetailBackend(),
          initialConfig: const LalaAppConfig(
            baseUri: 'https://example.invalid',
          ),
          actionController: LocalSignalActionController(),
          docentExperienceController: docentController,
          preferencesStore: preferencesStore,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'S-12 keeps the action row on the first viewport at 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpDetail(tester, textScaler: const TextScaler.linear(2));

      expect(tester.takeException(), isNull);
      // First-viewport compactness: the primary actions are tappable without
      // any scrolling even with doubled text.
      expect(
        find.byKey(const ValueKey('place-detail-add-to-plan')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find
            .byKey(const ValueKey('place-detail-restaurant-help'))
            .hitTestable(),
        findsOneWidget,
      );
      expect(find.text('일정 추가'), findsOneWidget);
    },
  );

  testWidgets('S-12 announces the loading state to screen readers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final docentController = DocentExperienceController(
      backendFactory: (_) => _DetailBackend(),
      baseConfig: const LalaAppConfig(baseUri: 'https://example.invalid'),
      player: InertDocentAudioPlayer(),
    );
    addTearDown(() async => docentController.dispose());

    await tester.pumpWidget(
      MaterialApp(
        home: PlaceDetailPage(
          placeId: _place.placeId,
          backendFactory: (_) => _HangingBackend(),
          initialConfig: const LalaAppConfig(
            baseUri: 'https://example.invalid',
          ),
          actionController: LocalSignalActionController(),
          docentExperienceController: docentController,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('place-detail-loading')), findsOneWidget);
    expect(find.bySemanticsLabel('장소 정보를 불러오는 중'), findsOneWidget);
  });

  testWidgets('S-12 marks the stale-context notice as a live region', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The failing backend keeps the initial place but breaks the refresh,
    // surfacing the stale-context notice.
    await pumpDetail(tester, backendFactory: (_) => _FailingBackend());

    expect(tester.takeException(), isNull);
    expect(find.text('최신 날씨와 출처 정보를 확인하지 못했어요.'), findsOneWidget);
    final handle = tester.ensureSemantics();
    final node = find
        .byKey(const ValueKey('place-detail-stale-notice'))
        .evaluate()
        .single
        .renderObject!
        .debugSemantics!;
    expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });
}

const LalaPlace _place = LalaPlace(
  placeId: 'canonical-restaurant',
  name: '정본 식당',
  nameKo: '정본 식당',
  nameEn: 'Canonical Restaurant',
  category: 'restaurant',
  lat: 37.55,
  lng: 127.04,
  address: '서울특별시 성동구',
  regionKo: '성수동',
  regionEn: 'Seongsu-dong',
  distanceM: 420,
  source: 'db',
  upstreamSource: 'tour_api',
  reason: '공식 장소 정보와 현재 날씨를 함께 확인했어요.',
  freshness: '2026-09-03T09:00:00Z',
);

class _DetailBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async => _envelope(
    const LalaPlacesResponse(
      count: 1,
      places: <LalaPlace>[_place],
      query: LalaPlacesQuery(
        lat: 37.55,
        lng: 127.04,
        radiusM: 3000,
        limit: 60,
        category: 'all',
        language: 'ko',
      ),
      source: 'db',
      locationEngine: 'postgis',
      dataAsOf: '2026-09-03T09:00:00Z',
    ),
  );

  @override
  Future<LalaEnvelope<LalaWeather>> getWeather() async => _envelope(
    LalaWeather(
      lat: 37.55,
      lng: 127.04,
      temp: '24°C',
      icon: 'sunny',
      dust: const LalaDust(
        pm10: '24',
        pm25: '11',
        grade: 'good',
        gradeKo: '좋음',
        pm10Grade: 'good',
        pm10GradeKo: '좋음',
        pm25Grade: 'good',
        pm25GradeKo: '좋음',
      ),
      forecast: const <LalaForecastItem>[],
      outdoorStatus: 'good',
      force: false,
      source: 'db+airkorea_sido_realtime',
    ),
  );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used');
}

/// Never-resolving backend so the page stays in its loading state.
class _HangingBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() =>
      Completer<LalaEnvelope<LalaPlacesResponse>>().future;

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used');
}

/// Backend whose lookups fail after the initial place was supplied.
class _FailingBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async =>
      throw StateError('lookup unavailable');

  @override
  Future<LalaEnvelope<LalaWeather>> getWeather() async =>
      throw StateError('weather unavailable');

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used');
}

LalaEnvelope<T> _envelope<T>(T data) => LalaEnvelope<T>(
  ok: true,
  data: data,
  meta: const <String, dynamic>{},
  error: null,
  statusCode: 200,
  requestId: 'screen-test',
);
