import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:lala_next_flutter_client_generated/lala_next_flutter_client_generated.dart';

typedef LalaAccessTokenProvider = Future<String?> Function();

/// Reference LALA API client.
///
/// Transport is powered by the generated `dart-dio` client's [Dio] engine and
/// its [standardSerializers] registry (used to serialize the simple POST
/// request bodies that have no enum fields). Response decoding deliberately
/// reuses this client's hand-made, defensively-loose parsers instead of the
/// generated `built_value` response models: those models declare non-nullable
/// fields and closed enums (e.g. `PlaceScoreComponents.reviewQualityScore` is a
/// non-nullable `double`, `ApiMeta.requestId` is required, `ReadinessChecks`
/// has 29 required enum fields) that cannot represent this contract's nullable,
/// stringly-typed wire shape. Routing responses through them would discard
/// information (notably `MeData.createdAt`, parsed by the generator as
/// `DateTime` and not reconstructable to the original ISO string). The request
/// wire (paths, query encoding, Dio auth/interceptor hooks) therefore comes
/// from the generated client surface, while the response adapter maps the raw
/// decoded JSON into the unchanged public model classes.
class LalaApiClient {
  LalaApiClient({
    required this.baseUri,
    this.bearerToken,
    this.apiKey,
    this.accessTokenProvider,
    this.defaultTimeout = const Duration(seconds: 15),
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    _dio.options.validateStatus = (_) => true;
    _dio.options.receiveTimeout = null;
    _dio.options.connectTimeout = null;
    _dio.options.sendTimeout = null;
  }

  static const Duration healthTimeout = Duration(seconds: 3);
  static const Duration readinessTimeout = Duration(seconds: 3);
  static const Duration readTimeout = Duration(seconds: 8);
  static const Duration generationTimeout = Duration(seconds: 24);
  static const Duration audioTimeout = Duration(seconds: 24);
  static const Duration plannerTimeout = Duration(seconds: 16);

  final Uri baseUri;
  final String? bearerToken;
  final String? apiKey;
  final LalaAccessTokenProvider? accessTokenProvider;
  final Duration defaultTimeout;
  final Dio _dio;
  final Serializers _serializers = standardSerializers;

  LalaAuthMode get authMode =>
      LalaAuthMode.fromCredentials(bearerToken: bearerToken, apiKey: apiKey);

  bool get hasDynamicAuth => accessTokenProvider != null;

  Future<LalaEnvelope<Map<String, dynamic>>> getHealth({
    String? requestId,
    Duration? timeout,
  }) async {
    final resp = await _request(
      'GET',
      '/healthz',
      requestId: requestId,
      timeout: timeout ?? healthTimeout,
      includeAuth: false,
    );
    return _envelopeFromResponse<Map<String, dynamic>>(resp);
  }

  Future<LalaEnvelope<LalaReadiness>> getReadiness({
    String? requestId,
    Duration? timeout,
  }) async {
    final resp = await _request(
      'GET',
      '/readyz',
      requestId: requestId,
      timeout: timeout ?? readinessTimeout,
      includeAuth: false,
    );
    return _envelopeFromResponse<LalaReadiness>(
      resp,
      parseData: LalaReadiness.fromJsonObject,
    );
  }

  Future<LalaEnvelope<LalaMe>> getMe({
    String? requestId,
    Duration? timeout,
  }) async {
    final resp = await _request(
      'GET',
      '/api/v1/me',
      requestId: requestId,
      timeout: timeout ?? readTimeout,
    );
    return _envelopeFromResponse<LalaMe>(
      resp,
      parseData: LalaMe.fromJsonObject,
    );
  }

  Future<void> deleteMe({
    required String confirmation,
    String? requestId,
    Duration? timeout,
  }) async {
    final resp = await _request(
      'DELETE',
      '/api/v1/me',
      body: {'confirmation': confirmation},
      requestId: requestId,
      timeout: timeout ?? readTimeout,
      contentType: 'application/json',
    );
    final status = resp.statusCode ?? 0;
    final reqId = resp.headers.value('x-request-id');
    if (status == 204) return;

    final raw = resp.data;
    if (raw is Map<String, dynamic>) {
      final envelope = LalaEnvelope<Map<String, dynamic>>.fromJson(
        raw,
        statusCode: status,
        responseRequestId: reqId,
      );
      if (!envelope.ok) {
        throw LalaApiException.fromEnvelope(envelope);
      }
    }

    throw LalaApiException(
      code: 'INVALID_RESPONSE',
      message: 'Unexpected response from LALA API.',
      statusCode: status,
      retryable: false,
      requestId: reqId,
    );
  }

  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces({
    required double lat,
    required double lng,
    int radiusM = 1000,
    int limit = 60,
    String category = 'all',
    String lang = 'ko',
    bool includeScores = false,
    String? requestId,
    Duration? timeout,
  }) async {
    final resp = await _request(
      'GET',
      '/api/v1/places',
      query: {
        'lat': '$lat',
        'lng': '$lng',
        'radius_m': '$radiusM',
        'limit': '$limit',
        'category': category,
        'lang': lang,
        'include_scores': '$includeScores',
      },
      requestId: requestId,
      timeout: timeout ?? readTimeout,
    );
    return _envelopeFromResponse<LalaPlacesResponse>(
      resp,
      parseData: LalaPlacesResponse.fromJsonObject,
    );
  }

  Future<LalaEnvelope<LalaWeather>> getWeather({
    required double lat,
    required double lng,
    bool force = false,
    String? requestId,
    Duration? timeout,
  }) async {
    final resp = await _request(
      'GET',
      '/api/v1/weather',
      query: {'lat': '$lat', 'lng': '$lng', 'force': '$force'},
      requestId: requestId,
      timeout: timeout ?? readTimeout,
    );
    return _envelopeFromResponse<LalaWeather>(
      resp,
      parseData: LalaWeather.fromJsonObject,
    );
  }

  Future<LalaEnvelope<LalaDocentScript>> createDocentScript({
    required String placeId,
    String? placeName,
    String? address,
    String? regionKo,
    String? regionEn,
    int? distanceM,
    String? source,
    String? upstreamSource,
    double? finalScore,
    double? localSpendingScore,
    double? smallMerchantFitScore,
    double? demandDispersionScore,
    double? weatherFitScore,
    double? cultureRelevanceScore,
    String? weatherTemp,
    String? weatherIcon,
    String? weatherOutdoorStatus,
    String? dustGrade,
    String? dustPm10,
    String? dustPm25,
    String? dustPm10Grade,
    String? dustPm25Grade,
    required String category,
    String language = 'ko',
    String mode = 'brief',
    String? requestId,
    Duration? timeout,
  }) async {
    // `category` is a closed enum in the generated `DocentScriptRequest`, so
    // the body is serialized from a literal map to preserve the loose string
    // contract and the conditional/trimmed-field semantics.
    final resp = await _request(
      'POST',
      '/api/v1/docents/script',
      body: {
        'place_id': placeId,
        if ((placeName ?? '').trim().isNotEmpty)
          'place_name': placeName!.trim(),
        if ((address ?? '').trim().isNotEmpty) 'address': address!.trim(),
        if ((regionKo ?? '').trim().isNotEmpty) 'region_ko': regionKo!.trim(),
        if ((regionEn ?? '').trim().isNotEmpty) 'region_en': regionEn!.trim(),
        if (distanceM != null && distanceM >= 0) 'distance_m': distanceM,
        if ((source ?? '').trim().isNotEmpty) 'source': source!.trim(),
        if ((upstreamSource ?? '').trim().isNotEmpty)
          'upstream_source': upstreamSource!.trim(),
        if (_validScore(finalScore)) 'final_score': finalScore,
        if (_validScore(localSpendingScore))
          'local_spending_score': localSpendingScore,
        if (_validScore(smallMerchantFitScore))
          'small_merchant_fit_score': smallMerchantFitScore,
        if (_validScore(demandDispersionScore))
          'demand_dispersion_score': demandDispersionScore,
        if (_validScore(weatherFitScore)) 'weather_fit_score': weatherFitScore,
        if (_validScore(cultureRelevanceScore))
          'culture_relevance_score': cultureRelevanceScore,
        if ((weatherTemp ?? '').trim().isNotEmpty)
          'weather_temp': weatherTemp!.trim(),
        if ((weatherIcon ?? '').trim().isNotEmpty)
          'weather_icon': weatherIcon!.trim(),
        if ((weatherOutdoorStatus ?? '').trim().isNotEmpty)
          'weather_outdoor_status': weatherOutdoorStatus!.trim(),
        if ((dustGrade ?? '').trim().isNotEmpty)
          'dust_grade': dustGrade!.trim(),
        if ((dustPm10 ?? '').trim().isNotEmpty) 'dust_pm10': dustPm10!.trim(),
        if ((dustPm25 ?? '').trim().isNotEmpty) 'dust_pm25': dustPm25!.trim(),
        if ((dustPm10Grade ?? '').trim().isNotEmpty)
          'dust_pm10_grade': dustPm10Grade!.trim(),
        if ((dustPm25Grade ?? '').trim().isNotEmpty)
          'dust_pm25_grade': dustPm25Grade!.trim(),
        'category': category,
        'language': language,
        'mode': mode,
      },
      requestId: requestId,
      timeout: timeout ?? generationTimeout,
      contentType: 'application/json',
    );
    return _envelopeFromResponse<LalaDocentScript>(
      resp,
      parseData: LalaDocentScript.fromJsonObject,
    );
  }

  Future<LalaAudioResponse> createDocentAudio({
    required String script,
    String language = 'ko',
    String? requestId,
    Duration? timeout,
  }) async {
    final request = DocentAudioRequestBuilder()
      ..script = script
      ..language = language;
    final body = _serializers.serialize(
      request.build(),
      specifiedType: const FullType(DocentAudioRequest),
    );
    final resp = await _request(
      'POST',
      '/api/v1/docents/audio',
      body: body,
      requestId: requestId,
      timeout: timeout ?? audioTimeout,
      responseType: ResponseType.bytes,
      accept: 'audio/mpeg, application/json',
      contentType: 'application/json',
    );
    final status = resp.statusCode ?? 0;
    final contentType = resp.headers.value('content-type') ?? '';
    if (status >= 200 &&
        status < 300 &&
        contentType.toLowerCase().contains('audio/mpeg')) {
      return LalaAudioResponse(
        bytes: _asBytes(resp.data),
        requestId: resp.headers.value('x-request-id'),
        contentType: contentType,
        requestHash: resp.headers.value('x-lala-request-hash'),
        cacheKey: resp.headers.value('x-lala-cache-key'),
      );
    }
    throw _exceptionFromBytesResponse(resp);
  }

  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({
    required double lat,
    required double lng,
    int radiusM = 3000,
    String language = 'ko',
    String? requestId,
    Duration? timeout,
  }) async {
    final request = DailyPlanRequestBuilder()
      ..lat = lat
      ..lng = lng
      ..radiusM = radiusM
      ..language = language;
    final body = _serializers.serialize(
      request.build(),
      specifiedType: const FullType(DailyPlanRequest),
    );
    final resp = await _request(
      'POST',
      '/api/v1/plans/daily',
      body: body,
      requestId: requestId,
      timeout: timeout ?? plannerTimeout,
      contentType: 'application/json',
    );
    return _envelopeFromResponse<LalaDailyPlan>(
      resp,
      parseData: LalaDailyPlan.fromJsonObject,
    );
  }

  Future<LalaEnvelope<LalaIntervention>> getIntervention({
    required double lat,
    required double lng,
    int radiusM = 10000,
    String? requestId,
    Duration? timeout,
  }) async {
    final resp = await _request(
      'GET',
      '/api/v1/plans/intervention',
      query: {'lat': '$lat', 'lng': '$lng', 'radius_m': '$radiusM'},
      requestId: requestId,
      timeout: timeout ?? readTimeout,
    );
    return _envelopeFromResponse<LalaIntervention>(
      resp,
      parseData: LalaIntervention.fromJsonObject,
    );
  }

  /// ONMU P3b: 커뮤니티 게시판 — 목록 조회(페이지네이션). 클라이언트 인증.
  Future<LalaEnvelope<CommunityPostsResponse>> getCommunityPosts({
    int limit = 20,
    int offset = 0,
    String? requestId,
    Duration? timeout,
  }) async {
    final resp = await _request(
      'GET',
      '/api/v1/community/posts',
      query: {'limit': '$limit', 'offset': '$offset'},
      requestId: requestId,
      timeout: timeout ?? readTimeout,
    );
    return _envelopeFromResponse<CommunityPostsResponse>(
      resp,
      parseData: CommunityPostsResponse.fromJsonObject,
    );
  }

  /// ONMU P3b: 게시글 작성(OAuth). 본문은 단순 JSON 맵(title/body/tags).
  Future<LalaEnvelope<CommunityPost>> createCommunityPost({
    required String title,
    required String body,
    List<String>? tags,
    String? requestId,
    Duration? timeout,
  }) async {
    final payload = <String, dynamic>{
      'title': title,
      'body': body,
    };
    if (tags != null && tags.isNotEmpty) {
      payload['tags'] = tags;
    }
    final resp = await _request(
      'POST',
      '/api/v1/community/posts',
      body: payload,
      requestId: requestId,
      timeout: timeout ?? readTimeout,
      contentType: 'application/json',
    );
    return _envelopeFromResponse<CommunityPost>(
      resp,
      parseData: CommunityPost.fromJsonObject,
    );
  }

  /// ONMU P3b: 단일 게시글 상세 조회.
  Future<LalaEnvelope<CommunityPost>> getCommunityPost({
    required String postId,
    String? requestId,
    Duration? timeout,
  }) async {
    final resp = await _request(
      'GET',
      '/api/v1/community/posts/$postId',
      requestId: requestId,
      timeout: timeout ?? readTimeout,
    );
    return _envelopeFromResponse<CommunityPost>(
      resp,
      parseData: CommunityPost.fromJsonObject,
    );
  }

  /// ONMU P3b: 게시글 댓글 목록 조회.
  Future<LalaEnvelope<CommunityCommentsResponse>> getCommunityComments({
    required String postId,
    int limit = 50,
    int offset = 0,
    String? requestId,
    Duration? timeout,
  }) async {
    final resp = await _request(
      'GET',
      '/api/v1/community/posts/$postId/comments',
      query: {'limit': '$limit', 'offset': '$offset'},
      requestId: requestId,
      timeout: timeout ?? readTimeout,
    );
    return _envelopeFromResponse<CommunityCommentsResponse>(
      resp,
      parseData: CommunityCommentsResponse.fromJsonObject,
    );
  }

  /// ONMU P3b: 댓글 작성(OAuth).
  Future<LalaEnvelope<CommunityComment>> createCommunityComment({
    required String postId,
    required String body,
    String? requestId,
    Duration? timeout,
  }) async {
    final resp = await _request(
      'POST',
      '/api/v1/community/posts/$postId/comments',
      body: <String, dynamic>{'body': body},
      requestId: requestId,
      timeout: timeout ?? readTimeout,
      contentType: 'application/json',
    );
    return _envelopeFromResponse<CommunityComment>(
      resp,
      parseData: CommunityComment.fromJsonObject,
    );
  }

  /// ONMU P3b: 게시글 좋아요 토글(OAuth). 응답: post_id/liked/like_count.
  Future<LalaEnvelope<CommunityLikeState>> toggleCommunityLike({
    required String postId,
    String? requestId,
    Duration? timeout,
  }) async {
    final resp = await _request(
      'POST',
      '/api/v1/community/posts/$postId/like',
      requestId: requestId,
      timeout: timeout ?? readTimeout,
      contentType: 'application/json',
    );
    return _envelopeFromResponse<CommunityLikeState>(
      resp,
      parseData: CommunityLikeState.fromJsonObject,
    );
  }

  /// ONMU P3c: 채팅방 목록 조회(페이지네이션). 클라이언트 인증.
  Future<LalaEnvelope<ChatRoomsResponse>> getChatRooms({
    int limit = 20,
    int offset = 0,
    String? requestId,
    Duration? timeout,
  }) async {
    final resp = await _request(
      'GET',
      '/api/v1/community/chat/rooms',
      query: {'limit': '$limit', 'offset': '$offset'},
      requestId: requestId,
      timeout: timeout ?? readTimeout,
    );
    return _envelopeFromResponse<ChatRoomsResponse>(
      resp,
      parseData: ChatRoomsResponse.fromJsonObject,
    );
  }

  /// ONMU P3c: 채팅방 생성(OAuth). 본문은 단순 JSON 맵(name).
  Future<LalaEnvelope<ChatRoom>> createChatRoom({
    required String name,
    String? requestId,
    Duration? timeout,
  }) async {
    final resp = await _request(
      'POST',
      '/api/v1/community/chat/rooms',
      body: <String, dynamic>{'name': name},
      requestId: requestId,
      timeout: timeout ?? readTimeout,
      contentType: 'application/json',
    );
    return _envelopeFromResponse<ChatRoom>(
      resp,
      parseData: ChatRoom.fromJsonObject,
    );
  }

  /// ONMU P3c: 채팅방 메시지 목록 조회(페이지네이션).
  Future<LalaEnvelope<ChatMessagesResponse>> getChatMessages({
    required String roomId,
    int limit = 50,
    int offset = 0,
    String? requestId,
    Duration? timeout,
  }) async {
    final resp = await _request(
      'GET',
      '/api/v1/community/chat/rooms/$roomId/messages',
      query: {'limit': '$limit', 'offset': '$offset'},
      requestId: requestId,
      timeout: timeout ?? readTimeout,
    );
    return _envelopeFromResponse<ChatMessagesResponse>(
      resp,
      parseData: ChatMessagesResponse.fromJsonObject,
    );
  }

  /// ONMU P3c: 채팅 WebSocket 핸드셰이크에 사용할 bearer 토큰을 해석.
  /// 동적 access token provider 가 있으면 이를, 아니면 static bearerToken 을 반환.
  /// 빈 문자열이면 연결할 수 없다(호출측에서 가드).
  Future<String> resolveWebSocketToken() async {
    if (accessTokenProvider != null) {
      try {
        final provided = (await accessTokenProvider!())?.trim();
        if (provided != null && provided.isNotEmpty) {
          return provided;
        }
      } catch (_) {
        // 폴백으로 static bearer 시도.
      }
    }
    final static = bearerToken?.trim();
    return static ?? '';
  }

  /// ONMU P3c: 채팅방 WebSocket URI 를 구성(baseUri 의 scheme 을 ws/wss 로 변환).
  /// [token] 은 query param ?token= 로 전달(브라우저 핸드셰이크는 헤더 미지원).
  Uri chatWebSocketUri({
    required String roomId,
    required String token,
  }) {
    final isSecure = baseUri.scheme == 'https' || baseUri.scheme == 'wss';
    final scheme = isSecure ? 'wss' : 'ws';
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    final routePath =
        '/api/v1/community/chat/rooms/$roomId/ws';
    final mergedPath = basePath == '/' ? routePath : '$basePath$routePath';
    return baseUri.replace(
      scheme: scheme,
      path: mergedPath,
      queryParameters: {'token': token},
    );
  }

  void close() {
    _dio.close(force: true);
  }

  Future<Response<dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    String? requestId,
    required Duration timeout,
    bool includeAuth = true,
    ResponseType responseType = ResponseType.json,
    String accept = 'application/json',
    String? contentType,
  }) async {
    final auth = await _resolveAuth(includeAuth);
    final headers = <String, String>{'Accept': accept};
    if (auth.authorization != null) {
      headers['Authorization'] = auth.authorization!;
    }
    if (auth.apiKey != null) {
      headers['X-API-Key'] = auth.apiKey!;
    }
    if (contentType != null) {
      headers['Content-Type'] = contentType;
    }
    final reqId = requestId?.trim();
    if (reqId != null && reqId.isNotEmpty) {
      headers['X-Request-ID'] = reqId;
    }

    final uri = _uri(path, query: query);
    try {
      return await _dio.requestUri<dynamic>(
        uri,
        data: body,
        options: Options(
          method: method,
          headers: headers,
          responseType: responseType,
          contentType: contentType,
          validateStatus: (_) => true,
          receiveTimeout: null,
          sendTimeout: null,
        ),
      ).timeout(timeout);
    } on TimeoutException {
      throw LalaApiException(
        code: 'REQUEST_TIMEOUT',
        message: 'LALA API request timed out.',
        statusCode: 0,
        retryable: true,
        requestId: requestId,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        throw LalaApiException(
          code: 'REQUEST_TIMEOUT',
          message: 'LALA API request timed out.',
          statusCode: 0,
          retryable: true,
          requestId: requestId,
        );
      }
      final status = e.response?.statusCode ?? 0;
      throw LalaApiException(
        code: status == 0 ? 'NETWORK_ERROR' : 'HTTP_$status',
        message: 'LALA API request failed.',
        statusCode: status,
        retryable: status >= 500,
        requestId: e.response?.headers.value('x-request-id') ?? requestId,
      );
    }
  }

  LalaEnvelope<T> _envelopeFromResponse<T>(
    Response<dynamic> resp, {
    T Function(Object?)? parseData,
  }) {
    final status = resp.statusCode ?? 0;
    final reqId = resp.headers.value('x-request-id');
    final raw = resp.data;
    if (raw is! Map<String, dynamic>) {
      throw LalaApiException(
        code: status < 200 || status >= 300 ? 'HTTP_$status' : 'INVALID_RESPONSE',
        message: 'Expected a JSON object response.',
        statusCode: status,
        retryable: status >= 500,
        requestId: reqId,
      );
    }
    final envelope = LalaEnvelope<T>.fromJson(
      raw,
      statusCode: status,
      responseRequestId: reqId,
      parseData: parseData,
    );
    if (!envelope.ok) {
      throw LalaApiException.fromEnvelope(envelope);
    }
    return envelope;
  }

  LalaApiException _exceptionFromBytesResponse(Response<dynamic> resp) {
    final status = resp.statusCode ?? 0;
    final reqId = resp.headers.value('x-request-id');
    try {
      final decoded = jsonDecode(utf8.decode(_asBytes(resp.data)));
      if (decoded is Map<String, dynamic>) {
        final envelope = LalaEnvelope<Map<String, dynamic>>.fromJson(
          decoded,
          statusCode: status,
          responseRequestId: reqId,
        );
        return LalaApiException.fromEnvelope(envelope);
      }
    } catch (_) {
      // Fall through to a generic exception. Do not include response body text.
    }
    return LalaApiException(
      code: 'HTTP_$status',
      message: 'LALA API request failed.',
      statusCode: status,
      retryable: status >= 500,
      requestId: reqId,
    );
  }

  Future<({String? authorization, String? apiKey})> _resolveAuth(
    bool includeAuth,
  ) async {
    if (!includeAuth) {
      return (authorization: null, apiKey: null);
    }

    String? providerToken;
    if (accessTokenProvider != null) {
      try {
        providerToken = (await accessTokenProvider!())?.trim();
      } catch (_) {
        throw const LalaApiException(
          code: 'AUTH_TOKEN_UNAVAILABLE',
          message: 'Access token unavailable.',
          statusCode: 0,
          retryable: true,
        );
      }
    }

    final token = providerToken != null && providerToken.isNotEmpty
        ? providerToken
        : bearerToken?.trim();
    final key = apiKey?.trim();

    if (token != null && token.isNotEmpty) {
      return (authorization: 'Bearer $token', apiKey: null);
    }
    if (key != null && key.isNotEmpty) {
      return (authorization: null, apiKey: key);
    }
    return (authorization: null, apiKey: null);
  }

  Uint8List _asBytes(dynamic data) {
    if (data is Uint8List) return data;
    if (data is List) return Uint8List.fromList(data.cast<int>());
    return Uint8List(0);
  }

  Uri _uri(String path, {Map<String, dynamic>? query}) {
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

class LalaMe {
  const LalaMe({
    required this.userId,
    required this.createdAt,
    required this.authenticated,
  });

  final String userId;
  final String createdAt;
  final bool authenticated;

  static LalaMe fromJsonObject(Object? value) {
    if (value is! Map) {
      throw const FormatException('Expected /api/v1/me data object.');
    }
    return LalaMe.fromJson(
      value.map((key, value) => MapEntry('$key', value)),
    );
  }

  factory LalaMe.fromJson(Map<String, dynamic> json) {
    final userId = json['user_id'];
    final createdAt = json['created_at'];
    final authenticated = json['authenticated'];
    if (userId is! String || createdAt is! String || authenticated is! bool) {
      throw const FormatException(
        'Expected user_id, created_at, and authenticated fields.',
      );
    }
    return LalaMe(
      userId: userId,
      createdAt: createdAt,
      authenticated: authenticated,
    );
  }
}

class LalaPlacesResponse {
  const LalaPlacesResponse({
    required this.count,
    required this.places,
    required this.query,
    required this.source,
    required this.locationEngine,
  });

  final int count;
  final List<LalaPlace> places;
  final LalaPlacesQuery query;
  final String source;
  final String locationEngine;

  static LalaPlacesResponse fromJsonObject(Object? value) {
    return LalaPlacesResponse.fromJson(_asMap(value));
  }

  factory LalaPlacesResponse.fromJson(Map<String, dynamic> json) {
    return LalaPlacesResponse(
      count: _asInt(json['count']),
      places: _asList(json['places']).map(LalaPlace.fromJsonObject).toList(),
      query: LalaPlacesQuery.fromJson(_asMap(json['query'])),
      source: _asString(json['source']),
      locationEngine: _asString(json['location_engine']),
    );
  }
}

class LalaPlacesQuery {
  const LalaPlacesQuery({
    required this.lat,
    required this.lng,
    required this.radiusM,
    required this.limit,
    required this.category,
    required this.language,
  });

  final double lat;
  final double lng;
  final int radiusM;
  final int limit;
  final String category;
  final String language;

  factory LalaPlacesQuery.fromJson(Map<String, dynamic> json) {
    return LalaPlacesQuery(
      lat: _asDouble(json['lat']),
      lng: _asDouble(json['lng']),
      radiusM: _asInt(json['radius_m']),
      limit: _asInt(json['limit']),
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
    this.imageUrl,
    this.upstreamSource,
    this.regionKo,
    this.regionEn,
    this.eventStartDate,
    this.eventEndDate,
    this.eventUrl,
    this.isOngoing,
    this.isApproximateLocation,
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
  final String? imageUrl;
  final String? upstreamSource;
  final String? regionKo;
  final String? regionEn;
  final String? eventStartDate;
  final String? eventEndDate;
  final String? eventUrl;
  final bool? isOngoing;
  final bool? isApproximateLocation;
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
      imageUrl: _asOptionalString(json['image_url']),
      upstreamSource: _asOptionalString(json['upstream_source']),
      regionKo: _asOptionalString(json['region_ko']),
      regionEn: _asOptionalString(json['region_en']),
      eventStartDate: _asOptionalString(json['event_start_date']),
      eventEndDate: _asOptionalString(json['event_end_date']),
      eventUrl: _asOptionalString(json['event_url']),
      isOngoing: _asOptionalBool(json['is_ongoing']),
      isApproximateLocation: _asOptionalBool(json['is_approximate_location']),
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
    required this.smallMerchantFitScore,
    required this.demandDispersionScore,
    required this.weatherFitScore,
    required this.reviewQualityScore,
    required this.cultureRelevanceScore,
    required this.accessibilityFitScore,
  });

  final double? localSpendingScore;
  final double? smallMerchantFitScore;
  final double? demandDispersionScore;
  final double? weatherFitScore;
  final double? reviewQualityScore;
  final double? cultureRelevanceScore;
  final double? accessibilityFitScore;

  factory LalaPlaceScoreComponents.fromJson(Map<String, dynamic> json) {
    return LalaPlaceScoreComponents(
      localSpendingScore: _asOptionalDouble(json['local_spending_score']),
      smallMerchantFitScore: _asOptionalDouble(
        json['small_merchant_fit_score'],
      ),
      demandDispersionScore: _asOptionalDouble(json['demand_dispersion_score']),
      weatherFitScore: _asOptionalDouble(json['weather_fit_score']),
      reviewQualityScore: _asOptionalDouble(json['review_quality_score']),
      cultureRelevanceScore: _asOptionalDouble(json['culture_relevance_score']),
      accessibilityFitScore: _asOptionalDouble(
        json['accessibility_fit_score'],
      ),
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
    this.pm10Grade = '',
    this.pm10GradeKo = '',
    this.pm25Grade = '',
    this.pm25GradeKo = '',
  });

  final String pm10;
  final String pm25;
  final String grade;
  final String gradeKo;
  final String pm10Grade;
  final String pm10GradeKo;
  final String pm25Grade;
  final String pm25GradeKo;

  factory LalaDust.fromJson(Map<String, dynamic> json) {
    return LalaDust(
      pm10: _asString(json['pm10']),
      pm25: _asString(json['pm25']),
      grade: _asString(json['grade']),
      gradeKo: _asString(json['grade_ko']),
      pm10Grade: _asString(json['pm10_grade']),
      pm10GradeKo: _asString(json['pm10_grade_ko']),
      pm25Grade: _asString(json['pm25_grade']),
      pm25GradeKo: _asString(json['pm25_grade_ko']),
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
    required this.radiusM,
    required this.weather,
    required this.slots,
    required this.source,
    required this.requestHash,
    required this.cacheKey,
  });

  final String language;
  final LalaCoordinate center;
  final int radiusM;
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
      radiusM: _asInt(json['radius_m']),
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
    this.place,
  });

  final LalaCoordinate center;
  final int radiusM;
  final bool shouldIntervene;
  final String reason;
  final String recommendedAction;
  final String source;
  final LalaPlace? place;

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
      place: json['place'] is Map<String, dynamic>
          ? LalaPlace.fromJson(_asMap(json['place']))
          : null,
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

  bool get isPublicCache => overall == 'public-cache' || data == 'public-cache';
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

// ─────────────────────────────────────────────────────────────────────────
// ONMU P3b: 커뮤니티 데이터 모델. apps/api app/schemas/community.py 와 대응.
// created_at/updated_at 은 백엔드가 ISO-8601 문자열로 내려주므로 String 그대로 보관한다.
// ─────────────────────────────────────────────────────────────────────────

/// 커뮤니티 게시글.
class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.authorUserId,
    required this.title,
    required this.body,
    required this.tags,
    required this.likeCount,
    required this.commentCount,
    required this.viewerLiked,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String authorUserId;
  final String title;
  final String body;
  final List<String> tags;
  final int likeCount;
  final int commentCount;
  final bool viewerLiked;
  final String createdAt;
  final String? updatedAt;

  static CommunityPost fromJsonObject(Object? value) {
    return CommunityPost.fromJson(_asMap(value));
  }

  factory CommunityPost.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    final tags = rawTags is List
        ? rawTags.map((e) => '$e').toList(growable: false)
        : const <String>[];
    return CommunityPost(
      id: _asString(json['id']),
      authorUserId: _asString(json['author_user_id']),
      title: _asString(json['title']),
      body: _asString(json['body']),
      tags: tags,
      likeCount: _asInt(json['like_count']),
      commentCount: _asInt(json['comment_count']),
      viewerLiked: _asBool(json['viewer_liked']),
      createdAt: _asString(json['created_at']),
      updatedAt: _asOptionalString(json['updated_at']),
    );
  }

  /// 좋아요/댓글 수·viewer_liked 만 갱신한 복사본(낙관적 UI 용).
  CommunityPost copyWithReactions({
    int? likeCount,
    int? commentCount,
    bool? viewerLiked,
  }) {
    return CommunityPost(
      id: id,
      authorUserId: authorUserId,
      title: title,
      body: body,
      tags: tags,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      viewerLiked: viewerLiked ?? this.viewerLiked,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// 게시글 목록 응답(count/total/posts).
class CommunityPostsResponse {
  const CommunityPostsResponse({
    required this.count,
    required this.total,
    required this.posts,
  });

  final int count;
  final int total;
  final List<CommunityPost> posts;

  static CommunityPostsResponse fromJsonObject(Object? value) {
    return CommunityPostsResponse.fromJson(_asMap(value));
  }

  factory CommunityPostsResponse.fromJson(Map<String, dynamic> json) {
    return CommunityPostsResponse(
      count: _asInt(json['count']),
      total: _asInt(json['total']),
      posts: _asList(json['posts'])
          .map(CommunityPost.fromJsonObject)
          .toList(growable: false),
    );
  }
}

/// 커뮤니티 댓글.
class CommunityComment {
  const CommunityComment({
    required this.id,
    required this.postId,
    required this.authorUserId,
    required this.body,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String postId;
  final String authorUserId;
  final String body;
  final String createdAt;
  final String? updatedAt;

  static CommunityComment fromJsonObject(Object? value) {
    return CommunityComment.fromJson(_asMap(value));
  }

  factory CommunityComment.fromJson(Map<String, dynamic> json) {
    return CommunityComment(
      id: _asString(json['id']),
      postId: _asString(json['post_id']),
      authorUserId: _asString(json['author_user_id']),
      body: _asString(json['body']),
      createdAt: _asString(json['created_at']),
      updatedAt: _asOptionalString(json['updated_at']),
    );
  }
}

/// 댓글 목록 응답(count/total/comments).
class CommunityCommentsResponse {
  const CommunityCommentsResponse({
    required this.count,
    required this.total,
    required this.comments,
  });

  final int count;
  final int total;
  final List<CommunityComment> comments;

  static CommunityCommentsResponse fromJsonObject(Object? value) {
    return CommunityCommentsResponse.fromJson(_asMap(value));
  }

  factory CommunityCommentsResponse.fromJson(Map<String, dynamic> json) {
    return CommunityCommentsResponse(
      count: _asInt(json['count']),
      total: _asInt(json['total']),
      comments: _asList(json['comments'])
          .map(CommunityComment.fromJsonObject)
          .toList(growable: false),
    );
  }
}

/// 좋아요 토글 응답(post_id/liked/like_count).
class CommunityLikeState {
  const CommunityLikeState({
    required this.postId,
    required this.liked,
    required this.likeCount,
  });

  final String postId;
  final bool liked;
  final int likeCount;

  static CommunityLikeState fromJsonObject(Object? value) {
    return CommunityLikeState.fromJson(_asMap(value));
  }

  factory CommunityLikeState.fromJson(Map<String, dynamic> json) {
    return CommunityLikeState(
      postId: _asString(json['post_id']),
      liked: _asBool(json['liked']),
      likeCount: _asInt(json['like_count']),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// ONMU P3c: 커뮤니티 채팅 데이터 모델. apps/api app/schemas/community_chat.py 와 대응.
// WebSocket 핸드셰이크/브로드캐스트 페이로드와 REST 응답이 동일한 메시지 모양을 공유한다.
// ─────────────────────────────────────────────────────────────────────────

/// 커뮤니티 채팅방.
class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String createdAt;

  static ChatRoom fromJsonObject(Object? value) {
    return ChatRoom.fromJson(_asMap(value));
  }

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: _asString(json['id']),
      name: _asString(json['name']),
      createdAt: _asString(json['created_at']),
    );
  }
}

/// 채팅방 목록 응답(count/total/rooms).
class ChatRoomsResponse {
  const ChatRoomsResponse({
    required this.count,
    required this.total,
    required this.rooms,
  });

  final int count;
  final int total;
  final List<ChatRoom> rooms;

  static ChatRoomsResponse fromJsonObject(Object? value) {
    return ChatRoomsResponse.fromJson(_asMap(value));
  }

  factory ChatRoomsResponse.fromJson(Map<String, dynamic> json) {
    return ChatRoomsResponse(
      count: _asInt(json['count']),
      total: _asInt(json['total']),
      rooms: _asList(json['rooms'])
          .map(ChatRoom.fromJsonObject)
          .toList(growable: false),
    );
  }
}

/// 채팅 메시지. WebSocket 브로드캐스트 페이로드와 REST 메시지가 같은 모양.
/// author_user_id 는 발신자가 identity.users 에 없을 수 있어 nullable.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.authorUserId,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String roomId;
  final String? authorUserId;
  final String body;
  final String createdAt;

  static ChatMessage fromJsonObject(Object? value) {
    return ChatMessage.fromJson(_asMap(value));
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: _asString(json['id']),
      roomId: _asString(json['room_id']),
      authorUserId: _asOptionalString(json['author_user_id']),
      body: _asString(json['body']),
      createdAt: _asString(json['created_at']),
    );
  }
}

/// 채팅 메시지 목록 응답(count/total/messages).
class ChatMessagesResponse {
  const ChatMessagesResponse({
    required this.count,
    required this.total,
    required this.messages,
  });

  final int count;
  final int total;
  final List<ChatMessage> messages;

  static ChatMessagesResponse fromJsonObject(Object? value) {
    return ChatMessagesResponse.fromJson(_asMap(value));
  }

  factory ChatMessagesResponse.fromJson(Map<String, dynamic> json) {
    return ChatMessagesResponse(
      count: _asInt(json['count']),
      total: _asInt(json['total']),
      messages: _asList(json['messages'])
          .map(ChatMessage.fromJsonObject)
          .toList(growable: false),
    );
  }
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

bool _validScore(double? value) {
  return value != null && value >= 0 && value <= 1;
}
