import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../config/app_config.dart';
import 'package:lala_next_app/shared/l10n/place_labels.dart';

/// C3 최종: main.dart 에서 이관. 본문 불변(이동만).
/// 백엔드 추상 경계 + API 구현체. _placeDisplayName forwarder 는
/// shared/l10n/place_labels.dart 의 placeDisplayName 과 동일해 직접 호출.

typedef LalaBackendFactory = LalaBackend Function(LalaAppConfig config);

abstract class LalaBackend {
  Future<LalaEnvelope<Map<String, dynamic>>> getHealth();

  Future<LalaEnvelope<LalaReadiness>> getReadiness();

  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces();

  Future<LalaEnvelope<LalaWeather>> getWeather();

  Future<LalaEnvelope<LalaIntervention>> getIntervention();

  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan();

  Future<LalaEnvelope<LalaDocentScript>> createDocentScript({
    required LalaPlace place,
    LalaWeather? weather,
    String mode = 'brief',
  });

  Future<LalaAudioResponse> createDocentAudio({required String script});

  void close();
}

class LalaApiBackend implements LalaBackend {
  LalaApiBackend(this.config)
    : _client = LalaApiClient(
        baseUri: Uri.parse(config.baseUri),
        bearerToken: config.bearerToken,
        apiKey: config.apiKey,
        accessTokenProvider: config.accessTokenProvider,
      );

  final LalaAppConfig config;
  final LalaApiClient _client;

  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getHealth() {
    return _client.getHealth();
  }

  @override
  Future<LalaEnvelope<LalaReadiness>> getReadiness() {
    return _client.getReadiness();
  }

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() {
    return _client.getPlaces(
      lat: config.lat,
      lng: config.lng,
      radiusM: config.radiusM,
      limit: config.placeLimit,
      category: config.category,
      lang: config.lang,
      includeScores: true,
    );
  }

  @override
  Future<LalaEnvelope<LalaWeather>> getWeather() {
    return _client.getWeather(lat: config.lat, lng: config.lng);
  }

  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() {
    return _client.getIntervention(
      lat: config.lat,
      lng: config.lng,
      radiusM: config.radiusM,
    );
  }

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() {
    return _client.createDailyPlan(
      lat: config.lat,
      lng: config.lng,
      radiusM: config.radiusM,
      language: config.lang,
    );
  }

  @override
  Future<LalaEnvelope<LalaDocentScript>> createDocentScript({
    required LalaPlace place,
    LalaWeather? weather,
    String mode = 'brief',
  }) {
    return _client.createDocentScript(
      placeId: place.placeId,
      placeName: placeDisplayName(place, config.lang),
      address: place.address,
      regionKo: place.regionKo,
      regionEn: place.regionEn,
      distanceM: place.distanceM,
      source: place.source,
      upstreamSource: place.upstreamSource,
      finalScore: place.score?.finalScore,
      localSpendingScore: place.score?.components.localSpendingScore,
      smallMerchantFitScore: place.score?.components.smallMerchantFitScore,
      demandDispersionScore: place.score?.components.demandDispersionScore,
      weatherFitScore: place.score?.components.weatherFitScore,
      cultureRelevanceScore: place.score?.components.cultureRelevanceScore,
      weatherTemp: weather?.temp,
      weatherIcon: weather?.icon,
      weatherOutdoorStatus: weather?.outdoorStatus,
      dustGrade: weather?.dust.grade,
      dustPm10: weather?.dust.pm10,
      dustPm25: weather?.dust.pm25,
      dustPm10Grade: weather?.dust.pm10Grade,
      dustPm25Grade: weather?.dust.pm25Grade,
      category: place.category,
      language: config.lang,
      mode: mode,
    );
  }

  @override
  Future<LalaAudioResponse> createDocentAudio({required String script}) {
    return _client.createDocentAudio(script: script, language: config.lang);
  }

  @override
  void close() {
    _client.close();
  }
}
