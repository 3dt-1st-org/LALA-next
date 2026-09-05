import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../config/app_config.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';
import 'package:lala_next_app/shared/l10n/place_labels.dart';

/// C3 최종: main.dart 에서 이관. 본문 불변(이동만).
/// 백엔드 추상 경계 + API 구현체. _placeDisplayName forwarder 는
/// shared/l10n/place_labels.dart 의 placeDisplayName 과 동일해 직접 호출.

typedef LalaBackendFactory = LalaBackend Function(LalaAppConfig config);

abstract class LalaBackend {
  Future<LalaEnvelope<Map<String, dynamic>>> getHealth();

  Future<LalaEnvelope<LalaReadiness>> getReadiness();

  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces();

  /// Public Local Signals projection. [region] is a coarse canonical region
  /// id; this boundary never accepts device coordinates or author identity.
  Future<LalaEnvelope<Map<String, dynamic>>> getLocalSignals({
    String? region,
    String? placeId,
    String? kind,
    String sort = 'recent',
    String? cursor,
  });

  /// Governed system aggregates (weekly review-mention counts per place).
  /// System-aggregate read model — never user posts, never raw review data.
  /// [region] is a coarse canonical region id, mirroring [getLocalSignals].
  Future<LalaEnvelope<Map<String, dynamic>>> getLocalSignalAggregates({
    int weeks,
    int limit,
    String? placeId,
    String? category,
    String? region,
  });

  Future<LalaEnvelope<LalaWeather>> getWeather();

  Future<LalaEnvelope<LalaIntervention>> getIntervention();

  /// D-1: [selectedPlaceId] 를 주면 해당 카노니컬 장소를 플랜에 정확히 한 번
  /// 고정 배정 요청한다. 서버가 후보에서 해석하지 못하면 정직하게 실패한다.
  ///
  /// CP1: [preferenceContext] 를 주면 비민감 soft 선호를 플랜 생성 입력으로
  /// 보낸다. null 이면 키를 실어 보내지 않는다(기존 요청 직렬화 보존).
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({
    String? selectedPlaceId,
    LalaPlanPreferenceContext? preferenceContext,
  });

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

  /// V1 bounds-query (D4): prepare the viewport-rectangle params from
  /// [config.bounds]. Each value is null when bounds are absent so the call
  /// site falls back to the existing center+radius circle (state B2).
  ({double? swLat, double? swLng, double? neLat, double? neLng})
  _placesBounds() {
    final b = config.bounds;
    return (swLat: b?.swLat, swLng: b?.swLng, neLat: b?.neLat, neLng: b?.neLng);
  }

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
    final bounds = _placesBounds();
    // V1 bounds-query (D4): forward viewport rectangle when present; null → server
    // falls back to the center+radius circle (state B2).
    return _client.getPlaces(
      lat: config.lat,
      lng: config.lng,
      radiusM: config.radiusM,
      limit: config.placeLimit,
      category: config.category,
      lang: apiRequestLanguage(config.lang),
      includeScores: true,
      swLat: bounds.swLat,
      swLng: bounds.swLng,
      neLat: bounds.neLat,
      neLng: bounds.neLng,
    );
  }

  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getLocalSignals({
    String? region,
    String? placeId,
    String? kind,
    String sort = 'recent',
    String? cursor,
  }) {
    return _client.getLocalSignals(
      language: apiRequestLanguage(config.lang),
      region: region,
      placeId: placeId,
      kind: kind,
      sort: sort,
      cursor: cursor,
    );
  }

  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getLocalSignalAggregates({
    int weeks = 4,
    int limit = 20,
    String? placeId,
    String? category,
    String? region,
  }) {
    return _client.getLocalSignalAggregates(
      weeks: weeks,
      limit: limit,
      placeId: placeId,
      category: category,
      region: region,
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
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({
    String? selectedPlaceId,
    LalaPlanPreferenceContext? preferenceContext,
  }) {
    return _client.createDailyPlan(
      lat: config.lat,
      lng: config.lng,
      radiusM: config.radiusM,
      language: apiRequestLanguage(config.lang),
      selectedPlaceId: selectedPlaceId,
      preferenceContext: preferenceContext,
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
      language: apiRequestLanguage(config.lang),
      mode: mode,
    );
  }

  @override
  Future<LalaAudioResponse> createDocentAudio({required String script}) {
    return _client.createDocentAudio(
      script: script,
      language: apiRequestLanguage(config.lang),
    );
  }

  @override
  void close() {
    _client.close();
  }
}
