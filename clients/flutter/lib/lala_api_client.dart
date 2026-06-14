import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class LalaApiClient {
  LalaApiClient({
    required this.baseUri,
    this.bearerToken,
    this.apiKey,
    this.defaultTimeout = const Duration(seconds: 15),
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static const Duration healthTimeout = Duration(seconds: 3);
  static const Duration readinessTimeout = Duration(seconds: 3);
  static const Duration readTimeout = Duration(seconds: 5);
  static const Duration generationTimeout = Duration(seconds: 30);
  static const Duration audioTimeout = Duration(seconds: 30);
  static const Duration plannerTimeout = Duration(seconds: 20);

  final Uri baseUri;
  final String? bearerToken;
  final String? apiKey;
  final Duration defaultTimeout;
  final http.Client _httpClient;

  LalaAuthMode get authMode =>
      LalaAuthMode.fromCredentials(bearerToken: bearerToken, apiKey: apiKey);

  Future<LalaEnvelope<Map<String, dynamic>>> getHealth({
    String? requestId,
    Duration? timeout,
  }) {
    return _sendJson<Map<String, dynamic>>(
      'GET',
      '/healthz',
      requestId: requestId,
      timeout: timeout ?? healthTimeout,
    );
  }

  Future<LalaEnvelope<LalaReadiness>> getReadiness({
    String? requestId,
    Duration? timeout,
  }) {
    return _sendJson<LalaReadiness>(
      'GET',
      '/readyz',
      requestId: requestId,
      timeout: timeout ?? readinessTimeout,
      parseData: LalaReadiness.fromJsonObject,
    );
  }

  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces({
    double lat = 37.2636,
    double lng = 127.0286,
    int radiusM = 1000,
    String category = 'all',
    String lang = 'ko',
    String? requestId,
    Duration? timeout,
  }) {
    return _sendJson<LalaPlacesResponse>(
      'GET',
      '/api/v1/places',
      query: {
        'lat': '$lat',
        'lng': '$lng',
        'radius_m': '$radiusM',
        'category': category,
        'lang': lang,
      },
      requestId: requestId,
      timeout: timeout ?? readTimeout,
      parseData: LalaPlacesResponse.fromJsonObject,
    );
  }

  Future<LalaEnvelope<LalaWeather>> getWeather({
    double lat = 37.2636,
    double lng = 127.0286,
    bool force = false,
    String? requestId,
    Duration? timeout,
  }) {
    return _sendJson<LalaWeather>(
      'GET',
      '/api/v1/weather',
      query: {'lat': '$lat', 'lng': '$lng', 'force': '$force'},
      requestId: requestId,
      timeout: timeout ?? readTimeout,
      parseData: LalaWeather.fromJsonObject,
    );
  }

  Future<LalaEnvelope<LalaDocentScript>> createDocentScript({
    required String placeId,
    required String category,
    String language = 'ko',
    String mode = 'brief',
    String? requestId,
    Duration? timeout,
  }) {
    return _sendJson<LalaDocentScript>(
      'POST',
      '/api/v1/docents/script',
      body: {
        'place_id': placeId,
        'category': category,
        'language': language,
        'mode': mode,
      },
      requestId: requestId,
      timeout: timeout ?? generationTimeout,
      parseData: LalaDocentScript.fromJsonObject,
    );
  }

  Future<LalaAudioResponse> createDocentAudio({
    required String script,
    String language = 'ko',
    String? requestId,
    Duration? timeout,
  }) async {
    final response = await _withTimeout(
      _httpClient.post(
        _uri('/api/v1/docents/audio'),
        headers: _headers(
          requestId: requestId,
          contentType: 'application/json',
          accept: 'audio/mpeg, application/json',
        ),
        body: jsonEncode({'script': script, 'language': language}),
      ),
      timeout: timeout ?? audioTimeout,
      requestId: requestId,
    );

    final contentType = response.headers['content-type'] ?? '';
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        contentType.toLowerCase().contains('audio/mpeg')) {
      return LalaAudioResponse(
        bytes: response.bodyBytes,
        requestId: response.headers['x-request-id'],
        contentType: contentType,
        requestHash: response.headers['x-lala-request-hash'],
        cacheKey: response.headers['x-lala-cache-key'],
      );
    }

    throw _exceptionFromJsonResponse(response);
  }

  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({
    double lat = 37.2636,
    double lng = 127.0286,
    String language = 'ko',
    String? requestId,
    Duration? timeout,
  }) {
    return _sendJson<LalaDailyPlan>(
      'POST',
      '/api/v1/plans/daily',
      body: {'lat': lat, 'lng': lng, 'language': language},
      requestId: requestId,
      timeout: timeout ?? plannerTimeout,
      parseData: LalaDailyPlan.fromJsonObject,
    );
  }

  Future<LalaEnvelope<LalaIntervention>> getIntervention({
    double lat = 37.2636,
    double lng = 127.0286,
    int radiusM = 10000,
    String? requestId,
    Duration? timeout,
  }) {
    return _sendJson<LalaIntervention>(
      'GET',
      '/api/v1/plans/intervention',
      query: {'lat': '$lat', 'lng': '$lng', 'radius_m': '$radiusM'},
      requestId: requestId,
      timeout: timeout ?? readTimeout,
      parseData: LalaIntervention.fromJsonObject,
    );
  }

  void close() {
    _httpClient.close();
  }

  Future<LalaEnvelope<T>> _sendJson<T>(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    String? requestId,
    T Function(Object?)? parseData,
    Duration? timeout,
  }) async {
    final uri = _uri(path, query: query);
    final headers = _headers(
      requestId: requestId,
      contentType: body == null ? null : 'application/json',
      accept: 'application/json',
    );

    late Future<http.Response> responseFuture;
    switch (method) {
      case 'GET':
        responseFuture = _httpClient.get(uri, headers: headers);
        break;
      case 'POST':
        responseFuture = _httpClient.post(
          uri,
          headers: headers,
          body: jsonEncode(body),
        );
        break;
      default:
        throw ArgumentError('Unsupported method $method.');
    }
    final response = await _withTimeout(
      responseFuture,
      timeout: timeout ?? defaultTimeout,
      requestId: requestId,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _exceptionFromJsonResponse(response);
    }

    return _parseEnvelope<T>(response, parseData: parseData);
  }

  Future<T> _withTimeout<T>(
    Future<T> request, {
    required Duration timeout,
    String? requestId,
  }) async {
    try {
      return await request.timeout(timeout);
    } on TimeoutException {
      throw LalaApiException(
        code: 'REQUEST_TIMEOUT',
        message: 'LALA API request timed out.',
        statusCode: 0,
        retryable: true,
        requestId: requestId,
      );
    }
  }

  LalaEnvelope<T> _parseEnvelope<T>(
    http.Response response, {
    T Function(Object?)? parseData,
  }) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw LalaApiException(
        code: 'INVALID_RESPONSE',
        message: 'Expected a JSON object response.',
        statusCode: response.statusCode,
        retryable: false,
        requestId: response.headers['x-request-id'],
      );
    }

    final envelope = LalaEnvelope<T>.fromJson(
      decoded,
      statusCode: response.statusCode,
      responseRequestId: response.headers['x-request-id'],
      parseData: parseData,
    );
    if (!envelope.ok) {
      throw LalaApiException.fromEnvelope(envelope);
    }
    return envelope;
  }

  LalaApiException _exceptionFromJsonResponse(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final envelope = LalaEnvelope<Map<String, dynamic>>.fromJson(
          decoded,
          statusCode: response.statusCode,
          responseRequestId: response.headers['x-request-id'],
        );
        return LalaApiException.fromEnvelope(envelope);
      }
    } catch (_) {
      // Fall through to a generic exception. Do not include response body text.
    }

    return LalaApiException(
      code: 'HTTP_${response.statusCode}',
      message: 'LALA API request failed.',
      statusCode: response.statusCode,
      retryable: response.statusCode >= 500,
      requestId: response.headers['x-request-id'],
    );
  }

  Map<String, String> _headers({
    String? requestId,
    String? contentType,
    String accept = 'application/json',
  }) {
    final headers = <String, String>{'Accept': accept};
    final token = bearerToken?.trim();
    final key = apiKey?.trim();

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    } else if (key != null && key.isNotEmpty) {
      headers['X-API-Key'] = key;
    }
    if (contentType != null) {
      headers['Content-Type'] = contentType;
    }
    if (requestId != null && requestId.trim().isNotEmpty) {
      headers['X-Request-ID'] = requestId.trim();
    }
    return headers;
  }

  Uri _uri(String path, {Map<String, String>? query}) {
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    final routePath = path.startsWith('/') ? path : '/$path';
    final mergedPath = basePath == '/' ? routePath : '$basePath$routePath';
    return baseUri.replace(path: mergedPath, queryParameters: query);
  }
}

enum LalaAuthMode {
  none,
  apiKey,
  bearerToken,
  oauthJwt;

  static LalaAuthMode fromCredentials({String? bearerToken, String? apiKey}) {
    final token = bearerToken?.trim();
    if (token != null && token.isNotEmpty) {
      return _looksLikeJwt(token)
          ? LalaAuthMode.oauthJwt
          : LalaAuthMode.bearerToken;
    }

    final key = apiKey?.trim();
    if (key != null && key.isNotEmpty) {
      return LalaAuthMode.apiKey;
    }

    return LalaAuthMode.none;
  }

  String get label {
    switch (this) {
      case LalaAuthMode.none:
        return 'public only';
      case LalaAuthMode.apiKey:
        return 'migration key';
      case LalaAuthMode.bearerToken:
        return 'static bearer';
      case LalaAuthMode.oauthJwt:
        return 'oauth jwt';
    }
  }

  bool get hasClientAuth => this != LalaAuthMode.none;
}

bool _looksLikeJwt(String token) {
  final parts = token.split('.');
  if (parts.length != 3 || parts.any((part) => part.isEmpty)) {
    return false;
  }
  final base64UrlSegment = RegExp(r'^[A-Za-z0-9_-]+$');
  return parts.every(base64UrlSegment.hasMatch);
}

class LalaEnvelope<T> {
  const LalaEnvelope({
    required this.ok,
    required this.data,
    required this.meta,
    required this.error,
    required this.statusCode,
    required this.requestId,
  });

  final bool ok;
  final T? data;
  final Map<String, dynamic> meta;
  final LalaApiError? error;
  final int statusCode;
  final String? requestId;

  factory LalaEnvelope.fromJson(
    Map<String, dynamic> json, {
    required int statusCode,
    String? responseRequestId,
    T Function(Object?)? parseData,
  }) {
    final rawMeta = json['meta'];
    final meta =
        rawMeta is Map<String, dynamic> ? rawMeta : <String, dynamic>{};
    final rawData = json['data'];
    final data = parseData == null
        ? (rawData is T ? rawData : null)
        : parseData(rawData);
    final rawError = json['error'];

    return LalaEnvelope<T>(
      ok: json['ok'] == true,
      data: data,
      meta: meta,
      error: rawError is Map<String, dynamic>
          ? LalaApiError.fromJson(rawError)
          : null,
      statusCode: statusCode,
      requestId: (meta['request_id'] as String?) ?? responseRequestId,
    );
  }
}

class LalaPlacesResponse {
  const LalaPlacesResponse({
    required this.count,
    required this.places,
    required this.query,
    required this.source,
  });

  final int count;
  final List<LalaPlace> places;
  final LalaPlacesQuery query;
  final String source;

  static LalaPlacesResponse fromJsonObject(Object? value) {
    return LalaPlacesResponse.fromJson(_asMap(value));
  }

  factory LalaPlacesResponse.fromJson(Map<String, dynamic> json) {
    return LalaPlacesResponse(
      count: _asInt(json['count']),
      places: _asList(json['places']).map(LalaPlace.fromJsonObject).toList(),
      query: LalaPlacesQuery.fromJson(_asMap(json['query'])),
      source: _asString(json['source']),
    );
  }
}

class LalaPlacesQuery {
  const LalaPlacesQuery({
    required this.lat,
    required this.lng,
    required this.radiusM,
    required this.category,
    required this.language,
  });

  final double lat;
  final double lng;
  final int radiusM;
  final String category;
  final String language;

  factory LalaPlacesQuery.fromJson(Map<String, dynamic> json) {
    return LalaPlacesQuery(
      lat: _asDouble(json['lat']),
      lng: _asDouble(json['lng']),
      radiusM: _asInt(json['radius_m']),
      category: _asString(json['category']),
      language: _asString(json['language']),
    );
  }
}

class LalaPlace {
  const LalaPlace({
    required this.placeId,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    required this.address,
    required this.distanceM,
    required this.source,
    this.nameKo,
    this.nameEn,
    this.regionKo,
    this.regionEn,
    this.score,
  });

  final String placeId;
  final String name;
  final String category;
  final double lat;
  final double lng;
  final String address;
  final int distanceM;
  final String source;
  final String? nameKo;
  final String? nameEn;
  final String? regionKo;
  final String? regionEn;
  final LalaPlaceScore? score;

  static LalaPlace fromJsonObject(Object? value) {
    return LalaPlace.fromJson(_asMap(value));
  }

  factory LalaPlace.fromJson(Map<String, dynamic> json) {
    return LalaPlace(
      placeId: _asString(json['place_id']),
      name: _asString(json['name']),
      category: _asString(json['category']),
      lat: _asDouble(json['lat']),
      lng: _asDouble(json['lng']),
      address: _asString(json['address']),
      distanceM: _asInt(json['distance_m']),
      source: _asString(json['source']),
      nameKo: _asOptionalString(json['name_ko']),
      nameEn: _asOptionalString(json['name_en']),
      regionKo: _asOptionalString(json['region_ko']),
      regionEn: _asOptionalString(json['region_en']),
      score: json['score'] is Map<String, dynamic>
          ? LalaPlaceScore.fromJson(_asMap(json['score']))
          : null,
    );
  }
}

class LalaPlaceScore {
  const LalaPlaceScore({
    required this.finalScore,
    required this.formulaVersion,
    required this.components,
    required this.dataBasis,
    required this.features,
  });

  final double finalScore;
  final String formulaVersion;
  final LalaPlaceScoreComponents components;
  final String dataBasis;
  final Map<String, dynamic> features;

  int get percent => (finalScore * 100).round();

  factory LalaPlaceScore.fromJson(Map<String, dynamic> json) {
    return LalaPlaceScore(
      finalScore: _asDouble(json['final_score']),
      formulaVersion: _asString(json['formula_version']),
      components: LalaPlaceScoreComponents.fromJson(_asMap(json['components'])),
      dataBasis: _asString(json['data_basis']),
      features: _asMap(json['features']),
    );
  }
}

class LalaPlaceScoreComponents {
  const LalaPlaceScoreComponents({
    required this.localSpendingScore,
    required this.demandDispersionScore,
    required this.weatherFitScore,
    required this.reviewQualityScore,
    required this.cultureRelevanceScore,
  });

  final double? localSpendingScore;
  final double? demandDispersionScore;
  final double? weatherFitScore;
  final double? reviewQualityScore;
  final double? cultureRelevanceScore;

  factory LalaPlaceScoreComponents.fromJson(Map<String, dynamic> json) {
    return LalaPlaceScoreComponents(
      localSpendingScore: _asOptionalDouble(json['local_spending_score']),
      demandDispersionScore: _asOptionalDouble(json['demand_dispersion_score']),
      weatherFitScore: _asOptionalDouble(json['weather_fit_score']),
      reviewQualityScore: _asOptionalDouble(json['review_quality_score']),
      cultureRelevanceScore: _asOptionalDouble(json['culture_relevance_score']),
    );
  }
}

class LalaWeather {
  const LalaWeather({
    required this.lat,
    required this.lng,
    required this.temp,
    required this.icon,
    required this.dust,
    required this.forecast,
    required this.outdoorStatus,
    required this.force,
    required this.source,
    this.location,
    this.recordTime,
    this.locationMatch,
  });

  final double lat;
  final double lng;
  final String temp;
  final String icon;
  final LalaDust dust;
  final List<LalaForecastItem> forecast;
  final String outdoorStatus;
  final bool force;
  final String source;
  final String? location;
  final String? recordTime;
  final bool? locationMatch;

  static LalaWeather fromJsonObject(Object? value) {
    return LalaWeather.fromJson(_asMap(value));
  }

  factory LalaWeather.fromJson(Map<String, dynamic> json) {
    return LalaWeather(
      lat: _asDouble(json['lat']),
      lng: _asDouble(json['lng']),
      temp: _asString(json['temp']),
      icon: _asString(json['icon']),
      dust: LalaDust.fromJson(_asMap(json['dust'])),
      forecast: _asList(
        json['forecast'],
      ).map(LalaForecastItem.fromJsonObject).toList(),
      outdoorStatus: _asString(json['outdoor_status']),
      force: _asBool(json['force']),
      source: _asString(json['source']),
      location: _asOptionalString(json['location']),
      recordTime: _asOptionalString(json['record_time']),
      locationMatch: _asOptionalBool(json['location_match']),
    );
  }
}

class LalaDust {
  const LalaDust({
    required this.pm10,
    required this.pm25,
    required this.grade,
    required this.gradeKo,
  });

  final String pm10;
  final String pm25;
  final String grade;
  final String gradeKo;

  factory LalaDust.fromJson(Map<String, dynamic> json) {
    return LalaDust(
      pm10: _asString(json['pm10']),
      pm25: _asString(json['pm25']),
      grade: _asString(json['grade']),
      gradeKo: _asString(json['grade_ko']),
    );
  }
}

class LalaForecastItem {
  const LalaForecastItem({
    required this.time,
    required this.temp,
    required this.icon,
  });

  final String time;
  final String temp;
  final String icon;

  static LalaForecastItem fromJsonObject(Object? value) {
    return LalaForecastItem.fromJson(_asMap(value));
  }

  factory LalaForecastItem.fromJson(Map<String, dynamic> json) {
    return LalaForecastItem(
      time: _asString(json['time']),
      temp: _asString(json['temp']),
      icon: _asString(json['icon']),
    );
  }
}

class LalaDocentScript {
  const LalaDocentScript({
    required this.placeId,
    required this.category,
    required this.language,
    required this.mode,
    required this.script,
    required this.source,
    required this.requestHash,
    required this.cacheKey,
    this.generatedAt,
    this.ttlSec,
  });

  final String placeId;
  final String category;
  final String language;
  final String mode;
  final String script;
  final String source;
  final String requestHash;
  final String cacheKey;
  final String? generatedAt;
  final int? ttlSec;

  static LalaDocentScript fromJsonObject(Object? value) {
    return LalaDocentScript.fromJson(_asMap(value));
  }

  factory LalaDocentScript.fromJson(Map<String, dynamic> json) {
    return LalaDocentScript(
      placeId: _asString(json['place_id']),
      category: _asString(json['category']),
      language: _asString(json['language']),
      mode: _asString(json['mode']),
      script: _asString(json['script']),
      source: _asString(json['source']),
      requestHash: _asString(json['request_hash']),
      cacheKey: _asString(json['cache_key']),
      generatedAt: _asOptionalString(json['generated_at']),
      ttlSec: _asOptionalInt(json['ttl_sec']),
    );
  }
}

class LalaDailyPlan {
  const LalaDailyPlan({
    required this.language,
    required this.center,
    required this.weather,
    required this.slots,
    required this.source,
    required this.requestHash,
    required this.cacheKey,
  });

  final String language;
  final LalaCoordinate center;
  final LalaWeather weather;
  final List<LalaPlanSlot> slots;
  final String source;
  final String requestHash;
  final String cacheKey;

  static LalaDailyPlan fromJsonObject(Object? value) {
    return LalaDailyPlan.fromJson(_asMap(value));
  }

  factory LalaDailyPlan.fromJson(Map<String, dynamic> json) {
    return LalaDailyPlan(
      language: _asString(json['language']),
      center: LalaCoordinate.fromJson(_asMap(json['center'])),
      weather: LalaWeather.fromJson(_asMap(json['weather'])),
      slots: _asList(json['slots']).map(LalaPlanSlot.fromJsonObject).toList(),
      source: _asString(json['source']),
      requestHash: _asString(json['request_hash']),
      cacheKey: _asString(json['cache_key']),
    );
  }
}

class LalaPlanSlot {
  const LalaPlanSlot({
    required this.period,
    required this.title,
    this.place,
    this.weatherHint,
  });

  final String period;
  final String title;
  final LalaPlace? place;
  final String? weatherHint;

  static LalaPlanSlot fromJsonObject(Object? value) {
    return LalaPlanSlot.fromJson(_asMap(value));
  }

  factory LalaPlanSlot.fromJson(Map<String, dynamic> json) {
    final rawPlace = json['place'];
    return LalaPlanSlot(
      period: _asString(json['period']),
      title: _asString(json['title']),
      place: rawPlace is Map<String, dynamic>
          ? LalaPlace.fromJson(rawPlace)
          : null,
      weatherHint: _asOptionalString(json['weather_hint']),
    );
  }
}

class LalaIntervention {
  const LalaIntervention({
    required this.center,
    required this.radiusM,
    required this.shouldIntervene,
    required this.reason,
    required this.recommendedAction,
    required this.source,
  });

  final LalaCoordinate center;
  final int radiusM;
  final bool shouldIntervene;
  final String reason;
  final String recommendedAction;
  final String source;

  static LalaIntervention fromJsonObject(Object? value) {
    return LalaIntervention.fromJson(_asMap(value));
  }

  factory LalaIntervention.fromJson(Map<String, dynamic> json) {
    return LalaIntervention(
      center: LalaCoordinate.fromJson(_asMap(json['center'])),
      radiusM: _asInt(json['radius_m']),
      shouldIntervene: _asBool(json['should_intervene']),
      reason: _asString(json['reason']),
      recommendedAction: _asString(json['recommended_action']),
      source: _asString(json['source']),
    );
  }
}

class LalaCoordinate {
  const LalaCoordinate({required this.lat, required this.lng});

  final double lat;
  final double lng;

  factory LalaCoordinate.fromJson(Map<String, dynamic> json) {
    return LalaCoordinate(
      lat: _asDouble(json['lat']),
      lng: _asDouble(json['lng']),
    );
  }
}

class LalaApiError {
  const LalaApiError({
    required this.code,
    required this.message,
    required this.retryable,
    this.details,
  });

  final String code;
  final String message;
  final bool retryable;
  final Object? details;

  factory LalaApiError.fromJson(Map<String, dynamic> json) {
    return LalaApiError(
      code: json['code'] as String? ?? 'UNKNOWN',
      message: json['message'] as String? ?? 'LALA API request failed.',
      retryable: json['retryable'] == true,
      details: json['details'],
    );
  }
}

class LalaApiException implements Exception {
  const LalaApiException({
    required this.code,
    required this.message,
    required this.statusCode,
    required this.retryable,
    this.requestId,
    this.details,
  });

  final String code;
  final String message;
  final int statusCode;
  final bool retryable;
  final String? requestId;
  final Object? details;

  factory LalaApiException.fromEnvelope(LalaEnvelope<Object?> envelope) {
    final error = envelope.error;
    return LalaApiException(
      code: error?.code ?? 'HTTP_${envelope.statusCode}',
      message: error?.message ?? 'LALA API request failed.',
      statusCode: envelope.statusCode,
      retryable: error?.retryable ?? envelope.statusCode >= 500,
      requestId: envelope.requestId,
      details: error?.details,
    );
  }

  @override
  String toString() {
    final id = requestId == null ? '' : ' request_id=$requestId';
    return 'LalaApiException($statusCode $code retryable=$retryable$id): $message';
  }
}

class LalaReadiness {
  const LalaReadiness({
    required this.status,
    required this.checks,
    required this.mode,
  });

  final String status;
  final Map<String, String> checks;
  final LalaRuntimeMode mode;

  static LalaReadiness fromJsonObject(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected /readyz data object.');
    }
    return LalaReadiness.fromJson(value);
  }

  factory LalaReadiness.fromJson(Map<String, dynamic> json) {
    final rawChecks = json['checks'];
    final checks = <String, String>{};
    if (rawChecks is Map<String, dynamic>) {
      for (final entry in rawChecks.entries) {
        final value = entry.value;
        if (value is String) {
          checks[entry.key] = value;
        }
      }
    }

    final rawMode = json['mode'];
    return LalaReadiness(
      status: json['status'] as String? ?? 'unknown',
      checks: checks,
      mode: rawMode is Map<String, dynamic>
          ? LalaRuntimeMode.fromJson(rawMode)
          : LalaRuntimeMode.unknown(),
    );
  }
}

class LalaRuntimeMode {
  const LalaRuntimeMode({
    required this.overall,
    required this.data,
    required this.ai,
    required this.speech,
    required this.worker,
  });

  final String overall;
  final String data;
  final String ai;
  final String speech;
  final String worker;

  factory LalaRuntimeMode.fromJson(Map<String, dynamic> json) {
    return LalaRuntimeMode(
      overall: json['overall'] as String? ?? 'unknown',
      data: json['data'] as String? ?? 'unknown',
      ai: json['ai'] as String? ?? 'unknown',
      speech: json['speech'] as String? ?? 'unknown',
      worker: json['worker'] as String? ?? 'unknown',
    );
  }

  factory LalaRuntimeMode.unknown() {
    return const LalaRuntimeMode(
      overall: 'unknown',
      data: 'unknown',
      ai: 'unknown',
      speech: 'unknown',
      worker: 'unknown',
    );
  }

  bool get isSkeleton => overall == 'skeleton';
  bool get isDbBacked => data == 'db-backed';
  bool get usesLiveAzure => ai == 'live-azure' || speech == 'live-azure';
  bool get isDegraded => overall == 'degraded';
}

class LalaAudioResponse {
  const LalaAudioResponse({
    required this.bytes,
    required this.requestId,
    required this.contentType,
    required this.requestHash,
    required this.cacheKey,
  });

  final Uint8List bytes;
  final String? requestId;
  final String contentType;
  final String? requestHash;
  final String? cacheKey;
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry('$key', value));
  }
  return <String, dynamic>{};
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return value.cast<Object?>();
  }
  return const <Object?>[];
}

String _asString(Object? value) {
  return value == null ? '' : '$value';
}

String? _asOptionalString(Object? value) {
  return value == null ? null : '$value';
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse('$value') ?? 0;
}

int? _asOptionalInt(Object? value) {
  if (value == null) {
    return null;
  }
  return _asInt(value);
}

double _asDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse('$value') ?? 0;
}

double? _asOptionalDouble(Object? value) {
  if (value == null) {
    return null;
  }
  return _asDouble(value);
}

bool _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  final normalized = '$value'.toLowerCase().trim();
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}

bool? _asOptionalBool(Object? value) {
  if (value == null) {
    return null;
  }
  return _asBool(value);
}
