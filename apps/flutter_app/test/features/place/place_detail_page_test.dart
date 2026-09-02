import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/navigation/local_signal_action.dart';
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/core/state/saved_place_store.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_controller.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/place/presentation/pages/place_detail_page.dart';

import '../docent/inert_docent_audio_player.dart';

void main() {
  setUp(() {
    SavedPlaceStore.clear();
    OnboardingState.applySnapshot(
      const OnboardingSnapshot(completed: true, language: 'ko'),
    );
  });
  tearDown(() {
    SavedPlaceStore.clear();
    OnboardingState.reset();
  });

  testWidgets(
    'S-12 binds real place data, save, evidence, and restaurant help',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final actionController = LocalSignalActionController();
      final docentController = DocentExperienceController(
        backendFactory: (_) => _PlaceDetailBackend(),
        baseConfig: const LalaAppConfig(baseUri: 'https://example.invalid'),
        player: InertDocentAudioPlayer(),
      );
      addTearDown(() async => docentController.dispose());

      await tester.pumpWidget(
        MaterialApp(
          home: PlaceDetailPage(
            placeId: _place.placeId,
            initialPlace: _place,
            backendFactory: (_) => _PlaceDetailBackend(),
            initialConfig: const LalaAppConfig(
              baseUri: 'https://example.invalid',
            ),
            actionController: actionController,
            docentExperienceController: docentController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('place-detail-page')), findsOneWidget);
      expect(find.text('정본 식당'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('restaurant-detail-show-staff')),
        findsOneWidget,
      );
      expect(SavedPlaceStore.isSaved(_place.placeId), isFalse);

      await tester.tap(find.byTooltip('저장'));
      await tester.pump();
      expect(SavedPlaceStore.isSaved(_place.placeId), isTrue);

      expect(find.text('내국인 소비'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('place-detail-toggle-evidence')),
      );
      await tester.pumpAndSettle();
      expect(find.text('내국인 소비'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'S-12 deep link shows honest unavailable state for an unknown ID',
    (tester) async {
      final docentController = DocentExperienceController(
        backendFactory: (_) => _PlaceDetailBackend(),
        baseConfig: const LalaAppConfig(baseUri: 'https://example.invalid'),
        player: InertDocentAudioPlayer(),
      );
      addTearDown(() async => docentController.dispose());

      await tester.pumpWidget(
        MaterialApp(
          home: PlaceDetailPage(
            placeId: 'missing-place',
            backendFactory: (_) => _PlaceDetailBackend(),
            initialConfig: const LalaAppConfig(
              baseUri: 'https://example.invalid',
            ),
            actionController: LocalSignalActionController(),
            docentExperienceController: docentController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('이 장소는 현재 제공되지 않아요.'), findsOneWidget);
      expect(find.text('정본 식당'), findsNothing);
    },
  );
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
  score: LalaPlaceScore(
    finalScore: 0.84,
    formulaVersion: 'test-v1',
    dataBasis: 'test evidence',
    features: <String, dynamic>{},
    components: LalaPlaceScoreComponents(
      localSpendingScore: 0.82,
      smallMerchantFitScore: 0.77,
      demandDispersionScore: 0.70,
      weatherFitScore: 0.91,
      reviewQualityScore: 0.75,
      cultureRelevanceScore: 0.68,
      accessibilityFitScore: null,
    ),
  ),
);

class _PlaceDetailBackend implements LalaBackend {
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

LalaEnvelope<T> _envelope<T>(T data) => LalaEnvelope<T>(
  ok: true,
  data: data,
  meta: const <String, dynamic>{},
  error: null,
  statusCode: 200,
  requestId: 'screen-test',
);
