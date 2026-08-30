import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../lala_map_models.dart';

/// C3 최종: main.dart 에서 이관. 본문 불변(이동만).
/// 앱 시작 환경설정(API base URI, 인증, 기본 쿼리 파라미터)을 담는 불변 값 객체.
class LalaAppConfig {
  const LalaAppConfig({
    required this.baseUri,
    this.bearerToken = '',
    this.apiKey = '',
    this.naverMapClientId = '',
    this.lat = 37.2636,
    this.lng = 127.0286,
    this.radiusM = 3000,
    this.placeLimit = 60,
    this.category = 'all',
    this.lang = 'ko',
    this.requireLocationStartConfirmation = false,
    this.accessTokenProvider,
    this.bounds,
  });

  const LalaAppConfig.fromEnvironment()
    : baseUri = const String.fromEnvironment(
        'LALA_API_BASE_URL',
        defaultValue: 'https://api.lala-next.cloud',
      ),
      bearerToken = const String.fromEnvironment('LALA_API_BEARER_TOKEN'),
      apiKey = const String.fromEnvironment('LALA_IOS_API_KEY'),
      naverMapClientId = const String.fromEnvironment('NAVER_MAP_CLIENT_ID'),
      lat = 37.2636,
      lng = 127.0286,
      radiusM = 3000,
      placeLimit = 60,
      category = const String.fromEnvironment(
        'LALA_PLACE_CATEGORY',
        defaultValue: 'all',
      ),
      lang = const String.fromEnvironment(
        'LALA_UI_LANGUAGE',
        defaultValue: 'ko',
      ),
      requireLocationStartConfirmation = const bool.fromEnvironment(
        'LALA_REQUIRE_LOCATION_START_CONFIRMATION',
        defaultValue: false,
      ),
      accessTokenProvider = null,
      bounds = null;

  final String baseUri;
  final String bearerToken;
  final String apiKey;
  final String naverMapClientId;
  final double lat;
  final double lng;
  final int radiusM;
  final int placeLimit;
  final String category;
  final String lang;
  final bool requireLocationStartConfirmation;
  final LalaAccessTokenProvider? accessTokenProvider;

  // V1 bounds-query (D4): optional viewport rectangle threaded from the camera
  // into the /places call. null → existing center+radius circle (fallback B2).
  final LalaMapBounds? bounds;

  bool get hasAuth => bearerToken.trim().isNotEmpty || apiKey.trim().isNotEmpty;
  LalaAuthMode get authMode =>
      LalaAuthMode.fromCredentials(bearerToken: bearerToken, apiKey: apiKey);

  LalaAppConfig copyWith({
    String? baseUri,
    String? bearerToken,
    String? apiKey,
    String? naverMapClientId,
    double? lat,
    double? lng,
    int? radiusM,
    int? placeLimit,
    String? category,
    String? lang,
    bool? requireLocationStartConfirmation,
    LalaAccessTokenProvider? accessTokenProvider,
    LalaMapBounds? bounds,
  }) {
    return LalaAppConfig(
      baseUri: baseUri ?? this.baseUri,
      bearerToken: bearerToken ?? this.bearerToken,
      apiKey: apiKey ?? this.apiKey,
      naverMapClientId: naverMapClientId ?? this.naverMapClientId,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      radiusM: radiusM ?? this.radiusM,
      placeLimit: placeLimit ?? this.placeLimit,
      category: category ?? this.category,
      lang: lang ?? this.lang,
      requireLocationStartConfirmation:
          requireLocationStartConfirmation ??
          this.requireLocationStartConfirmation,
      accessTokenProvider: accessTokenProvider ?? this.accessTokenProvider,
      bounds: bounds ?? this.bounds,
    );
  }
}
