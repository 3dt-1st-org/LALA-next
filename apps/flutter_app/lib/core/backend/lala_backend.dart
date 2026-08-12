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

  /// Public Local Signals projection. [region] is a coarse canonical region
  /// id; this boundary never accepts device coordinates or author identity.
  Future<LalaEnvelope<Map<String, dynamic>>> getLocalSignals({
    String? region,
    String? placeId,
    String? kind,
    String sort = 'recent',
    String? cursor,
  });

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
    // Bounds are prepared here; forwarding is blocked on Lane A's regenerated
    // client (PR #133). The discard keeps the wiring live without an unused
    // local while the four named args are not yet on the generated signature.
    final _ = _placesBounds();
    // TODO(bounds-LaneB): forward swLat/swLng/neLat/neLng to _client.getPlaces once Lane A's regenerated client lands (pinned names sw_lat→swLat, sw_lng→swLng, ne_lat→neLat, ne_lng→neLng).
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
  Future<LalaEnvelope<Map<String, dynamic>>> getLocalSignals({
    String? region,
    String? placeId,
    String? kind,
    String sort = 'recent',
    String? cursor,
  }) {
    return _client.getLocalSignals(
      language: config.lang == 'en' ? 'en' : 'ko',
      region: region,
      placeId: placeId,
      kind: kind,
      sort: sort,
      cursor: cursor,
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
