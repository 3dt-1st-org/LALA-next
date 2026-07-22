// ignore_for_file: unused_element

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'auth/auth_controller.dart';
import 'auth/logto_auth_gateway.dart';
import 'browser_location.dart';
import 'features/intervention/widgets/intervention_toast.dart';
import 'features/docent/docent_helpers.dart';
import 'features/docent/widgets/auto_docent_fab.dart';
import 'features/docent/widgets/dock_docent_preview.dart';
import 'features/docent/widgets/docent_subtitle.dart';
import 'features/location/widgets/manual_location_sheet.dart';
import 'features/place/place_helpers.dart';
import 'features/place/widgets/category_badge.dart';
import 'features/place/widgets/context_fact.dart';
import 'features/place/widgets/context_fact_chip.dart';
import 'features/place/widgets/event_info_card.dart';
import 'features/place/widgets/featured_place_header.dart';
import 'features/place/widgets/map_rail_place_card.dart';
import 'features/place/widgets/proof_chip.dart';
import 'features/place/widgets/signal_grid.dart';
import 'features/planner/widgets/planner_map_pill.dart';
import 'features/planner/widgets/planner_sheet_content.dart';
import 'features/settings/widgets/user_settings_sheet.dart';
import 'features/tour/tour_helpers.dart';
import 'features/tour/widgets/tour_map_pill.dart';
import 'features/tour/widgets/tour_sheet_content.dart';
import 'features/weather/weather_helpers.dart';
import 'features/weather/widgets/weather_map_pill.dart';
import 'features/weather/widgets/weather_sheet_content.dart';
import 'kakao_map_view.dart';
import 'manual_location_options.dart';
import 'shared/l10n/lala_copy.dart';
import 'shared/l10n/multi_language_text.dart';
import 'shared/l10n/place_labels.dart';
import 'shared/labels/basis_label.dart';
import 'shared/labels/dust_label.dart';
import 'shared/labels/source_label.dart';
import 'shared/widgets/muted_sheet_card.dart';
import 'shared/widgets/tiny_meta.dart';
import 'smoke_state.dart';

SemanticsHandle? _webSemanticsHandle;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // Force the Flutter semantics tree on web so assistive tech and browser
    // automation can inspect more than the canvas fallback placeholder.
    _webSemanticsHandle ??= SemanticsBinding.instance.ensureSemantics();
  }
  // C2: Riverpod 루트. feature 컨트롤러(C3)가 ProviderScope 하위에서 동작한다.
  runApp(const ProviderScope(child: LalaApp()));
}

typedef LalaBackendFactory = LalaBackend Function(LalaAppConfig config);

const int _defaultMapLevel = 6;
const int _focusedPlaceMapLevel = 4;
const Duration _recommendationRequestRetryDelay = Duration(milliseconds: 450);
const List<Duration> _defaultRecommendationRecoveryDelays = <Duration>[
  Duration(seconds: 8),
  Duration(seconds: 16),
  Duration(seconds: 30),
];
const String _buildSha = String.fromEnvironment('LALA_BUILD_SHA');
const List<LalaPlace> _bundledStartupPlaces = <LalaPlace>[
  LalaPlace(
    placeId: 'tour-api-2469037',
    name: '히말라야정원',
    category: 'restaurant',
    lat: 37.2635931591,
    lng: 127.0338939523,
    address: '경기도 수원시 팔달구 권광로180번길 19 (인계동) 2층',
    distanceM: 470,
    source: 'db',
    nameKo: '히말라야정원',
    imageUrl:
        'https://tong.visitkorea.or.kr/cms/resource/38/3563938_image2_1.jpg',
    upstreamSource: 'tour_api',
    regionKo: '수원시',
  ),
  LalaPlace(
    placeId: 'tour-api-129191',
    name: '나혜석거리',
    category: 'attraction',
    lat: 37.2640208974,
    lng: 127.0344383354,
    address: '경기도 수원시 팔달구 권광로188번길 25-2 (인계동)',
    distanceM: 520,
    source: 'db',
    nameKo: '나혜석거리',
    imageUrl:
        'https://tong.visitkorea.or.kr/cms/resource/99/3400899_image2_1.JPG',
    upstreamSource: 'tour_api',
    regionKo: '수원시',
  ),
  LalaPlace(
    placeId: 'tour-api-130489',
    name: '경기아트센터',
    category: 'culture_venue',
    lat: 37.2614073374,
    lng: 127.0359410498,
    address: '경기도 수원시 팔달구 효원로307번길 20 (인계동)',
    distanceM: 695,
    source: 'db',
    nameKo: '경기아트센터',
    imageUrl:
        'https://tong.visitkorea.or.kr/cms/resource/50/3055250_image2_1.JPG',
    upstreamSource: 'tour_api',
    regionKo: '수원시',
  ),
  LalaPlace(
    placeId: 'tour-api-3517333',
    name: '제3회 발달장애인 문화예술페스티벌',
    category: 'event',
    lat: 37.2614073374,
    lng: 127.0359410498,
    address: '경기도 수원시 팔달구 효원로307번길 20 (인계동)',
    distanceM: 695,
    source: 'db',
    nameKo: '제3회 발달장애인 문화예술페스티벌',
    imageUrl:
        'https://tong.visitkorea.or.kr/cms/resource/32/3517332_image2_1.jpeg',
    upstreamSource: 'tour_api',
    regionKo: '수원시',
  ),
];

class LalaApp extends StatelessWidget {
  const LalaApp({
    super.key,
    this.backendFactory = LalaApiBackend.new,
    this.initialConfig = const LalaAppConfig.fromEnvironment(),
    this.locationProvider = const GeolocatorLalaLocationProvider(),
    this.recommendationRecoveryDelays = _defaultRecommendationRecoveryDelays,
    this.authControllerFactory = createLalaAuthController,
  });

  final LalaBackendFactory backendFactory;
  final LalaAppConfig initialConfig;
  final LalaLocationProvider locationProvider;
  final List<Duration> recommendationRecoveryDelays;
  final LalaAuthControllerFactory authControllerFactory;

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF2B6CB0),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF2B6CB0),
          secondary: const Color(0xFFF5C842),
          tertiary: const Color(0xFFC53030),
          surface: const Color(0xFFF7FAFC),
          surfaceContainerLowest: Colors.white,
        );

    return MaterialApp(
      title: 'LALA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: Colors.transparent,
        useMaterial3: true,
        fontFamily: 'Pretendard',
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: LalaHomePage(
        backendFactory: backendFactory,
        initialConfig: initialConfig,
        locationProvider: locationProvider,
        recommendationRecoveryDelays: recommendationRecoveryDelays,
        authControllerFactory: authControllerFactory,
      ),
    );
  }
}

class LalaAppConfig {
  const LalaAppConfig({
    required this.baseUri,
    this.bearerToken = '',
    this.apiKey = '',
    this.kakaoJavascriptKey = '',
    this.lat = 37.2636,
    this.lng = 127.0286,
    this.radiusM = 3000,
    this.placeLimit = 60,
    this.category = 'all',
    this.lang = 'ko',
    this.requireLocationStartConfirmation = false,
    this.accessTokenProvider,
  });

  const LalaAppConfig.fromEnvironment()
    : baseUri = const String.fromEnvironment(
        'LALA_API_BASE_URL',
        defaultValue: 'http://127.0.0.1:8080',
      ),
      bearerToken = const String.fromEnvironment('LALA_API_BEARER_TOKEN'),
      apiKey = const String.fromEnvironment('LALA_IOS_API_KEY'),
      kakaoJavascriptKey = const String.fromEnvironment('KAKAO_JAVASCRIPT_KEY'),
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
      accessTokenProvider = null;

  final String baseUri;
  final String bearerToken;
  final String apiKey;
  final String kakaoJavascriptKey;
  final double lat;
  final double lng;
  final int radiusM;
  final int placeLimit;
  final String category;
  final String lang;
  final bool requireLocationStartConfirmation;
  final LalaAccessTokenProvider? accessTokenProvider;

  bool get hasAuth => bearerToken.trim().isNotEmpty || apiKey.trim().isNotEmpty;
  LalaAuthMode get authMode =>
      LalaAuthMode.fromCredentials(bearerToken: bearerToken, apiKey: apiKey);

  LalaAppConfig copyWith({
    String? baseUri,
    String? bearerToken,
    String? apiKey,
    String? kakaoJavascriptKey,
    double? lat,
    double? lng,
    int? radiusM,
    int? placeLimit,
    String? category,
    String? lang,
    bool? requireLocationStartConfirmation,
    LalaAccessTokenProvider? accessTokenProvider,
  }) {
    return LalaAppConfig(
      baseUri: baseUri ?? this.baseUri,
      bearerToken: bearerToken ?? this.bearerToken,
      apiKey: apiKey ?? this.apiKey,
      kakaoJavascriptKey: kakaoJavascriptKey ?? this.kakaoJavascriptKey,
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
    );
  }
}

class LalaLocation {
  const LalaLocation({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

enum LalaLocationResultStatus { found, denied, unavailable }

class LalaLocationResult {
  const LalaLocationResult._({required this.status, this.location});

  const LalaLocationResult.found(LalaLocation location)
    : this._(status: LalaLocationResultStatus.found, location: location);

  const LalaLocationResult.denied()
    : this._(status: LalaLocationResultStatus.denied);

  const LalaLocationResult.unavailable()
    : this._(status: LalaLocationResultStatus.unavailable);

  final LalaLocationResultStatus status;
  final LalaLocation? location;
}

abstract class LalaLocationProvider {
  Future<LalaLocationResult> requestCurrentLocation();
}

class GeolocatorLalaLocationProvider implements LalaLocationProvider {
  const GeolocatorLalaLocationProvider();

  static const Duration _permissionTimeout = Duration(seconds: 8);
  static const Duration _positionTimeout = Duration(seconds: 12);

  @override
  Future<LalaLocationResult> requestCurrentLocation() async {
    try {
      final browserLocation = await requestBrowserLocation(_positionTimeout);
      if (browserLocation.status == BrowserLocationResultStatus.found &&
          browserLocation.lat != null &&
          browserLocation.lng != null) {
        return LalaLocationResult.found(
          LalaLocation(lat: browserLocation.lat!, lng: browserLocation.lng!),
        );
      }
      if (browserLocation.status == BrowserLocationResultStatus.denied) {
        return const LalaLocationResult.denied();
      }

      var permission = await Geolocator.checkPermission().timeout(
        _permissionTimeout,
      );
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission().timeout(
          _permissionTimeout,
        );
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const LalaLocationResult.denied();
      }
      if (permission == LocationPermission.unableToDetermine) {
        return const LalaLocationResult.unavailable();
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _positionTimeout,
        ),
      ).timeout(_positionTimeout);
      return LalaLocationResult.found(
        LalaLocation(lat: position.latitude, lng: position.longitude),
      );
    } on MissingPluginException {
      return const LalaLocationResult.unavailable();
    } on TimeoutException {
      return const LalaLocationResult.unavailable();
    } on Object {
      return const LalaLocationResult.unavailable();
    }
  }
}

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
      placeName: _placeDisplayName(place, config.lang),
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

class LalaHomePage extends StatefulWidget {
  const LalaHomePage({
    required this.backendFactory,
    required this.initialConfig,
    required this.locationProvider,
    required this.recommendationRecoveryDelays,
    required this.authControllerFactory,
    super.key,
  });

  final LalaBackendFactory backendFactory;
  final LalaAppConfig initialConfig;
  final LalaLocationProvider locationProvider;
  final List<Duration> recommendationRecoveryDelays;
  final LalaAuthControllerFactory authControllerFactory;

  @override
  State<LalaHomePage> createState() => _LalaHomePageState();
}

enum _ActiveMapSheet { detail, planner, weather, tour }

class _LalaHomePageState extends State<LalaHomePage> {
  static const int _autoDocentTriggerMeters = 100;
  static const double _placesReloadThresholdMeters = 250;
  static const double _weatherReloadThresholdMeters = 10000;
  static const Duration _autoDocentCooldown = Duration(seconds: 12);
  static const Duration _interventionToastAutoDismiss = Duration(seconds: 8);
  static const Duration _initialLocationFallbackDelay = Duration(seconds: 2);
  static const Duration _weatherMaxAge = Duration(minutes: 10);

  late final LalaAppConfig _baseConfig;
  late double _queryLat;
  late double _queryLng;
  late LalaBackend _backend;
  late final LalaAuthController _authController;
  bool _authInitializationComplete = false;
  LalaAuthStatus? _lastAuthStatus;

  bool _loading = false;
  String? _error;
  LalaEnvelope<Map<String, dynamic>>? _health;
  LalaEnvelope<LalaReadiness>? _readiness;
  LalaEnvelope<LalaPlacesResponse>? _places;
  LalaEnvelope<LalaWeather>? _weather;
  LalaEnvelope<LalaIntervention>? _intervention;
  LalaEnvelope<LalaDailyPlan>? _dailyPlan;
  LalaEnvelope<LalaDocentScript>? _docentScript;
  LalaAudioResponse? _docentAudio;
  LalaAudioResponse? _tourAudio;
  bool _audioLoading = false;
  String? _audioError;
  bool _tourAudioLoading = false;
  String? _tourAudioError;
  String _selectedCategory = 'all';
  String? _selectedPlaceId;
  _ActiveMapSheet? _activeSheet;
  bool _voiceEnabled = true;
  bool _autoDocentEnabled = false;
  bool _showEvidence = false;
  bool _interventionToastDismissed = false;
  bool _locationConsentEnabled = true;
  bool _locationRequestInFlight = false;
  bool _locationFallbackNoticeVisible = false;
  bool _locationStartPromptVisible = false;
  bool _recommendationRailExpanded = true;
  List<String> _focusedClusterMemberIds = const <String>[];
  final Set<String> _savedPlaceIds = <String>{};
  final Set<String> _detailDocentPlayedPlaceIds = <String>{};
  DateTime? _lastAutoDocentAt;
  String? _lastAutoDocentPlaceId;
  double? _lastPlacesFetchLat;
  double? _lastPlacesFetchLng;
  DateTime? _lastWeatherFetchAt;
  double? _lastWeatherFetchLat;
  double? _lastWeatherFetchLng;
  LalaLocation? _currentLocation;
  double? _mapFocusLat;
  double? _mapFocusLng;
  int _mapLevel = _defaultMapLevel;
  Timer? _mapCameraDebounce;
  Timer? _interventionToastTimer;
  Timer? _recommendationRecoveryTimer;
  String _uiLanguage = 'ko';
  double _fontScale = 1.0;
  int _recommendationRecoveryAttempts = 0;
  bool _recommendationRecoveryInFlight = false;

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig;
    _baseConfig = config;
    _queryLat = config.lat;
    _queryLng = config.lng;
    _uiLanguage = config.lang;
    _locationStartPromptVisible = config.requireLocationStartConfirmation;
    _authController = widget.authControllerFactory(
      LalaAppAuthDependencies(apiBaseUri: Uri.parse(config.baseUri)),
    );
    _lastAuthStatus = _authController.state.status;
    _authController.addListener(_handleAuthStateChanged);
    _backend = widget.backendFactory(_currentConfig());
    unawaited(_initializeAuth());
    if (!config.requireLocationStartConfirmation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _requestLocationThenRefresh(initial: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _mapCameraDebounce?.cancel();
    _interventionToastTimer?.cancel();
    _recommendationRecoveryTimer?.cancel();
    _authController.removeListener(_handleAuthStateChanged);
    _authController.dispose();
    _backend.close();
    super.dispose();
  }

  LalaAppConfig _currentConfig() {
    return _baseConfig.copyWith(
      lat: _queryLat,
      lng: _queryLng,
      category: _selectedCategory,
      lang: _uiLanguage,
      accessTokenProvider: _authController.accessToken,
    );
  }

  Future<void> _initializeAuth() async {
    await _authController.initialize();
    _authInitializationComplete = true;
  }

  void _handleAuthStateChanged() {
    final previousStatus = _lastAuthStatus;
    final currentStatus = _authController.state.status;
    _lastAuthStatus = currentStatus;
    if (!_authInitializationComplete || !mounted) {
      return;
    }
    if (previousStatus == LalaAuthStatus.busy &&
        (currentStatus == LalaAuthStatus.signedIn ||
            currentStatus == LalaAuthStatus.signedOut)) {
      unawaited(_refresh(forceWeather: true));
    }
  }

  void _resetMapContext() {
    _selectedPlaceId = null;
    _activeSheet = null;
    _docentAudio = null;
    _audioError = null;
    _tourAudio = null;
    _tourAudioError = null;
    _tourAudioLoading = false;
    _showEvidence = false;
    _focusedClusterMemberIds = const <String>[];
    _recommendationRailExpanded = true;
  }

  Future<void> _requestLocationThenRefresh({
    bool initial = false,
    bool resetSelection = false,
  }) async {
    if (_locationRequestInFlight) {
      return;
    }
    setState(() {
      _locationRequestInFlight = true;
      _locationStartPromptVisible = false;
      if (resetSelection) {
        _resetMapContext();
      }
    });

    final locationFuture = widget.locationProvider.requestCurrentLocation();
    LalaLocationResult? result;
    var startedFallbackRefresh = false;

    if (initial && _places == null) {
      final fallbackDelay = Completer<void>();
      final fallbackTimer = Timer(_initialLocationFallbackDelay, () {
        if (!fallbackDelay.isCompleted) {
          fallbackDelay.complete();
        }
      });
      try {
        final initialOutcome = await Future.any<Object?>([
          locationFuture,
          fallbackDelay.future,
        ]);
        if (initialOutcome is LalaLocationResult) {
          result = initialOutcome;
        } else {
          startedFallbackRefresh = true;
          await _refresh(forceWeather: true);
        }
      } finally {
        fallbackTimer.cancel();
      }
    }

    result ??= await locationFuture;
    if (!mounted) {
      return;
    }

    final resolvedResult = result;
    final location = resolvedResult.location;
    if (resolvedResult.status == LalaLocationResultStatus.found &&
        location != null) {
      setState(() {
        _locationConsentEnabled = true;
        _locationFallbackNoticeVisible = false;
        _currentLocation = location;
        _queryLat = location.lat;
        _queryLng = location.lng;
        _mapFocusLat = location.lat;
        _mapFocusLng = location.lng;
        _mapLevel = _defaultMapLevel;
        _locationRequestInFlight = false;
      });
      await _refresh(forceWeather: true);
    } else {
      setState(() {
        _locationRequestInFlight = false;
        if (resolvedResult.status == LalaLocationResultStatus.denied) {
          _locationFallbackNoticeVisible = true;
        } else if (initial || resetSelection) {
          _locationFallbackNoticeVisible = true;
        }
      });
      if (!startedFallbackRefresh) {
        await _refresh(forceWeather: true);
      }
      return;
    }

    if (mounted) {
      setState(() {
        _locationRequestInFlight = false;
      });
    }
  }

  Future<void> _refresh({
    bool forceWeather = false,
    bool fromAutoRecovery = false,
  }) async {
    if (!fromAutoRecovery) {
      _resetRecommendationRecoveryState();
    }
    final config = _currentConfig();
    setState(() {
      _loading = true;
      if (!fromAutoRecovery) {
        _error = null;
      }
      _audioError = null;
      _docentAudio = null;
      _tourAudio = null;
      _tourAudioError = null;
      _tourAudioLoading = false;
    });

    _backend.close();
    _backend = widget.backendFactory(config);

    try {
      final loadErrors = <String>[];
      Future<T?> loadOptional<T>(
        Future<T> Function() loader, {
        bool reportError = true,
        String? Function(Object error)? fallbackMessage,
      }) async {
        try {
          return await loader();
        } on Object catch (error) {
          if (reportError) {
            loadErrors.add(
              _safeErrorMessage(error, fallbackMessage: fallbackMessage),
            );
          }
          return null;
        }
      }

      final previousHealth = _health;
      final previousReadiness = _readiness;
      final healthFuture = loadOptional(_backend.getHealth, reportError: false);
      final readinessFuture = loadOptional(
        _backend.getReadiness,
        reportError: false,
      );
      final shouldReloadWeather = shouldReloadWeatherForMapMove(
        force: forceWeather,
        hasWeather: _weather?.data != null,
        lastFetchAt: _lastWeatherFetchAt,
        lastFetchLat: _lastWeatherFetchLat,
        lastFetchLng: _lastWeatherFetchLng,
        currentLat: config.lat,
        currentLng: config.lng,
        maxAge: _weatherMaxAge,
        thresholdMeters: _weatherReloadThresholdMeters,
      );
      final previousPlaces = _places;
      final previousWeather = _weather;
      final previousIntervention = _intervention;
      final placesFuture = loadOptional(
        () => loadWithSingleRetry(
          _backend.getPlaces,
          shouldRetry: true,
          retryDelay: _recommendationRequestRetryDelay,
        ),
        fallbackMessage: (_) => _recommendationLoadFailureMessage(config.lang),
      );
      final health = (await healthFuture) ?? previousHealth;
      final readiness = (await readinessFuture) ?? previousReadiness;
      final places = await placesFuture;
      final activePlaces = places ?? previousPlaces;
      final placeItems = activePlaces?.data?.places ?? const <LalaPlace>[];
      final filteredItems = _filterPlaces(placeItems, _selectedCategory);
      final effectiveItems = filteredItems.isEmpty ? placeItems : filteredItems;
      final autoDocentPlace = _autoDocentEnabled
          ? _nextAutoDocentPlace(effectiveItems)
          : null;
      final selectedPlace = _placeById(effectiveItems, _selectedPlaceId);
      final firstPlace =
          autoDocentPlace ?? selectedPlace ?? _featuredPlace(effectiveItems);
      final coreLoadError = loadErrors.isEmpty
          ? null
          : loadErrors.toSet().take(2).join(' / ');

      if (!mounted) {
        return;
      }
      setState(() {
        _health = health;
        _readiness = readiness;
        _syncSpeechCapabilityFromReadiness(readiness);
        _places = places ?? previousPlaces;
        _docentAudio = null;
        _tourAudio = null;
        _audioError = null;
        _tourAudioError = null;
        _tourAudioLoading = false;
        _error = coreLoadError;
        _loading = false;
        if (places != null) {
          _lastPlacesFetchLat = config.lat;
          _lastPlacesFetchLng = config.lng;
        }
        if (autoDocentPlace != null) {
          _applyAutoDocentPlace(autoDocentPlace, closeActiveSheet: false);
        }
      });
      if (coreLoadError == null) {
        _resetRecommendationRecoveryState(
          emitTelemetry: fromAutoRecovery,
          reason: 'places-loaded',
        );
      } else {
        _scheduleRecommendationRecovery(reason: 'places-load-failed');
      }

      final dailyPlanFuture = loadOptional(
        _backend.createDailyPlan,
        reportError: false,
      );

      if (shouldReloadWeather) {
        final weatherFuture = loadOptional(
          _backend.getWeather,
          reportError: false,
        );
        final interventionFuture = loadOptional(
          _backend.getIntervention,
          reportError: false,
        );
        final weather = await weatherFuture;
        final intervention = await interventionFuture;
        final loadError = loadErrors.isEmpty
            ? null
            : loadErrors.toSet().take(2).join(' / ');

        if (!mounted) {
          return;
        }
        setState(() {
          _weather = weather ?? previousWeather;
          _intervention = intervention ?? previousIntervention;
          _error = loadError;
          _interventionToastDismissed = false;
          if (weather != null) {
            _lastWeatherFetchAt = DateTime.now();
            _lastWeatherFetchLat = config.lat;
            _lastWeatherFetchLng = config.lng;
          }
        });
      }
      _syncInterventionToastTimer();

      Future<LalaEnvelope<LalaDocentScript>?> docentScriptFuture =
          Future<LalaEnvelope<LalaDocentScript>?>.value();
      if (firstPlace != null) {
        final weatherContext = _publicWeatherOrNull(_weather?.data);
        docentScriptFuture = loadOptional(
          () => _backend.createDocentScript(
            place: firstPlace,
            weather: weatherContext,
          ),
          reportError: false,
        );
      }
      final dailyPlan = await dailyPlanFuture;
      final docentScript = await docentScriptFuture;
      final loadError = loadErrors.isEmpty
          ? null
          : loadErrors.toSet().take(2).join(' / ');

      if (!mounted) {
        return;
      }
      setState(() {
        _dailyPlan = dailyPlan;
        _docentScript = docentScript;
        _docentAudio = null;
        _tourAudio = null;
        _audioError = null;
        _tourAudioError = null;
        _tourAudioLoading = false;
        _error = loadError;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _safeErrorMessage(
          error,
          fallbackMessage: (_) =>
              _recommendationLoadFailureMessage(config.lang),
        );
      });
      _cancelInterventionToastTimer();
      _scheduleRecommendationRecovery(reason: 'refresh-exception');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _safeErrorMessage(
    Object error, {
    String? Function(Object error)? fallbackMessage,
  }) {
    if (error is LalaApiException) {
      return _safeUiErrorMessage(
        error.message,
        fallbackMessage: fallbackMessage?.call(error),
      );
    }
    if (error is FormatException) {
      return _safeUiErrorMessage(
        error.message,
        fallbackMessage: fallbackMessage?.call(error),
      );
    }
    return fallbackMessage?.call(error) ?? _requestFailureMessage();
  }

  Future<void> _fetchMoreInfo() async {
    if (!_voiceEnabled) {
      return;
    }
    final place = _currentDocentPlace();
    if (place == null ||
        _detailDocentPlayedPlaceIds.contains(place.placeId) ||
        _audioLoading) {
      return;
    }

    setState(() {
      _audioLoading = true;
      _audioError = null;
      _detailDocentPlayedPlaceIds.add(place.placeId);
    });

    try {
      final detailScript = await _backend.createDocentScript(
        place: place,
        weather: _publicWeatherOrNull(_weather?.data),
        mode: 'detail',
      );
      final script = detailScript.data?.script.trim();
      LalaAudioResponse? audio;
      if (script != null && script.isNotEmpty && _voiceEnabled) {
        audio = await _backend.createDocentAudio(script: script);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        if (_voiceEnabled) {
          _docentScript = detailScript;
          _docentAudio = audio;
        }
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _detailDocentPlayedPlaceIds.remove(place.placeId);
        _audioError = _safeErrorMessage(
          error,
          fallbackMessage: (_) => _docentAudioFailureMessage(),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _audioLoading = false;
        });
      }
    }
  }

  Future<void> _fetchTourAudio() async {
    if (!_voiceEnabled || _tourAudioLoading) {
      return;
    }
    final restaurants = _restaurantTourPlaces(
      _visiblePlacesForCurrentCategory(),
    ).take(5).toList(growable: false);
    if (restaurants.isEmpty) {
      return;
    }
    final script = _tourGuideScript(restaurants, _uiLanguage);
    setState(() {
      _tourAudioLoading = true;
      _tourAudioError = null;
    });
    try {
      final audio = await _backend.createDocentAudio(script: script);
      if (!mounted) {
        return;
      }
      setState(() {
        if (_voiceEnabled) {
          _tourAudio = audio;
        }
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _tourAudioError = _safeErrorMessage(
          error,
          fallbackMessage: (_) => _tourAudioFailureMessage(),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _tourAudioLoading = false;
        });
      }
    }
  }

  LalaPlace? _currentDocentPlace() {
    final places = _visiblePlacesForCurrentCategory();
    if (places.isEmpty) {
      return null;
    }
    return _placeById(places, _selectedPlaceId) ?? _featuredPlace(places);
  }

  void _selectCategory(String category) {
    setState(() {
      _selectedCategory = category;
      _selectedPlaceId = null;
      _activeSheet = null;
      _docentAudio = null;
      _audioError = null;
      _tourAudio = null;
      _tourAudioError = null;
      _tourAudioLoading = false;
      _showEvidence = false;
      _focusedClusterMemberIds = const <String>[];
      _mapFocusLat = null;
      _mapFocusLng = null;
      _mapLevel = _defaultMapLevel;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  void _selectPlace(LalaPlace place) {
    setState(() {
      _selectedPlaceId = place.placeId;
      _activeSheet = _ActiveMapSheet.detail;
      _docentAudio = null;
      _audioError = null;
      _focusedClusterMemberIds = const <String>[];
      _mapFocusLat = place.lat;
      _mapFocusLng = place.lng;
      _mapLevel = _focusedPlaceMapLevel;
    });
  }

  void _clearPlaceSelection() {
    setState(() {
      _selectedPlaceId = null;
      _activeSheet = null;
      _docentScript = null;
      _docentAudio = null;
      _audioError = null;
      _focusedClusterMemberIds = const <String>[];
      _showEvidence = false;
    });
  }

  void _focusCluster(KakaoMapPlace cluster) {
    setState(() {
      _mapFocusLat = cluster.lat;
      _mapFocusLng = cluster.lng;
      _mapLevel = _mapLevel <= 2 ? 2 : _mapLevel - 1;
      _focusedClusterMemberIds = cluster.clusterMemberIds;
      _selectedPlaceId = cluster.clusterMemberIds.isEmpty
          ? null
          : cluster.clusterMemberIds.first;
      _activeSheet = null;
      _recommendationRailExpanded = true;
    });
  }

  void _handleMapCameraIdle(KakaoMapCamera camera) {
    final normalizedLevel = camera.level.clamp(2, 10).toInt();
    final shouldReloadPlaces = shouldReloadPlacesForMapMove(
      hasAnyPlaces: _visiblePlacesForCurrentCategory().isNotEmpty,
      lastFetchLat: _lastPlacesFetchLat,
      lastFetchLng: _lastPlacesFetchLng,
      currentLat: camera.lat,
      currentLng: camera.lng,
      thresholdMeters: _placesReloadThresholdMeters,
    );
    setState(() {
      _queryLat = camera.lat;
      _queryLng = camera.lng;
      _mapFocusLat = camera.lat;
      _mapFocusLng = camera.lng;
      _mapLevel = normalizedLevel;
      if (shouldReloadPlaces) {
        _selectedPlaceId = null;
        _focusedClusterMemberIds = const <String>[];
        _activeSheet = null;
        _docentAudio = null;
        _audioError = null;
        _tourAudio = null;
        _tourAudioError = null;
        _tourAudioLoading = false;
        _recommendationRailExpanded = true;
      }
    });
    if (!shouldReloadPlaces) {
      return;
    }
    _mapCameraDebounce?.cancel();
    _mapCameraDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) {
        _refresh();
      }
    });
  }

  void _returnToCurrentLocation() {
    setState(() {
      _resetMapContext();
      final location = _currentLocation;
      if (location != null) {
        _queryLat = location.lat;
        _queryLng = location.lng;
        _mapFocusLat = location.lat;
        _mapFocusLng = location.lng;
      }
      _mapLevel = _defaultMapLevel;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _requestLocationThenRefresh(resetSelection: true);
      }
    });
  }

  void _openSheet(_ActiveMapSheet sheet) {
    setState(() {
      _activeSheet = sheet;
    });
  }

  void _closeSheet() {
    setState(() {
      _activeSheet = null;
    });
  }

  void _dismissInterventionToast() {
    _cancelInterventionToastTimer();
    setState(() {
      _interventionToastDismissed = true;
    });
  }

  void _syncInterventionToastTimer() {
    _cancelInterventionToastTimer();
    if (_error != null ||
        _interventionToastDismissed ||
        _intervention?.data?.shouldIntervene != true) {
      return;
    }
    _interventionToastTimer = Timer(_interventionToastAutoDismiss, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _interventionToastDismissed = true;
      });
    });
  }

  void _cancelInterventionToastTimer() {
    _interventionToastTimer?.cancel();
    _interventionToastTimer = null;
  }

  bool get _recommendationRecoveryPending =>
      _recommendationRecoveryTimer != null || _recommendationRecoveryInFlight;

  Duration _recommendationRecoveryDelayForAttempt(int attempt) {
    final delays = widget.recommendationRecoveryDelays;
    if (delays.isEmpty) {
      return Duration.zero;
    }
    final index = math.min(attempt, delays.length) - 1;
    return delays[index];
  }

  void _recordFrontendEvent(
    String event, {
    Map<String, Object?> details = const {},
  }) {
    publishLalaSmokeEvent({
      'event': event,
      'language': _uiLanguage,
      'category': _selectedCategory,
      'recoveryAttempt': _recommendationRecoveryAttempts,
      ...details,
    });
  }

  void _resetRecommendationRecoveryState({
    bool emitTelemetry = false,
    String reason = 'manual-reset',
  }) {
    final hadRecoveryState =
        _recommendationRecoveryAttempts > 0 ||
        _recommendationRecoveryTimer != null ||
        _recommendationRecoveryInFlight;
    _recommendationRecoveryTimer?.cancel();
    _recommendationRecoveryTimer = null;
    _recommendationRecoveryAttempts = 0;
    _recommendationRecoveryInFlight = false;
    if (emitTelemetry && hadRecoveryState) {
      _recordFrontendEvent(
        'recommendation-recovery-cleared',
        details: {'reason': reason},
      );
    }
  }

  void _scheduleRecommendationRecovery({required String reason}) {
    final maxAttempts = widget.recommendationRecoveryDelays.length;
    if (maxAttempts == 0 || _recommendationRecoveryInFlight) {
      return;
    }
    if (_recommendationRecoveryAttempts >= maxAttempts) {
      _recordFrontendEvent(
        'recommendation-recovery-exhausted',
        details: {'reason': reason},
      );
      return;
    }
    _recommendationRecoveryTimer?.cancel();
    final nextAttempt = _recommendationRecoveryAttempts + 1;
    final delay = _recommendationRecoveryDelayForAttempt(nextAttempt);
    _recordFrontendEvent(
      'recommendation-recovery-scheduled',
      details: {
        'reason': reason,
        'attempt': nextAttempt,
        'delayMs': delay.inMilliseconds,
      },
    );
    _recommendationRecoveryTimer = Timer(delay, () async {
      _recommendationRecoveryTimer = null;
      if (!mounted) {
        return;
      }
      _recommendationRecoveryAttempts = nextAttempt;
      _recommendationRecoveryInFlight = true;
      setState(() {});
      _recordFrontendEvent(
        'recommendation-recovery-started',
        details: {'attempt': nextAttempt},
      );
      try {
        await _refresh(forceWeather: true, fromAutoRecovery: true);
      } finally {
        if (!mounted) {
          _recommendationRecoveryInFlight = false;
        } else {
          setState(() {
            _recommendationRecoveryInFlight = false;
          });
        }
      }
    });
    if (mounted) {
      setState(() {});
    }
  }

  void _syncSpeechCapabilityFromReadiness(
    LalaEnvelope<LalaReadiness>? readiness,
  ) {
    if (_liveSpeechEnabled(readiness?.data) || !_voiceEnabled) {
      return;
    }
    _voiceEnabled = false;
    _docentAudio = null;
    _audioError = null;
    _audioLoading = false;
    _tourAudio = null;
    _tourAudioError = null;
    _tourAudioLoading = false;
  }

  void _toggleVoice() {
    if (!_liveSpeechEnabled(_readiness?.data)) {
      setState(() {
        _syncSpeechCapabilityFromReadiness(_readiness);
      });
      return;
    }
    final willEnable = !_voiceEnabled;
    setState(() {
      _voiceEnabled = willEnable;
      if (!willEnable) {
        _docentAudio = null;
        _audioError = null;
        _audioLoading = false;
        _tourAudio = null;
        _tourAudioError = null;
        _tourAudioLoading = false;
      }
    });
  }

  void _toggleAutoDocent() {
    final willEnable = !_autoDocentEnabled;
    final nearestPlace = willEnable
        ? _nextAutoDocentPlace(_visiblePlacesForCurrentCategory())
        : null;
    setState(() {
      _autoDocentEnabled = willEnable;
      if (nearestPlace != null) {
        _applyAutoDocentPlace(nearestPlace, closeActiveSheet: true);
      }
    });
  }

  void _toggleEvidence() {
    setState(() {
      _showEvidence = !_showEvidence;
    });
  }

  void _toggleSavedPlace(String placeId) {
    setState(() {
      if (_savedPlaceIds.contains(placeId)) {
        _savedPlaceIds.remove(placeId);
      } else {
        _savedPlaceIds.add(placeId);
      }
    });
  }

  void _toggleRecommendationRail() {
    setState(() {
      _recommendationRailExpanded = !_recommendationRailExpanded;
    });
  }

  void _setUiLanguage(String language) {
    if (_uiLanguage == language) {
      return;
    }
    setState(() {
      _uiLanguage = language;
      _docentScript = null;
      _docentAudio = null;
      _tourAudio = null;
      _audioError = null;
      _tourAudioError = null;
      _tourAudioLoading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh(forceWeather: true);
      }
    });
  }

  void _setFontScale(double scale) {
    setState(() {
      _fontScale = scale;
    });
  }

  void _setLocationConsent(bool enabled) {
    setState(() {
      _locationConsentEnabled = enabled;
      if (!enabled) {
        _locationFallbackNoticeVisible = false;
      }
    });
    if (enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _requestLocationThenRefresh(resetSelection: true);
        }
      });
    }
  }

  void _retryLocationConsent() {
    setState(() {
      _locationConsentEnabled = true;
      _locationFallbackNoticeVisible = false;
      _locationStartPromptVisible = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _requestLocationThenRefresh(resetSelection: true);
      }
    });
  }

  void _startFromCurrentLocation() {
    setState(() {
      _locationConsentEnabled = true;
      _locationFallbackNoticeVisible = false;
      _locationStartPromptVisible = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _requestLocationThenRefresh(initial: true, resetSelection: true);
      }
    });
  }

  List<LalaPlace> _visiblePlacesForCurrentCategory() {
    final apiPlaces = _places?.data?.places ?? const <LalaPlace>[];
    final filteredPlaces = _filterPlaces(apiPlaces, _selectedCategory);
    return filteredPlaces.isEmpty ? apiPlaces : filteredPlaces;
  }

  LalaPlace? _nearestAutoDocentPlace(List<LalaPlace> places) {
    if (places.isEmpty) {
      return null;
    }
    final sorted =
        places
            .where((place) => place.distanceM <= _autoDocentTriggerMeters)
            .toList()
          ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return sorted.isEmpty ? null : sorted.first;
  }

  LalaPlace? _nextAutoDocentPlace(List<LalaPlace> places) {
    final nearestPlace = _nearestAutoDocentPlace(places);
    if (nearestPlace == null) {
      _lastAutoDocentPlaceId = null;
      return null;
    }

    final now = DateTime.now();
    final lastAutoDocentAt = _lastAutoDocentAt;
    if (lastAutoDocentAt != null &&
        now.difference(lastAutoDocentAt) < _autoDocentCooldown) {
      return null;
    }
    if (nearestPlace.placeId == _lastAutoDocentPlaceId) {
      return null;
    }

    _lastAutoDocentAt = now;
    _lastAutoDocentPlaceId = nearestPlace.placeId;
    return nearestPlace;
  }

  void _applyAutoDocentPlace(
    LalaPlace place, {
    required bool closeActiveSheet,
  }) {
    _selectedPlaceId = place.placeId;
    if (closeActiveSheet) {
      _activeSheet = null;
    }
    _docentAudio = null;
    _audioError = null;
    _focusedClusterMemberIds = const <String>[];
    _mapFocusLat = place.lat;
    _mapFocusLng = place.lng;
    _mapLevel = _focusedPlaceMapLevel;
  }

  Future<void> _openSettingsSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void updateSheet(VoidCallback action) {
              action();
              setSheetState(() {});
            }

            return UserSettingsSheet(
              authController: _authController,
              locationConsentEnabled: _locationConsentEnabled,
              uiLanguage: _uiLanguage,
              fontScale: _fontScale,
              onLocationConsentChanged: (enabled) =>
                  updateSheet(() => _setLocationConsent(enabled)),
              onLanguageChanged: (language) =>
                  updateSheet(() => _setUiLanguage(language)),
              onFontScaleChanged: (scale) =>
                  updateSheet(() => _setFontScale(scale)),
            );
          },
        );
      },
    );
  }

  Future<void> _openManualLocationSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<ManualLocationOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ManualLocationSheet(language: _uiLanguage),
    );
    if (!mounted || selected == null) {
      return;
    }
    setState(() {
      _resetMapContext();
      _locationConsentEnabled = true;
      _locationRequestInFlight = false;
      _locationFallbackNoticeVisible = false;
      _locationStartPromptVisible = false;
      _currentLocation = null;
      _queryLat = selected.lat;
      _queryLng = selected.lng;
      _mapFocusLat = selected.lat;
      _mapFocusLng = selected.lng;
      _mapLevel = _defaultMapLevel;
    });
    await _refresh(forceWeather: true);
  }

  @override
  Widget build(BuildContext context) {
    final config = _currentConfig();
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(_fontScale)),
      child: Scaffold(
        body: SafeArea(
          child: Builder(
            builder: (context) => _Dashboard(
              loading: _loading,
              error: _error,
              health: _health,
              readiness: _readiness,
              places: _places,
              weather: _weather,
              intervention: _intervention,
              dailyPlan: _dailyPlan,
              docentScript: _docentScript,
              docentAudio: _docentAudio,
              tourAudio: _tourAudio,
              audioLoading: _audioLoading,
              audioError: _audioError,
              tourAudioLoading: _tourAudioLoading,
              tourAudioError: _tourAudioError,
              authMode: config.authMode,
              kakaoJavascriptKey: config.kakaoJavascriptKey,
              selectedCategory: _selectedCategory,
              selectedPlaceId: _selectedPlaceId,
              activeSheet: _activeSheet,
              uiLanguage: _uiLanguage,
              voiceEnabled: _voiceEnabled,
              autoDocentEnabled: _autoDocentEnabled,
              showEvidence: _showEvidence,
              savedPlaceIds: _savedPlaceIds,
              detailDocentPlayedPlaceIds: _detailDocentPlayedPlaceIds,
              interventionToastDismissed: _interventionToastDismissed,
              locationConsentEnabled: _locationConsentEnabled,
              locationRequestInFlight: _locationRequestInFlight,
              locationFallbackNoticeVisible: _locationFallbackNoticeVisible,
              locationStartPromptVisible: _locationStartPromptVisible,
              recommendationRailExpanded: _recommendationRailExpanded,
              recommendationRecoveryPending: _recommendationRecoveryPending,
              recommendationRecoveryAttempt: _recommendationRecoveryAttempts,
              focusedClusterMemberIds: _focusedClusterMemberIds,
              mapFocusLat: _mapFocusLat,
              mapFocusLng: _mapFocusLng,
              mapLevel: _mapLevel,
              onSelectCategory: _selectCategory,
              onSelectPlace: _selectPlace,
              onSelectCluster: _focusCluster,
              onCameraIdle: _handleMapCameraIdle,
              onClearPlaceSelection: _clearPlaceSelection,
              onToggleRecommendationRail: _toggleRecommendationRail,
              onOpenSheet: _openSheet,
              onCloseSheet: _closeSheet,
              onToggleVoice: _toggleVoice,
              onToggleAutoDocent: _toggleAutoDocent,
              onToggleEvidence: _toggleEvidence,
              onToggleSavedPlace: _toggleSavedPlace,
              onDismissInterventionToast: _dismissInterventionToast,
              onFetchAudio: _fetchMoreInfo,
              onFetchTourAudio: _fetchTourAudio,
              onRefresh: () => _refresh(),
              onRefreshWeather: () => _refresh(forceWeather: true),
              onReturnToLocation: _returnToCurrentLocation,
              onOpenSettings: () => _openSettingsSheet(context),
              onOpenManualLocation: () => _openManualLocationSheet(context),
              onRetryLocation: _retryLocationConsent,
              onStartLocation: _startFromCurrentLocation,
            ),
          ),
        ),
      ),
    );
  }
}

// C3 추출(Settings + Location): _SettingsSection, _AccountSettingsSection,
// _AccountStatusRow, _AccountErrorText, _UserSettingsSheet, _PrivacyDetailsSheet,
// _PrivacyDetailRow → features/settings/widgets/ (+ _showPrivacyDetailsSheet,
// _languageOptionLabel, _MetricRow). _ManualLocationSheet(+State),
// _ManualLocationProvinceChip, _ManualLocationSectionLabel,
// _ManualLocationEmptyState, _ManualLocationTile → features/location/widgets/.

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.loading,
    required this.error,
    required this.health,
    required this.readiness,
    required this.places,
    required this.weather,
    required this.intervention,
    required this.dailyPlan,
    required this.docentScript,
    required this.docentAudio,
    required this.tourAudio,
    required this.audioLoading,
    required this.audioError,
    required this.tourAudioLoading,
    required this.tourAudioError,
    required this.authMode,
    required this.kakaoJavascriptKey,
    required this.selectedCategory,
    required this.selectedPlaceId,
    required this.activeSheet,
    required this.uiLanguage,
    required this.voiceEnabled,
    required this.autoDocentEnabled,
    required this.showEvidence,
    required this.savedPlaceIds,
    required this.detailDocentPlayedPlaceIds,
    required this.interventionToastDismissed,
    required this.locationConsentEnabled,
    required this.locationRequestInFlight,
    required this.locationFallbackNoticeVisible,
    required this.locationStartPromptVisible,
    required this.recommendationRailExpanded,
    required this.recommendationRecoveryPending,
    required this.recommendationRecoveryAttempt,
    required this.focusedClusterMemberIds,
    required this.mapFocusLat,
    required this.mapFocusLng,
    required this.mapLevel,
    required this.onSelectCategory,
    required this.onSelectPlace,
    required this.onSelectCluster,
    required this.onCameraIdle,
    required this.onClearPlaceSelection,
    required this.onToggleRecommendationRail,
    required this.onOpenSheet,
    required this.onCloseSheet,
    required this.onToggleVoice,
    required this.onToggleAutoDocent,
    required this.onToggleEvidence,
    required this.onToggleSavedPlace,
    required this.onDismissInterventionToast,
    required this.onFetchAudio,
    required this.onFetchTourAudio,
    required this.onRefresh,
    required this.onRefreshWeather,
    required this.onReturnToLocation,
    required this.onOpenSettings,
    required this.onOpenManualLocation,
    required this.onRetryLocation,
    required this.onStartLocation,
  });

  final bool loading;
  final String? error;
  final LalaEnvelope<Map<String, dynamic>>? health;
  final LalaEnvelope<LalaReadiness>? readiness;
  final LalaEnvelope<LalaPlacesResponse>? places;
  final LalaEnvelope<LalaWeather>? weather;
  final LalaEnvelope<LalaIntervention>? intervention;
  final LalaEnvelope<LalaDailyPlan>? dailyPlan;
  final LalaEnvelope<LalaDocentScript>? docentScript;
  final LalaAudioResponse? docentAudio;
  final LalaAudioResponse? tourAudio;
  final bool audioLoading;
  final String? audioError;
  final bool tourAudioLoading;
  final String? tourAudioError;
  final LalaAuthMode authMode;
  final String kakaoJavascriptKey;
  final String selectedCategory;
  final String? selectedPlaceId;
  final _ActiveMapSheet? activeSheet;
  final String uiLanguage;
  final bool voiceEnabled;
  final bool autoDocentEnabled;
  final bool showEvidence;
  final Set<String> savedPlaceIds;
  final Set<String> detailDocentPlayedPlaceIds;
  final bool interventionToastDismissed;
  final bool locationConsentEnabled;
  final bool locationRequestInFlight;
  final bool locationFallbackNoticeVisible;
  final bool locationStartPromptVisible;
  final bool recommendationRailExpanded;
  final bool recommendationRecoveryPending;
  final int recommendationRecoveryAttempt;
  final List<String> focusedClusterMemberIds;
  final double? mapFocusLat;
  final double? mapFocusLng;
  final int mapLevel;
  final ValueChanged<String> onSelectCategory;
  final ValueChanged<LalaPlace> onSelectPlace;
  final ValueChanged<KakaoMapPlace> onSelectCluster;
  final ValueChanged<KakaoMapCamera> onCameraIdle;
  final VoidCallback onClearPlaceSelection;
  final VoidCallback onToggleRecommendationRail;
  final ValueChanged<_ActiveMapSheet> onOpenSheet;
  final VoidCallback onCloseSheet;
  final VoidCallback onToggleVoice;
  final VoidCallback onToggleAutoDocent;
  final VoidCallback onToggleEvidence;
  final ValueChanged<String> onToggleSavedPlace;
  final VoidCallback onDismissInterventionToast;
  final VoidCallback onFetchAudio;
  final VoidCallback onFetchTourAudio;
  final VoidCallback onRefresh;
  final VoidCallback onRefreshWeather;
  final VoidCallback onReturnToLocation;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenManualLocation;
  final VoidCallback onRetryLocation;
  final VoidCallback onStartLocation;

  @override
  Widget build(BuildContext context) {
    final apiPlaces = places?.data?.places ?? const <LalaPlace>[];
    final hasLivePlaces = apiPlaces.isNotEmpty;
    final effectiveSource = hasLivePlaces ? places?.data?.source : 'db';
    final visibleError = _localizedUiMessage(error, uiLanguage);
    final showBundledStartupPlaces = !hasLivePlaces && visibleError == null;
    final displayedError = visibleError == null
        ? null
        : _recommendationStatusMessage(
            uiLanguage,
            recoveryPending: recommendationRecoveryPending,
          );
    final allPlaces = hasLivePlaces
        ? apiPlaces
        : showBundledStartupPlaces
        ? _bundledStartupPlaces
        : const <LalaPlace>[];
    final filteredTopPlaces = _filterPlaces(allPlaces, selectedCategory);
    final topPlaces = _prioritizeClusterMembers(
      filteredTopPlaces,
      focusedClusterMemberIds,
    );
    final tourPlaces = _restaurantTourPlaces(allPlaces);
    final topPlace =
        _placeById(topPlaces, selectedPlaceId) ?? _featuredPlace(topPlaces);
    final activeDocent = docentScript?.data;
    final activeDailyPlan = dailyPlan?.data;
    final currentWeather = _publicWeatherOrNull(weather?.data);
    final activeIntervention = intervention?.data;
    final liveSpeechEnabled = _liveSpeechEnabled(readiness?.data);
    publishLalaSmokeState({
      'buildSha': _buildSha,
      'apiPlacesCount': apiPlaces.length,
      'topPlacesCount': topPlaces.length,
      'usingBundledStartupPlaces': showBundledStartupPlaces,
      'selectedCategory': selectedCategory,
      'locationFallbackNoticeVisible': locationFallbackNoticeVisible,
      'locationManualSelectAvailable':
          locationFallbackNoticeVisible && !locationRequestInFlight,
      'locationRequestInFlight': locationRequestInFlight,
      'locationStartPromptVisible': locationStartPromptVisible,
      'manualLocationOptionCount': manualLocationOptions.length,
      'weatherVisible': currentWeather != null,
      'weatherSource': currentWeather?.source ?? '',
      'weatherHasPm10': currentWeather?.dust.pm10 != null,
      'weatherHasPm25': currentWeather?.dust.pm25 != null,
      'visibleError': visibleError ?? '',
      'displayedError': displayedError ?? '',
      'recommendationRecoveryPending': recommendationRecoveryPending,
      'recommendationRecoveryAttempt': recommendationRecoveryAttempt,
      'mapLevel': mapLevel,
    });
    void selectPlaceById(String placeId) {
      final place = _placeById(topPlaces, placeId);
      if (place != null) {
        onSelectPlace(place);
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 860;
        final compactMapChrome =
            !isWide &&
            (constraints.maxWidth <= 430 || constraints.maxHeight < 760);
        final floatingPillTop = isWide
            ? 264.0
            : compactMapChrome
            ? 242.0
            : 266.0;
        final locationFallbackTop =
            topPlaces.isNotEmpty && recommendationRailExpanded
            ? isWide
                  ? 286.0
                  : compactMapChrome
                  ? 246.0
                  : 282.0
            : isWide
            ? 232.0
            : 220.0;
        final bottomDockHeight = isWide
            ? 218.0
            : constraints.maxHeight < 700
            ? 164.0
            : compactMapChrome
            ? 224.0
            : 238.0;
        final floatingControlsBottom = bottomDockHeight + 16;
        return Stack(
          children: [
            Positioned.fill(
              child: _LegacyMapCanvas(
                places: topPlaces,
                selectedPlace: topPlace,
                weather: currentWeather,
                kakaoJavascriptKey: kakaoJavascriptKey,
                language: uiLanguage,
                mapFocusLat: mapFocusLat,
                mapFocusLng: mapFocusLng,
                mapLevel: mapLevel,
                onSelectPlaceId: selectPlaceById,
                onSelectCluster: onSelectCluster,
                onCameraIdle: onCameraIdle,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _TopMapChrome(
                loading: loading,
                language: uiLanguage,
                selectedCategory: selectedCategory,
                onSelectCategory: onSelectCategory,
                onOpenSettings: onOpenSettings,
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: isWide ? 76 : 68,
              child: Center(
                child: SizedBox(
                  width: isWide
                      ? math.min(780.0, constraints.maxWidth - 32)
                      : constraints.maxWidth - 32,
                  child: _MapPlaceCarouselOverlay(
                    places: topPlaces,
                    source: effectiveSource,
                    language: uiLanguage,
                    selectedPlaceId: topPlace?.placeId,
                    explicitSelectedPlaceId: selectedPlaceId,
                    expanded: recommendationRailExpanded,
                    compact: compactMapChrome,
                    onSelectPlace: onSelectPlace,
                    onReselectSelectedPlace: onClearPlaceSelection,
                    onToggleExpanded: onToggleRecommendationRail,
                  ),
                ),
              ),
            ),
            if (selectedCategory == 'restaurant' && tourPlaces.isNotEmpty)
              Positioned(
                right: 16,
                top: 52,
                child: TourMapPill(
                  places: tourPlaces,
                  language: uiLanguage,
                  onPressed: () => onOpenSheet(_ActiveMapSheet.tour),
                ),
              ),
            if (displayedError != null)
              Positioned(
                left: 16,
                right: isWide ? null : 16,
                top: isWide ? 88 : 118,
                child: SizedBox(
                  width: isWide ? 420 : null,
                  child: _MapToast(
                    icon: Icons.error_outline,
                    label: displayedError,
                    actionLabel: _copy(
                      uiLanguage,
                      ko: '지금 다시 시도',
                      en: 'Retry now',
                    ),
                    onAction: onRefresh,
                    color: Theme.of(context).colorScheme.errorContainer,
                  ),
                ),
              ),
            if (displayedError == null &&
                locationFallbackNoticeVisible &&
                !locationRequestInFlight)
              Positioned(
                left: 16,
                right: isWide ? null : 16,
                top: locationFallbackTop,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: _MapToast(
                      actionKey: const ValueKey('location-fallback-retry'),
                      secondaryActionKey: const ValueKey(
                        'location-manual-select',
                      ),
                      icon: Icons.my_location_outlined,
                      label: _copy(
                        uiLanguage,
                        ko: '현재 위치를 확인해야 추천을 볼 수 있어요',
                        en: 'Location permission is needed for recommendations',
                      ),
                      actionLabel: _copy(uiLanguage, ko: '재시도', en: 'Retry'),
                      onAction: onRetryLocation,
                      secondaryActionLabel: _copy(
                        uiLanguage,
                        ko: '지역 선택',
                        en: 'Choose area',
                      ),
                      onSecondaryAction: onOpenManualLocation,
                      color: Colors.white.withValues(alpha: 0.94),
                    ),
                  ),
                ),
              ),
            if (displayedError == null &&
                activeIntervention?.shouldIntervene == true &&
                !interventionToastDismissed)
              Positioned(
                left: 16,
                right: 16,
                top: isWide ? 92 : 110,
                child: Center(
                  child: InterventionToast(
                    label: _interventionToastLabel(
                      activeIntervention!,
                      uiLanguage,
                    ),
                    language: uiLanguage,
                    onOpenPlanner: () => onOpenSheet(_ActiveMapSheet.planner),
                    onDismiss: onDismissInterventionToast,
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: SizedBox(
                  width: isWide
                      ? math.min(760.0, constraints.maxWidth - 32)
                      : constraints.maxWidth,
                  child: _MapBottomDock(
                    isWide: isWide,
                    places: topPlaces,
                    source: effectiveSource,
                    topPlace: topPlace,
                    uiLanguage: uiLanguage,
                    height: bottomDockHeight,
                    docentScript: activeDocent?.placeId == topPlace?.placeId
                        ? activeDocent?.script
                        : null,
                    docentAudio: docentAudio,
                    docentAction:
                        activeIntervention?.recommendedAction ??
                        (activeDailyPlan?.slots.isEmpty == false
                            ? activeDailyPlan?.slots.first.title
                            : null),
                    audioLoading: audioLoading,
                    audioError: _localizedUiMessage(audioError, uiLanguage),
                    canFetchAudio:
                        liveSpeechEnabled &&
                        activeDocent?.placeId == topPlace?.placeId &&
                        _hasUsableDocentScript(
                          activeDocent?.script,
                          uiLanguage,
                        ) &&
                        !audioLoading &&
                        topPlace != null &&
                        !detailDocentPlayedPlaceIds.contains(topPlace.placeId),
                    showEvidence: showEvidence,
                    error: displayedError,
                    recommendationRecoveryPending:
                        recommendationRecoveryPending,
                    onFetchAudio: onFetchAudio,
                    onAddToPlan: () => onOpenSheet(_ActiveMapSheet.planner),
                    onOpenDetail: () => onOpenSheet(_ActiveMapSheet.detail),
                    onRefresh: onRefresh,
                    onToggleEvidence: onToggleEvidence,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: floatingControlsBottom,
              child: Center(
                child: _FloatingMapControls(
                  voiceEnabled: voiceEnabled,
                  autoDocentEnabled: autoDocentEnabled,
                  language: uiLanguage,
                  onToggleVoice: onToggleVoice,
                  onToggleAutoDocent: onToggleAutoDocent,
                  onReturnToLocation: onReturnToLocation,
                ),
              ),
            ),
            if (!locationFallbackNoticeVisible)
              Positioned(
                left: 16,
                right: 16,
                top: floatingPillTop,
                child: Center(
                  child: SizedBox(
                    width: isWide
                        ? math.min(760.0, constraints.maxWidth - 32)
                        : constraints.maxWidth - 32,
                    child: _MapUtilityControlRow(
                      dailyPlan: activeDailyPlan,
                      weather: currentWeather,
                      language: uiLanguage,
                      onOpenPlanner: () => onOpenSheet(_ActiveMapSheet.planner),
                      onOpenWeather: () {
                        onOpenSheet(_ActiveMapSheet.weather);
                        onRefreshWeather();
                      },
                    ),
                  ),
                ),
              ),
            if (activeSheet != null)
              Positioned.fill(
                child: _MapDraggableSheet(
                  activeSheet: activeSheet!,
                  place: topPlace,
                  places: tourPlaces,
                  weather: currentWeather,
                  language: uiLanguage,
                  loading: loading,
                  intervention: intervention?.data,
                  dailyPlan: dailyPlan?.data,
                  docentScript: docentScript?.data,
                  docentAudio: docentAudio,
                  tourAudio: tourAudio,
                  audioLoading: audioLoading,
                  audioError: _localizedUiMessage(audioError, uiLanguage),
                  tourAudioLoading: tourAudioLoading,
                  tourAudioError: _localizedUiMessage(
                    tourAudioError,
                    uiLanguage,
                  ),
                  liveSpeechEnabled: liveSpeechEnabled,
                  source: effectiveSource,
                  showEvidence: showEvidence,
                  savedPlaceIds: savedPlaceIds,
                  detailDocentPlayedPlaceIds: detailDocentPlayedPlaceIds,
                  onToggleEvidence: onToggleEvidence,
                  onToggleSavedPlace: onToggleSavedPlace,
                  onAddToPlan: () => onOpenSheet(_ActiveMapSheet.planner),
                  onFetchAudio: onFetchAudio,
                  onFetchTourAudio: onFetchTourAudio,
                  onSelectPlace: onSelectPlace,
                  onRefresh: onRefresh,
                  onClose: onCloseSheet,
                ),
              ),
            if (locationStartPromptVisible)
              Positioned.fill(
                child: _LocationStartPromptOverlay(
                  language: uiLanguage,
                  onStartLocation: onStartLocation,
                ),
              ),
            if (!locationStartPromptVisible && !locationConsentEnabled)
              Positioned.fill(
                child: _LocationConsentOverlay(
                  language: uiLanguage,
                  onOpenSettings: onOpenSettings,
                  onRetryLocation: onRetryLocation,
                ),
              ),
            if (locationRequestInFlight && places == null)
              Positioned.fill(
                child: _LocationStartupOverlay(language: uiLanguage),
              ),
          ],
        );
      },
    );
  }
}

class _LocationStartPromptOverlay extends StatelessWidget {
  const _LocationStartPromptOverlay({
    required this.language,
    required this.onStartLocation,
  });

  final String language;
  final VoidCallback onStartLocation;

  @override
  Widget build(BuildContext context) {
    final isEnglish = language == 'en';
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.86),
      child: SafeArea(
        child: Center(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 430),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE1ECF8)),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 34,
                  offset: Offset(0, 18),
                  color: Color(0x22000000),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FB),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.my_location_outlined,
                    color: Color(0xFF2B6CB0),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  isEnglish ? 'Start from here' : '현재 위치에서 시작할게요',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isEnglish
                      ? 'LALA uses your approximate location to load nearby places, weather, and local routes.'
                      : '주변 장소와 날씨, 로컬 동선을 불러오기 위해 대략적인 위치를 확인합니다.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4B5563),
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const ValueKey('location-start-confirm'),
                  onPressed: onStartLocation,
                  icon: const Icon(Icons.my_location),
                  label: Text(isEnglish ? 'Use my location' : '현재 위치 사용'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: const Color(0xFF2B6CB0),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocationStartupOverlay extends StatelessWidget {
  const _LocationStartupOverlay({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    final isEnglish = language == 'en';
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.82),
      child: SafeArea(
        child: Center(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 430),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE1ECF8)),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 34,
                  offset: Offset(0, 18),
                  color: Color(0x22000000),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FB),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.my_location_outlined,
                    color: Color(0xFF2B6CB0),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  isEnglish
                      ? 'Start from your current location'
                      : '현재 위치로 시작할게요',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isEnglish
                      ? 'Allow location access in your browser and LALA will immediately load nearby culture, weather, and local experience recommendations.'
                      : '브라우저의 위치 권한을 허용하면 주변 문화·날씨·로컬 경험 추천을 바로 불러옵니다.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4B5563),
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isEnglish
                            ? 'Waiting for the browser permission prompt'
                            : '위치 권한 확인 중',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF2B6CB0),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopMapChrome extends StatelessWidget {
  const _TopMapChrome({
    required this.loading,
    required this.language,
    required this.selectedCategory,
    required this.onSelectCategory,
    required this.onOpenSettings,
  });

  final bool loading;
  final String language;
  final String selectedCategory;
  final ValueChanged<String> onSelectCategory;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _CategoryChip(
                        label: categoryFilterLabel('all', language),
                        active: selectedCategory == 'all',
                        color: const Color(0xFF1A202C),
                        onTap: () => onSelectCategory('all'),
                      ),
                      _CategoryChip(
                        label: categoryFilterLabel('attraction', language),
                        active: selectedCategory == 'attraction',
                        color: const Color(0xFFC53030),
                        onTap: () => onSelectCategory('attraction'),
                      ),
                      _CategoryChip(
                        label: categoryFilterLabel('restaurant', language),
                        active: selectedCategory == 'restaurant',
                        color: const Color(0xFFF5C842),
                        onTap: () => onSelectCategory('restaurant'),
                      ),
                      _CategoryChip(
                        label: categoryFilterLabel('event', language),
                        active: selectedCategory == 'event',
                        color: const Color(0xFF2B6CB0),
                        onTap: () => onSelectCategory('event'),
                      ),
                      _CategoryChip(
                        label: categoryFilterLabel('culture_venue', language),
                        active: selectedCategory == 'culture_venue',
                        color: const Color(0xFF0F766E),
                        onTap: () => onSelectCategory('culture_venue'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _MapRoundButton(
                buttonKey: const ValueKey('settings-button'),
                tooltip: _copy(language, ko: '설정', en: 'Settings'),
                icon: Icons.settings,
                onPressed: onOpenSettings,
              ),
            ],
          ),
          if (loading) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: const LinearProgressIndicator(minHeight: 3),
            ),
          ],
        ],
      ),
    );
  }
}

class _MapPlaceCarouselOverlay extends StatelessWidget {
  const _MapPlaceCarouselOverlay({
    required this.places,
    required this.source,
    required this.language,
    required this.selectedPlaceId,
    required this.explicitSelectedPlaceId,
    required this.expanded,
    required this.compact,
    required this.onSelectPlace,
    required this.onReselectSelectedPlace,
    required this.onToggleExpanded,
  });

  final List<LalaPlace> places;
  final String? source;
  final String language;
  final String? selectedPlaceId;
  final String? explicitSelectedPlaceId;
  final bool expanded;
  final bool compact;
  final ValueChanged<LalaPlace> onSelectPlace;
  final VoidCallback onReselectSelectedPlace;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final items = _railPlaces(places);
    final railHeight = compact ? 126.0 : 150.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.center,
          child: Material(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(999),
            elevation: 0,
            shadowColor: const Color(0x18000000),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onToggleExpanded,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 12,
                      offset: Offset(0, 4),
                      color: Color(0x18000000),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 17,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      expanded
                          ? _copy(language, ko: '추천 장소 접기', en: 'Hide places')
                          : _copy(language, ko: '추천 장소 보기', en: 'Show places'),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: const Color(0xFF374151),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _copy(
                        language,
                        ko: '${items.length}곳 · ${_sourceLabel(source, language: language)}',
                        en: '${items.length} places · ${_sourceLabel(source, language: language)}',
                      ),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: expanded
              ? Column(
                  key: const ValueKey('recommendation-rail-expanded'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    SizedBox(
                      key: const ValueKey('recommendation-rail-list'),
                      height: railHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              blurRadius: 18,
                              offset: Offset(0, 8),
                              color: Color(0x16000000),
                            ),
                          ],
                        ),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(8),
                          scrollDirection: Axis.horizontal,
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final place = items[index];
                            final selected =
                                (selectedPlaceId == null && index == 0) ||
                                selectedPlaceId == place.placeId;
                            final explicitlySelected =
                                explicitSelectedPlaceId == place.placeId;
                            return MapRailPlaceCard(
                              place: place,
                              language: language,
                              selected: selected,
                              compact: compact,
                              onTap: explicitlySelected
                                  ? onReselectSelectedPlace
                                  : selected
                                  ? null
                                  : () => onSelectPlace(place),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(
                  key: ValueKey('recommendation-rail-collapsed'),
                ),
        ),
      ],
    );
  }
}

// C3: RailCategoryBadge → features/place/widgets/rail_category_badge.dart (RailCategoryBadge).
// C3: RailPlaceThumb → features/place/widgets/rail_place_thumb.dart (RailPlaceThumb).

// C3: PlannerMapPill → features/planner/widgets/planner_map_pill.dart (PlannerMapPill).

class _MapUtilityControlRow extends StatelessWidget {
  const _MapUtilityControlRow({
    required this.dailyPlan,
    required this.weather,
    required this.language,
    required this.onOpenPlanner,
    required this.onOpenWeather,
  });

  final LalaDailyPlan? dailyPlan;
  final LalaWeather? weather;
  final String language;
  final VoidCallback onOpenPlanner;
  final VoidCallback onOpenWeather;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('map-utility-control-row'),
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: PlannerMapPill(
              dailyPlan: dailyPlan,
              language: language,
              onPressed: onOpenPlanner,
            ),
          ),
        ),
        const SizedBox(width: 46),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: WeatherMapPill(
              key: const ValueKey('weather-pill'),
              weather: weather,
              language: language,
              onPressed: onOpenWeather,
            ),
          ),
        ),
      ],
    );
  }
}

// C3: TourMapPill → features/tour/widgets/tour_map_pill.dart (TourMapPill).

class _MapBottomDock extends StatelessWidget {
  const _MapBottomDock({
    required this.isWide,
    required this.places,
    required this.source,
    required this.topPlace,
    required this.uiLanguage,
    required this.height,
    required this.docentScript,
    required this.docentAudio,
    required this.docentAction,
    required this.audioLoading,
    required this.audioError,
    required this.canFetchAudio,
    required this.showEvidence,
    required this.error,
    required this.recommendationRecoveryPending,
    required this.onFetchAudio,
    required this.onAddToPlan,
    required this.onOpenDetail,
    required this.onRefresh,
    required this.onToggleEvidence,
  });

  final bool isWide;
  final List<LalaPlace> places;
  final String? source;
  final LalaPlace? topPlace;
  final String uiLanguage;
  final double height;
  final String? docentScript;
  final LalaAudioResponse? docentAudio;
  final String? docentAction;
  final bool audioLoading;
  final String? audioError;
  final bool canFetchAudio;
  final bool showEvidence;
  final String? error;
  final bool recommendationRecoveryPending;
  final VoidCallback onFetchAudio;
  final VoidCallback onAddToPlan;
  final VoidCallback onOpenDetail;
  final VoidCallback onRefresh;
  final VoidCallback onToggleEvidence;

  @override
  Widget build(BuildContext context) {
    final currentPlace = topPlace;
    return SizedBox(
      key: const ValueKey('map-bottom-dock'),
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: const [
            BoxShadow(
              blurRadius: 28,
              offset: Offset(0, -10),
              color: Color(0x22000000),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, isWide ? 14 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onTap: onOpenDetail,
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCBD5E0),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: currentPlace == null ? null : onOpenDetail,
                    icon: const Icon(Icons.keyboard_arrow_up),
                    label: Text(uiLanguage == 'en' ? 'Details' : '상세'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (currentPlace == null)
                _EmptyDockContent(
                  language: uiLanguage,
                  errorLabel: error,
                  recoveryPending: recommendationRecoveryPending,
                  onRetry: onRefresh,
                )
              else ...[
                Row(
                  children: [
                    CategoryBadge(
                      category: currentPlace.category,
                      language: uiLanguage,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _placeDisplayName(currentPlace, uiLanguage),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: const Color(0xFF111827),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        if (!showEvidence) {
                          onToggleEvidence();
                        }
                        onOpenDetail();
                      },
                      child: Text(
                        uiLanguage == 'en' ? 'Signals' : '점수/근거',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TinyMeta(_placeRegionLabel(currentPlace, uiLanguage)),
                    TinyMeta('${currentPlace.distanceM}m'),
                    TinyMeta(_sourceLabel(source, language: uiLanguage)),
                  ],
                ),
                const SizedBox(height: 12),
                DockDocentPreview(
                  place: currentPlace,
                  language: uiLanguage,
                  script: docentScript,
                  action: docentAction,
                  audioLoading: audioLoading,
                  audioError: audioError,
                  docentAudio: docentAudio,
                  canFetchAudio: canFetchAudio,
                  onFetchAudio: onFetchAudio,
                  onAddToPlan: onAddToPlan,
                  onOpenDetail: onOpenDetail,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyDockContent extends StatelessWidget {
  const _EmptyDockContent({
    required this.language,
    this.errorLabel,
    this.recoveryPending = false,
    this.onRetry,
  });

  final String language;
  final String? errorLabel;
  final bool recoveryPending;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final hasError = errorLabel != null && errorLabel!.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: hasError ? const Color(0xFFFFF3E8) : const Color(0xFFEAF2FF),
            shape: BoxShape.circle,
          ),
          child: Icon(
            hasError ? Icons.refresh_outlined : Icons.travel_explore,
            color: hasError ? const Color(0xFFB45309) : const Color(0xFF2B6CB0),
            size: 21,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasError
                    ? _copy(
                        language,
                        ko: '추천 연결을 다시 확인하고 있어요',
                        en: 'Checking recommendations again',
                      )
                    : _copy(
                        language,
                        ko: '추천을 준비 중입니다',
                        en: 'Preparing recommendations',
                      ),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF111827),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                hasError
                    ? _copy(
                        language,
                        ko: recoveryPending
                            ? '잠시 후 자동으로 다시 시도합니다. 지금 바로 다시 시도할 수도 있어요.'
                            : '잠시 후 다시 시도해 주세요. 필요하면 지금 바로 다시 시도할 수 있어요.',
                        en: recoveryPending
                            ? 'Retrying automatically soon. You can also retry right now.'
                            : 'Please try again shortly. You can also retry right now.',
                      )
                    : _copy(
                        language,
                        ko: '공식 데이터가 확인된 장소만 표시합니다.',
                        en: 'Only places backed by official data are shown.',
                      ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (hasError && onRetry != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('dock-error-retry'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(
                      _copy(language, ko: '지금 다시 시도', en: 'Retry now'),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MapDraggableSheet extends StatelessWidget {
  const _MapDraggableSheet({
    required this.activeSheet,
    required this.place,
    required this.places,
    required this.weather,
    required this.language,
    required this.loading,
    required this.intervention,
    required this.dailyPlan,
    required this.docentScript,
    required this.docentAudio,
    required this.tourAudio,
    required this.audioLoading,
    required this.audioError,
    required this.tourAudioLoading,
    required this.tourAudioError,
    required this.liveSpeechEnabled,
    required this.source,
    required this.showEvidence,
    required this.savedPlaceIds,
    required this.detailDocentPlayedPlaceIds,
    required this.onToggleEvidence,
    required this.onToggleSavedPlace,
    required this.onAddToPlan,
    required this.onFetchAudio,
    required this.onFetchTourAudio,
    required this.onSelectPlace,
    required this.onRefresh,
    required this.onClose,
  });

  final _ActiveMapSheet activeSheet;
  final LalaPlace? place;
  final List<LalaPlace> places;
  final LalaWeather? weather;
  final String language;
  final bool loading;
  final LalaIntervention? intervention;
  final LalaDailyPlan? dailyPlan;
  final LalaDocentScript? docentScript;
  final LalaAudioResponse? docentAudio;
  final LalaAudioResponse? tourAudio;
  final bool audioLoading;
  final String? audioError;
  final bool tourAudioLoading;
  final String? tourAudioError;
  final bool liveSpeechEnabled;
  final String? source;
  final bool showEvidence;
  final Set<String> savedPlaceIds;
  final Set<String> detailDocentPlayedPlaceIds;
  final VoidCallback onToggleEvidence;
  final ValueChanged<String> onToggleSavedPlace;
  final VoidCallback onAddToPlan;
  final VoidCallback onFetchAudio;
  final VoidCallback onFetchTourAudio;
  final ValueChanged<LalaPlace> onSelectPlace;
  final VoidCallback onRefresh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final title = switch (activeSheet) {
      _ActiveMapSheet.detail => language == 'en' ? 'Details' : '장소 상세',
      _ActiveMapSheet.planner => language == 'en' ? 'Daily Plan' : '하루 일정',
      _ActiveMapSheet.weather => language == 'en' ? 'Weather' : '날씨',
      _ActiveMapSheet.tour => language == 'en' ? 'Food Tour' : '맛집 투어',
    };
    final icon = switch (activeSheet) {
      _ActiveMapSheet.detail => Icons.place_outlined,
      _ActiveMapSheet.planner => Icons.route_outlined,
      _ActiveMapSheet.weather => Icons.wb_cloudy_outlined,
      _ActiveMapSheet.tour => Icons.restaurant_menu,
    };
    final initialSize = switch (activeSheet) {
      _ActiveMapSheet.detail => 0.66,
      _ActiveMapSheet.planner => 0.52,
      _ActiveMapSheet.weather => 0.44,
      _ActiveMapSheet.tour => 0.68,
    };

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
          ),
        ),
        DraggableScrollableSheet(
          initialChildSize: initialSize,
          minChildSize: 0.30,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.98),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 32,
                    offset: Offset(0, -12),
                    color: Color(0x26000000),
                  ),
                ],
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E0),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(icon, color: const Color(0xFF2B6CB0)),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: const Color(0xFF111827),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: _copy(language, ko: '닫기', en: 'Close'),
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  switch (activeSheet) {
                    _ActiveMapSheet.detail => _FeaturedPlacePanel(
                      place: place,
                      language: language,
                      weather: weather,
                      intervention: intervention,
                      dailyPlan: dailyPlan,
                      docentScript: docentScript,
                      docentAudio: docentAudio,
                      audioLoading: audioLoading,
                      audioError: audioError,
                      liveSpeechEnabled: liveSpeechEnabled,
                      source: source,
                      showEvidence: showEvidence,
                      savedPlaceIds: savedPlaceIds,
                      detailDocentPlayedPlaceIds: detailDocentPlayedPlaceIds,
                      onToggleEvidence: onToggleEvidence,
                      onToggleSavedPlace: onToggleSavedPlace,
                      onAddToPlan: onAddToPlan,
                      onFetchAudio: onFetchAudio,
                    ),
                    _ActiveMapSheet.planner => PlannerSheetContent(
                      language: language,
                      weather: weather,
                      dailyPlan: dailyPlan,
                      intervention: intervention,
                      loading: loading,
                      onRegenerate: onRefresh,
                      onSelectPlace: onSelectPlace,
                    ),
                    _ActiveMapSheet.weather => WeatherSheetContent(
                      language: language,
                      weather: weather,
                    ),
                    _ActiveMapSheet.tour => TourSheetContent(
                      places: places,
                      language: language,
                      tourAudio: tourAudio,
                      audioLoading: tourAudioLoading,
                      audioError: tourAudioError,
                      liveSpeechEnabled: liveSpeechEnabled,
                      onFetchAudio: onFetchTourAudio,
                      onSelectPlace: onSelectPlace,
                    ),
                  },
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _LocationConsentOverlay extends StatelessWidget {
  const _LocationConsentOverlay({
    required this.language,
    required this.onOpenSettings,
    required this.onRetryLocation,
  });

  final String language;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetryLocation;

  @override
  Widget build(BuildContext context) {
    final isEnglish = language == 'en';
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.34),
      child: SafeArea(
        child: Center(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 420),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 32,
                  offset: Offset(0, 16),
                  color: Color(0x33000000),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FB),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.location_off_outlined,
                    color: Color(0xFF2B6CB0),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isEnglish ? 'Location consent is off' : '위치기반 추천이 꺼져 있어요',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isEnglish
                      ? 'LALA uses your approximate location only to recommend nearby public culture, weather, and local spending signals.'
                      : 'LALA는 주변 문화·날씨·지역 소비 신호를 연결하기 위해 대략적인 위치 동의가 필요합니다.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4B5563),
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.tune),
                  label: Text(isEnglish ? 'Turn on location' : '위치 동의 켜기'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const ValueKey('location-consent-retry'),
                  onPressed: onRetryLocation,
                  icon: const Icon(Icons.my_location_outlined),
                  label: Text(isEnglish ? 'Retry location' : '다시 확인'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: const Color(0xFF2B6CB0),
                    side: const BorderSide(color: Color(0xFFB9D4F3)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// C3: PlannerLoadingCard → features/planner/widgets/planner_loading_card.dart (PlannerLoadingCard).

// C3: TourTag → features/tour/widgets/tour_tag.dart (TourTag).

// C3: TourScriptCard → features/docent/widgets/tour_script_card.dart (TourScriptCard).
// C3: TourAudioBar → features/docent/widgets/tour_audio_bar.dart (TourAudioBar).

String _tourGuideScript(List<LalaPlace> places, String language) =>
    tourGuideScript(places, language);
// C3: WeatherForecastChartCard -> features/weather/widgets/weather_forecast_chart_card.dart.

// C3-2: WeatherChartPoint + WeatherForecastChartPainter → features/weather/widgets/weather_forecast_chart_painter.dart.

// C3: WeatherUnavailableCard -> features/weather/widgets/weather_unavailable_card.dart.

// C3: WeatherFact -> features/weather/widgets/weather_fact.dart.

// C3: ForecastChip -> features/weather/widgets/forecast_chip.dart.

// C3: _MutedSheetCard → shared/widgets/muted_sheet_card.dart (MutedSheetCard).
typedef _MutedSheetCard = MutedSheetCard;

class _FeaturedPlacePanel extends StatelessWidget {
  const _FeaturedPlacePanel({
    required this.place,
    required this.language,
    required this.weather,
    required this.intervention,
    required this.dailyPlan,
    required this.docentScript,
    required this.docentAudio,
    required this.audioLoading,
    required this.audioError,
    required this.liveSpeechEnabled,
    required this.source,
    required this.showEvidence,
    required this.savedPlaceIds,
    required this.detailDocentPlayedPlaceIds,
    required this.onToggleEvidence,
    required this.onToggleSavedPlace,
    required this.onAddToPlan,
    required this.onFetchAudio,
  });

  final LalaPlace? place;
  final String language;
  final LalaWeather? weather;
  final LalaIntervention? intervention;
  final LalaDailyPlan? dailyPlan;
  final LalaDocentScript? docentScript;
  final LalaAudioResponse? docentAudio;
  final bool audioLoading;
  final String? audioError;
  final bool liveSpeechEnabled;
  final String? source;
  final bool showEvidence;
  final Set<String> savedPlaceIds;
  final Set<String> detailDocentPlayedPlaceIds;
  final VoidCallback onToggleEvidence;
  final ValueChanged<String> onToggleSavedPlace;
  final VoidCallback onAddToPlan;
  final VoidCallback onFetchAudio;

  @override
  Widget build(BuildContext context) {
    final currentPlace = place;
    if (currentPlace == null) {
      return _MutedSheetCard(
        icon: Icons.place_outlined,
        label: _copy(
          language,
          ko: '이 주변 추천을 준비 중입니다. 지도를 움직이거나 잠시 뒤 다시 시도해 주세요.',
          en: 'Recommendations are still being prepared here. Move the map or try again shortly.',
        ),
      );
    }
    final score = currentPlace.score;
    final components = score?.components;
    final slots = dailyPlan?.slots ?? const <LalaPlanSlot>[];
    final effectiveDocent = docentScript?.placeId == currentPlace.placeId
        ? docentScript
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FeaturedPlaceHeader(
          place: currentPlace,
          language: language,
          showEvidence: showEvidence,
          saved: savedPlaceIds.contains(currentPlace.placeId),
          onToggleSaved: () => onToggleSavedPlace(currentPlace.placeId),
        ),
        const SizedBox(height: 12),
        _PlaceContextCard(
          place: currentPlace,
          language: language,
          weather: weather,
          showEvidence: showEvidence,
        ),
        if (_shouldShowEventInfo(currentPlace)) ...[
          const SizedBox(height: 12),
          EventInfoCard(place: currentPlace, language: language),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onToggleEvidence,
            icon: Icon(
              showEvidence ? Icons.visibility_off : Icons.insights_outlined,
            ),
            label: Text(
              showEvidence
                  ? _copy(language, ko: '점수/근거 숨기기', en: 'Hide signals')
                  : _copy(language, ko: '점수/근거 보기', en: 'Show signals'),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1A202C),
              side: const BorderSide(color: Color(0xFFD7E3F5)),
            ),
          ),
        ),
        if (showEvidence) ...[
          const SizedBox(height: 12),
          SignalGrid(
            language: language,
            localSpending: components?.localSpendingScore,
            demandDispersion: components?.demandDispersionScore,
            cultureRelevance: components?.cultureRelevanceScore,
            weatherFit: components?.weatherFitScore,
          ),
        ],
        const SizedBox(height: 12),
        DocentSubtitle(
          place: currentPlace,
          language: language,
          script: effectiveDocent?.script,
          action:
              intervention?.recommendedAction ??
              (slots.isEmpty ? null : slots.first.title),
          audioLoading: audioLoading,
          audioError: audioError,
          docentAudio: docentAudio,
          canFetchAudio:
              liveSpeechEnabled &&
              _hasUsableDocentScript(effectiveDocent?.script, language) &&
              !audioLoading &&
              !detailDocentPlayedPlaceIds.contains(currentPlace.placeId),
          onFetchAudio: onFetchAudio,
          onAddToPlan: onAddToPlan,
        ),
        if (showEvidence) ...[
          const SizedBox(height: 12),
          _PublicDataProofRow(
            place: currentPlace,
            language: language,
            source: source ?? currentPlace.source,
            weather: weather,
            score: score,
          ),
        ],
      ],
    );
  }
}

class _PlaceContextCard extends StatelessWidget {
  const _PlaceContextCard({
    required this.place,
    required this.language,
    required this.weather,
    required this.showEvidence,
  });

  final LalaPlace place;
  final String language;
  final LalaWeather? weather;
  final bool showEvidence;

  @override
  Widget build(BuildContext context) {
    final facts = _placeContextFacts(
      place: place,
      language: language,
      weather: weather,
      includeEvidence: showEvidence,
    );
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FB),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  _placeContextIcon(place.category),
                  color: const Color(0xFF2B6CB0),
                  size: 19,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _placeContextTitle(place.category, language),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: facts
                .map(
                  (fact) =>
                      ContextFactChip(icon: fact.icon, label: fact.label),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

// C3: ContextFact → features/place/widgets/context_fact.dart (ContextFact).
// C3: ContextFactChip → features/place/widgets/context_fact_chip.dart (ContextFactChip).

// C3: EventStatusPill → features/place/widgets/event_status_pill.dart (EventStatusPill).

// C3: SignalGrid → features/place/widgets/signal_grid.dart (SignalGrid).
// C3: SignalMeter → features/place/widgets/signal_meter.dart (SignalMeter).

class _PublicDataProofRow extends StatelessWidget {
  const _PublicDataProofRow({
    required this.place,
    required this.language,
    required this.source,
    required this.weather,
    required this.score,
  });

  final LalaPlace place;
  final String language;
  final String? source;
  final LalaWeather? weather;
  final LalaPlaceScore? score;

  @override
  Widget build(BuildContext context) {
    final labels = _proofSourceLabels(
      place: place,
      language: language,
      source: source,
      weather: weather,
      score: score,
    );
    final title =
        _hasFallbackProofSource(
          place: place,
          source: source,
          weather: weather,
          score: score,
        )
        ? _copy(language, ko: '제한적 데이터 근거', en: 'Limited data evidence')
        : _copy(language, ko: '공식 데이터 근거', en: 'Official data evidence');
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w900,
            ),
          ),
          ...labels.map((label) => ProofChip(label: label)),
        ],
      ),
    );
  }
}

bool _hasFallbackProofSource({
  required LalaPlace place,
  required String? source,
  required LalaWeather? weather,
  required LalaPlaceScore? score,
}) {
  final features = score?.features ?? const <String, dynamic>{};
  final inputSources = _stringList(features['input_sources']);
  return _isFallbackSourceCode(source) ||
      _isFallbackSourceCode(place.source) ||
      _isFallbackSourceCode(place.upstreamSource) ||
      _isFallbackSourceCode(weather?.source) ||
      _isFallbackSourceCode(score?.dataBasis) ||
      _isFallbackSourceCode(features['primary_source']?.toString()) ||
      inputSources.any(_isFallbackSourceCode);
}

List<String> _proofSourceLabels({
  required LalaPlace place,
  required String language,
  required String? source,
  required LalaWeather? weather,
  required LalaPlaceScore? score,
}) {
  final labels = <String>[];
  void add(String? label) {
    final trimmed = label?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == '-') {
      return;
    }
    if (!labels.contains(trimmed)) {
      labels.add(trimmed);
    }
  }

  final features = score?.features ?? const <String, dynamic>{};
  add(_sourceLabel(source, language: language));
  add(
    _externalSourceLabel(
      place.upstreamSource ?? features['primary_source'],
      language: language,
    ),
  );
  if (score != null) {
    add(_basisLabel(score.dataBasis, language: language));
  }

  final inputSources = _stringList(features['input_sources']);
  if (inputSources.any((source) => source.startsWith('economy.'))) {
    add(_copy(language, ko: '카드 소비', en: 'Card spending'));
  }
  if (inputSources.contains('culture.events') ||
      _asFeatureInt(features['culture_event_count']) > 0) {
    add(_copy(language, ko: '문화행사 데이터', en: 'Culture events'));
  }
  if (inputSources.contains('travel.weather_observations') ||
      score?.components.weatherFitScore != null ||
      weather != null) {
    add(
      weather == null
          ? _copy(language, ko: '날씨 관측', en: 'Weather observations')
          : _copy(
              language,
              ko: '날씨 ${_dustSituationLabel(weather.dust, language)}',
              en: 'Weather ${_dustSituationLabel(weather.dust, language, includePrefix: false)}',
            ),
    );
  }
  if (inputSources.contains('travel.places')) {
    add(_copy(language, ko: '공식 장소 DB', en: 'Official place DB'));
  }
  if (_stringList(features['dynamic_source_types']).isNotEmpty ||
      _stringList(features['rag_source_types']).isNotEmpty) {
    add(_copy(language, ko: '검색 컨텍스트', en: 'RAG context'));
  }
  return labels.take(8).toList(growable: false);
}

// C3: ProofChip → features/place/widgets/proof_chip.dart (ProofChip).

class _LegacyMapCanvas extends StatelessWidget {
  const _LegacyMapCanvas({
    required this.places,
    required this.selectedPlace,
    required this.weather,
    required this.kakaoJavascriptKey,
    required this.language,
    required this.mapFocusLat,
    required this.mapFocusLng,
    required this.mapLevel,
    required this.onSelectPlaceId,
    required this.onSelectCluster,
    required this.onCameraIdle,
  });

  final List<LalaPlace> places;
  final LalaPlace? selectedPlace;
  final LalaWeather? weather;
  final String kakaoJavascriptKey;
  final String language;
  final double? mapFocusLat;
  final double? mapFocusLng;
  final int mapLevel;
  final ValueChanged<String> onSelectPlaceId;
  final ValueChanged<KakaoMapPlace> onSelectCluster;
  final ValueChanged<KakaoMapCamera> onCameraIdle;

  @override
  Widget build(BuildContext context) {
    final selected = selectedPlace;
    final centerLat = mapFocusLat ?? selected?.lat ?? 37.2823;
    final centerLng = mapFocusLng ?? selected?.lng ?? 127.0179;
    final mapPlaces = clusterMapPlacesForMap(
      places: places,
      selected: selected,
      mapLevel: mapLevel,
      language: language,
    );

    void handleMapFeatureTap(String featureId) {
      for (final marker in mapPlaces) {
        if (marker.id == featureId) {
          if (marker.isCluster) {
            onSelectCluster(marker);
            return;
          }
          break;
        }
      }
      onSelectPlaceId(featureId);
    }

    return Stack(
      children: [
        Positioned.fill(
          child: buildKakaoMapView(
            javascriptKey: kakaoJavascriptKey,
            language: language,
            centerLat: centerLat,
            centerLng: centerLng,
            level: mapLevel,
            places: mapPlaces,
            onPlaceTap: handleMapFeatureTap,
            onCameraIdle: onCameraIdle,
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.18),
                    Colors.white.withValues(alpha: 0.02),
                    Colors.white.withValues(alpha: 0.26),
                  ],
                  stops: const [0, 0.46, 1],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

@visibleForTesting
List<KakaoMapPlace> clusterMapPlacesForMap({
  required List<LalaPlace> places,
  required LalaPlace? selected,
  required int mapLevel,
  required String language,
}) {
  final selectedId = selected?.placeId;
  final expandedPinFloor = mapLevel >= 10 ? 36 : 48;
  final selectedMarkers = <KakaoMapPlace>[];
  final expandedMarkers = <KakaoMapPlace>[];
  final buckets = <String, List<LalaPlace>>{};
  final shouldUseClusters = places.length >= 80 && mapLevel >= 10;
  var expandedPinCount = 0;
  final orderedPlaces = [...places]
    ..sort((a, b) {
      final selectedCompare = _selectedPlaceSortValue(
        a.placeId,
        selectedId,
      ).compareTo(_selectedPlaceSortValue(b.placeId, selectedId));
      if (selectedCompare != 0) {
        return selectedCompare;
      }
      final distanceCompare = a.distanceM.compareTo(b.distanceM);
      if (distanceCompare != 0) {
        return distanceCompare;
      }
      return _placeDisplayName(
        a,
        language,
      ).compareTo(_placeDisplayName(b, language));
    });

  KakaoMapPlace toMapPlace(LalaPlace place, {bool selected = false}) {
    return KakaoMapPlace(
      id: place.placeId,
      name: _placeDisplayName(place, language),
      category: place.category,
      lat: place.lat,
      lng: place.lng,
      selected: selected,
    );
  }

  for (final place in orderedPlaces.take(60)) {
    if (place.placeId == selectedId) {
      selectedMarkers.add(toMapPlace(place, selected: true));
      continue;
    }
    if (!shouldUseClusters) {
      selectedMarkers.add(toMapPlace(place));
      continue;
    }
    if (expandedPinCount < expandedPinFloor) {
      expandedMarkers.add(toMapPlace(place));
      expandedPinCount += 1;
      continue;
    }
    final latBucket = (place.lat * 180).round();
    final lngBucket = (place.lng * 180).round();
    final key = '${place.category}:$latBucket:$lngBucket';
    buckets.putIfAbsent(key, () => <LalaPlace>[]).add(place);
  }

  final clustered = <KakaoMapPlace>[];
  for (final entry in buckets.entries) {
    final group = entry.value;
    if (group.length >= 3) {
      final lat =
          group.fold<double>(0, (sum, place) => sum + place.lat) / group.length;
      final lng =
          group.fold<double>(0, (sum, place) => sum + place.lng) / group.length;
      clustered.add(
        KakaoMapPlace(
          id: 'cluster-${entry.key}',
          name: _copy(
            language,
            ko: '${group.length}곳',
            en: '${group.length} places',
          ),
          category: group.first.category,
          lat: lat,
          lng: lng,
          clusterCount: group.length,
          clusterMemberIds: group
              .map((place) => place.placeId)
              .toList(growable: false),
        ),
      );
    } else {
      clustered.addAll(group.map(toMapPlace));
    }
  }

  return [...clustered, ...expandedMarkers, ...selectedMarkers];
}

int _selectedPlaceSortValue(String placeId, String? selectedId) {
  if (selectedId == null) {
    return 1;
  }
  return placeId == selectedId ? 0 : 1;
}

class _MapRoundButton extends StatelessWidget {
  const _MapRoundButton({
    this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final Key? buttonKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Listener(
          key: buttonKey,
          behavior: HitTestBehavior.opaque,
          onPointerUp: (_) => onPressed(),
          child: Material(
            color: Colors.white.withValues(alpha: 0.95),
            elevation: 7,
            shadowColor: const Color(0x22000000),
            shape: const CircleBorder(
              side: BorderSide(color: Color(0xFFE2E8F0), width: 1.4),
            ),
            child: SizedBox.square(
              dimension: 46,
              child: Icon(icon, size: 22, color: const Color(0xFF1A202C)),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingMapControls extends StatelessWidget {
  const _FloatingMapControls({
    required this.voiceEnabled,
    required this.autoDocentEnabled,
    required this.language,
    required this.onToggleVoice,
    required this.onToggleAutoDocent,
    required this.onReturnToLocation,
  });

  final bool voiceEnabled;
  final bool autoDocentEnabled;
  final String language;
  final VoidCallback onToggleVoice;
  final VoidCallback onToggleAutoDocent;
  final VoidCallback onReturnToLocation;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MapFab(
          key: const ValueKey('voice-toggle'),
          tooltip: language == 'en'
              ? (voiceEnabled ? 'Mute voice' : 'Enable voice')
              : (voiceEnabled ? '음성 끄기' : '음성 켜기'),
          icon: voiceEnabled ? Icons.volume_up : Icons.volume_off,
          label: language == 'en'
              ? (voiceEnabled ? 'Voice on' : 'Voice off')
              : (voiceEnabled ? '음성 켜짐' : '음성 꺼짐'),
          active: voiceEnabled,
          statusLabel: language == 'en'
              ? (voiceEnabled ? 'ON' : 'OFF')
              : (voiceEnabled ? '켬' : '끔'),
          onPressed: onToggleVoice,
        ),
        const SizedBox(width: 14),
        AutoDocentFab(
          key: const ValueKey('auto-docent-toggle'),
          tooltip: language == 'en'
              ? (autoDocentEnabled ? 'Auto guide off' : 'Auto guide on')
              : (autoDocentEnabled ? '자동 도슨트 끄기' : '자동 도슨트 켜기'),
          label: language == 'en'
              ? (autoDocentEnabled ? 'Auto on' : 'Auto off')
              : (autoDocentEnabled ? '자동 켜짐' : '자동 꺼짐'),
          active: autoDocentEnabled,
          statusLabel: language == 'en'
              ? (autoDocentEnabled ? 'ON' : 'OFF')
              : (autoDocentEnabled ? '켬' : '끔'),
          onPressed: onToggleAutoDocent,
        ),
        const SizedBox(width: 14),
        _MapFab(
          key: const ValueKey('location-refresh'),
          tooltip: language == 'en' ? 'My location' : '내 위치',
          icon: Icons.my_location,
          label: language == 'en' ? 'My location' : '내 위치',
          active: true,
          statusLabel: null,
          onPressed: onReturnToLocation,
        ),
      ],
    );
  }
}

// C3: AutoDocentFab → features/docent/widgets/auto_docent_fab.dart (AutoDocentFab).

class _MapFab extends StatelessWidget {
  const _MapFab({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.active,
    required this.statusLabel,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final bool active;
  final String? statusLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: label,
        child: Badge(
          isLabelVisible: statusLabel != null,
          alignment: Alignment.topRight,
          backgroundColor: active
              ? const Color(0xFFF5C842)
              : const Color(0xFF64748B),
          textColor: active ? const Color(0xFF1A202C) : Colors.white,
          label: statusLabel == null
              ? null
              : Text(
                  statusLabel!,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
          child: IconButton.filled(
            onPressed: onPressed,
            icon: Icon(icon, size: 22),
            style: IconButton.styleFrom(
              fixedSize: const Size.square(46),
              backgroundColor: active
                  ? const Color(0xFF2B6CB0)
                  : const Color(0xFF1A202C).withValues(alpha: 0.82),
              foregroundColor: Colors.white,
              shape: CircleBorder(
                side: BorderSide(
                  color: active
                      ? Colors.white.withValues(alpha: 0.86)
                      : Colors.white.withValues(alpha: 0.22),
                  width: 1.6,
                ),
              ),
              elevation: 8,
            ),
          ),
        ),
      ),
    );
  }
}

// C3: PlaceThumb → features/place/widgets/place_thumb.dart (PlaceThumb).
// C3: PlaceImage → features/place/widgets/place_image.dart (PlaceImage).
// C3: hasOfficialPlaceImage / normalizedPlaceImageUri → features/place/place_helpers.dart.
// C3: CategoryBadge → features/place/widgets/category_badge.dart (CategoryBadge).

// C3: CompactInfoTile -> shared/widgets/compact_info_tile.dart.

class _LalaWordmark extends StatelessWidget {
  const _LalaWordmark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'LALA',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              blurRadius: 12,
              offset: Offset(0, 4),
              color: Color(0x14000000),
            ),
          ],
        ),
        child: const Text(
          'LALA',
          style: TextStyle(
            color: Color(0xFF2B6CB0),
            fontSize: 21,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: active ? color : Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 12,
                  offset: Offset(0, 4),
                  color: Color(0x12000000),
                ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                color: active
                    ? (color == const Color(0xFFF5C842)
                          ? const Color(0xFF1A202C)
                          : Colors.white)
                    : const Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// C3: SmallStatusPill(공용) → shared/widgets/small_status_pill.dart (SmallStatusPill).

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A202C),
      ),
    );
  }
}

// C3: TinyMeta → shared/widgets/tiny_meta.dart (TinyMeta).

class _MapToast extends StatelessWidget {
  const _MapToast({
    required this.icon,
    required this.label,
    required this.color,
    this.actionKey = const ValueKey('map-error-retry'),
    this.secondaryActionKey = const ValueKey('map-secondary-action'),
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Key actionKey;
  final Key secondaryActionKey;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onErrorContainer;
    final accent = Theme.of(context).colorScheme.error;
    final actions = <Widget>[
      if (actionLabel != null && onAction != null)
        TextButton(
          key: actionKey,
          onPressed: onAction,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: accent,
            backgroundColor: color.withValues(alpha: 0.42),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          child: Text(actionLabel!),
        ),
      if (secondaryActionLabel != null && onSecondaryAction != null)
        TextButton(
          key: secondaryActionKey,
          onPressed: onSecondaryAction,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: const Color(0xFF2B6CB0),
            backgroundColor: const Color(0xFFE6F0FB),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          child: Text(secondaryActionLabel!),
        ),
    ];

    Widget message() {
      return Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );
    }

    Widget actionWrap() {
      return Wrap(spacing: 4, runSpacing: 4, children: actions);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = math.max(
          0.0,
          MediaQuery.sizeOf(context).width - 32,
        );
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth;
        final toastWidth = math.min(520.0, availableWidth);
        final compact = actions.length > 1 && toastWidth < 440;
        return SizedBox(
          width: toastWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(compact ? 18 : 999),
              border: Border.all(color: color.withValues(alpha: 0.78)),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 14,
                  offset: Offset(0, 5),
                  color: Color(0x16000000),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: compact
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        message(),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: actionWrap(),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: message()),
                        if (actions.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          actionWrap(),
                        ],
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

// C3-1: _InterventionToast → features/intervention/widgets/intervention_toast.dart (InterventionToast).

// C3: EmptyPlaceState → features/place/widgets/empty_place_state.dart (EmptyPlaceState).

bool _isEnglish(String language) => isLalaEnglish(language);

bool shouldReloadPlacesForMapMove({
  required bool hasAnyPlaces,
  required double? lastFetchLat,
  required double? lastFetchLng,
  required double currentLat,
  required double currentLng,
  double thresholdMeters = 250,
}) {
  if (!hasAnyPlaces || lastFetchLat == null || lastFetchLng == null) {
    return true;
  }
  return _distanceMeters(lastFetchLat, lastFetchLng, currentLat, currentLng) >=
      thresholdMeters;
}

Future<T> loadWithSingleRetry<T>(
  Future<T> Function() loader, {
  required bool shouldRetry,
  Duration retryDelay = const Duration(milliseconds: 600),
}) async {
  try {
    return await loader();
  } on Object {
    if (!shouldRetry) {
      rethrow;
    }
    await Future<void>.delayed(retryDelay);
    return await loader();
  }
}

bool shouldReloadWeatherForMapMove({
  required bool force,
  required bool hasWeather,
  required DateTime? lastFetchAt,
  required double? lastFetchLat,
  required double? lastFetchLng,
  required double currentLat,
  required double currentLng,
  Duration maxAge = const Duration(minutes: 10),
  double thresholdMeters = 10000,
  DateTime? now,
}) {
  if (force || !hasWeather || lastFetchAt == null) {
    return true;
  }
  if (lastFetchLat == null || lastFetchLng == null) {
    return true;
  }
  final effectiveNow = now ?? DateTime.now();
  if (effectiveNow.difference(lastFetchAt) >= maxAge) {
    return true;
  }
  return _distanceMeters(lastFetchLat, lastFetchLng, currentLat, currentLng) >=
      thresholdMeters;
}

double _distanceMeters(
  double fromLat,
  double fromLng,
  double toLat,
  double toLng,
) {
  const earthRadiusMeters = 6371000.0;
  final fromLatRadians = fromLat * math.pi / 180;
  final toLatRadians = toLat * math.pi / 180;
  final deltaLat = (toLat - fromLat) * math.pi / 180;
  final deltaLng = (toLng - fromLng) * math.pi / 180;
  final haversine =
      math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(fromLatRadians) *
          math.cos(toLatRadians) *
          math.sin(deltaLng / 2) *
          math.sin(deltaLng / 2);
  final centralAngle =
      2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  return earthRadiusMeters * centralAngle;
}

String _copy(String language, {required String ko, required String en}) {
  return lalaCopy(language, ko: ko, en: en);
}

String _recommendationStatusMessage(
  String language, {
  required bool recoveryPending,
}) {
  if (recoveryPending) {
    return _copy(
      language,
      ko: '추천 연결이 잠시 지연되고 있어요. 자동으로 다시 불러오는 중입니다.',
      en: 'Recommendations are taking longer than expected. Retrying automatically.',
    );
  }
  return _copy(
    language,
    ko: '추천 장소를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
    en: 'Could not load recommendations. Please try again shortly.',
  );
}

String? _localizedUiMessage(String? value, String language) {
  final localized = _singleLanguageText(value, language);
  if (localized != null && localized.isNotEmpty) {
    return localized;
  }
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return _copy(
    language,
    ko: '지금 정보를 불러오지 못했어요.',
    en: 'Could not load the information right now.',
  );
}

String _safeUiErrorMessage(String? value, {String? fallbackMessage}) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return fallbackMessage ?? _requestFailureMessage();
  }
  if (_containsKorean(trimmed)) {
    return trimmed;
  }
  return fallbackMessage ?? _requestFailureMessage();
}

String _recommendationLoadFailureMessage(String language) {
  return _copy(
    language,
    ko: '추천 장소를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
    en: 'Could not load recommendations. Please try again shortly.',
  );
}

String _docentAudioFailureMessage() {
  return '도슨트 음성을 준비하지 못했어요. 스크립트는 계속 볼 수 있습니다. Could not prepare docent audio. The script is still available.';
}

String _tourAudioFailureMessage() {
  return '투어 음성을 준비하지 못했어요. 추천 코스는 계속 볼 수 있습니다. Could not prepare tour audio. The route is still available.';
}

String _requestFailureMessage() {
  return '지금 정보를 불러오지 못했어요.';
}

// C3: _locationLabel → shared/l10n/place_labels.dart (locationLabel).
String _locationLabel(String? value, String language) =>
    locationLabel(value, language);

String _interventionToastLabel(LalaIntervention intervention, String language) {
  final place = intervention.place == null
      ? null
      : _placeDisplayName(intervention.place!, language);
  final reason = intervention.reason.trim();
  final action = intervention.recommendedAction.trim();
  final localizedReason = _singleLanguageText(reason, language);
  final localizedAction = _singleLanguageText(action, language);

  if (_isEnglish(language)) {
    if (localizedReason != null && localizedAction != null) {
      return '$localizedReason · $localizedAction';
    }
    if (localizedReason != null) {
      return localizedReason;
    }
    if (localizedAction != null) {
      return localizedAction;
    }
    if (place != null) {
      return 'Weather changed. Adjust the route near $place.';
    }
    return 'Weather changed. Review today\'s route.';
  }

  if (localizedReason != null) {
    return localizedReason;
  }
  if (localizedAction != null) {
    return localizedAction;
  }
  if (place != null) {
    return '날씨가 바뀌었어요. $place 중심으로 동선을 다시 확인해보세요.';
  }
  return '날씨가 바뀌었어요. 하루 일정을 다시 확인해보세요.';
}

// C3: categoryLabel / categoryFilterLabel / railCategoryLabel → features/place/place_helpers.dart.

List<LalaPlace> _filterPlaces(List<LalaPlace> places, String category) {
  if (category == 'all') {
    return places;
  }
  return places.where((place) => place.category == category).toList();
}

List<LalaPlace> _prioritizeClusterMembers(
  List<LalaPlace> places,
  List<String> focusedClusterMemberIds,
) {
  if (places.isEmpty || focusedClusterMemberIds.isEmpty) {
    return places;
  }
  final memberOrder = <String, int>{
    for (final entry in focusedClusterMemberIds.indexed) entry.$2: entry.$1,
  };
  final clusterPlaces =
      places
          .where((place) => memberOrder.containsKey(place.placeId))
          .toList(growable: false)
        ..sort(
          (a, b) => memberOrder[a.placeId]!.compareTo(memberOrder[b.placeId]!),
        );
  if (clusterPlaces.isEmpty) {
    return places;
  }
  final clusterPlaceIds = clusterPlaces.map((place) => place.placeId).toSet();
  return [
    ...clusterPlaces,
    ...places.where((place) => !clusterPlaceIds.contains(place.placeId)),
  ];
}

List<LalaPlace> _restaurantTourPlaces(List<LalaPlace> places) {
  final restaurants = places
      .where((place) => place.category == 'restaurant')
      .toList(growable: false);
  if (restaurants.isEmpty) {
    return const <LalaPlace>[];
  }
  final sorted = [...restaurants]
    ..sort((a, b) {
      final scoreCompare = (b.score?.components.localSpendingScore ?? 0)
          .compareTo(a.score?.components.localSpendingScore ?? 0);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return a.distanceM.compareTo(b.distanceM);
    });
  return sorted.take(6).toList(growable: false);
}

LalaPlace? _placeById(List<LalaPlace> places, String? placeId) {
  if (placeId == null) {
    return null;
  }
  for (final place in places) {
    if (place.placeId == placeId) {
      return place;
    }
  }
  return null;
}

// C3: _placeDisplayName / _placeRegionLabel → shared/l10n/place_labels.dart.
String _placeDisplayName(LalaPlace place, String language) =>
    placeDisplayName(place, language);

String _placeRegionLabel(LalaPlace place, String language) =>
    placeRegionLabel(place, language);

// C3: 다국어 텍스트 헬퍼 → shared/l10n/multi_language_text.dart.
//     _singleLanguageText/_containsKorean/_looksEnglishText 는 외부 호출이 있어 forwarder 유지.
//     (extract*/hasMixedKoreanEnglish/cleanLocalizedFragment 는 외부 사용 없어 본문 제거)
bool _containsKorean(String value) => containsKorean(value);

bool _looksEnglishText(String value) => looksEnglishText(value);

String? _singleLanguageText(String? value, String language) =>
    singleLanguageText(value, language);

bool _shouldShowEventInfo(LalaPlace place) => shouldShowEventInfo(place);
String _placeContextTitle(String category, String language) {
  return switch (category) {
    'event' => _copy(language, ko: '행사 맥락', en: 'Event context'),
    'restaurant' => _copy(language, ko: '맛집 로컬 맥락', en: 'Food local context'),
    'culture_venue' => _copy(language, ko: '문화 연계 맥락', en: 'Culture context'),
    _ => _copy(language, ko: '로컬 맥락', en: 'Local context'),
  };
}

IconData _placeContextIcon(String category) {
  return switch (category) {
    'event' => Icons.event_available_outlined,
    'restaurant' => Icons.restaurant_menu,
    'culture_venue' => Icons.account_balance_outlined,
    _ => Icons.travel_explore_outlined,
  };
}

List<ContextFact> _placeContextFacts({
  required LalaPlace place,
  required String language,
  required LalaWeather? weather,
  required bool includeEvidence,
}) {
  final score = place.score;
  final features = score?.features ?? const <String, dynamic>{};
  final facts = <ContextFact>[];

  void add(IconData icon, String? label) {
    final trimmed = label?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == '-') {
      return;
    }
    if (facts.any((fact) => fact.label == trimmed)) {
      return;
    }
    facts.add(ContextFact(icon: icon, label: trimmed));
  }

  add(Icons.place_outlined, _placeRegionLabel(place, language));

  final placeEventCount = _asFeatureInt(features['place_event_count']);
  final cultureEventCount = _asFeatureInt(features['culture_event_count']);
  if (placeEventCount > 0) {
    add(
      Icons.event_note_outlined,
      _copy(
        language,
        ko: '장소 연계 행사 ${_commaInt(placeEventCount)}건',
        en: '${_commaInt(placeEventCount)} linked events',
      ),
    );
  } else if (cultureEventCount > 0) {
    add(
      Icons.festival_outlined,
      _copy(
        language,
        ko: '지역 문화행사 ${_commaInt(cultureEventCount)}건',
        en: '${_commaInt(cultureEventCount)} nearby culture events',
      ),
    );
  }

  final spendAmount = _asFeatureDouble(features['region_spend_amount']);
  if (includeEvidence && spendAmount > 0) {
    add(
      Icons.payments_outlined,
      _copy(
        language,
        ko: '카드 소비 ${_formatWonCompact(spendAmount, language)}',
        en: 'Card spend ${_formatWonCompact(spendAmount, language)}',
      ),
    );
  }

  final transactionCount = _asFeatureInt(features['region_transaction_count']);
  if (includeEvidence && transactionCount > 0) {
    add(
      Icons.receipt_long_outlined,
      _copy(
        language,
        ko: '거래 ${_commaInt(transactionCount)}건',
        en: '${_commaInt(transactionCount)} transactions',
      ),
    );
  }

  if (weather != null) {
    add(
      Icons.wb_cloudy_outlined,
      '${_outdoorLabel(weather.outdoorStatus, language: language)} · ${temperatureLabel(weather.temp)}',
    );
  }

  if (includeEvidence) {
    add(
      Icons.verified_outlined,
      _externalSourceLabel(
            place.upstreamSource ?? features['primary_source'],
            language: language,
          ) ??
          _sourceLabel(place.source, language: language),
    );
  }

  return facts.take(5).toList(growable: false);
}

// C3: 최상위 _categoryColor → features/place/place_helpers.dart (categoryColor).
// (주의: _RecommendedPlaceCard 인스턴스 메서드 _categoryColor 는 별개 — 잔류)

LalaWeather? _publicWeatherOrNull(LalaWeather? weather) =>
    publicWeatherOrNull(weather);
// C3: _isPlaceholderWeatherSource → shared/labels/source_label.dart (isPlaceholderWeatherSource).
bool _isPlaceholderWeatherSource(String? source) =>
    isPlaceholderWeatherSource(source);

// C3: weather helpers (temperatureLabel, buildWeatherChartPoints, weatherChartTimeLabel, weatherForecastIcon) -> features/weather/weather_helpers.dart.

// C3: _outdoorLabel → shared/l10n/place_labels.dart (outdoorLabel).
String _outdoorLabel(String status, {String language = 'ko'}) =>
    outdoorLabel(status, language: language);

// C3: 미세먼지 라벨 → shared/labels/dust_label.dart.
//     _dustLabel/_dustPollutantGradeLabel 은 외부 호출이 있어 forwarder 유지.
//     (_dustGradeLabel 은 외부 사용 없어 본문 제거)
String _dustLabel(LalaDust dust, String language) => dustLabel(dust, language);

String _dustPollutantGradeLabel(
  LalaDust dust,
  String pollutant,
  String language,
) =>
    dustPollutantGradeLabel(dust, pollutant, language);

// C3: _dustSituationLabel / _compactDustPart → shared/labels/dust_label.dart.
String _dustSituationLabel(
  LalaDust dust,
  String language, {
  bool includePrefix = true,
}) =>
    dustSituationLabel(dust, language, includePrefix: includePrefix);

String _compactDustPart({
  required String label,
  required String value,
  required String grade,
}) =>
    compactDustPart(label: label, value: value, grade: grade);

List<LalaPlace> _railPlaces(List<LalaPlace> places) {
  if (places.isEmpty) {
    return const <LalaPlace>[];
  }
  final featured = _featuredPlace(places);
  if (featured == null) {
    return places.take(8).toList();
  }
  return [
    featured,
    ...places.where((place) => place.placeId != featured.placeId),
  ].take(8).toList();
}

LalaPlace? _featuredPlace(List<LalaPlace> places) {
  if (places.isEmpty) {
    return null;
  }

  final suwonPlaces = places.where((place) => place.distanceM <= 5000).toList()
    ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
  for (final place in suwonPlaces) {
    final name = '${place.nameKo ?? ''} ${place.name}';
    if (name.contains('화성행궁') || name.contains('수원화성')) {
      return place;
    }
  }
  if (suwonPlaces.isNotEmpty) {
    return suwonPlaces.first;
  }

  return places.first;
}

bool _hasUsableDocentScript(String? script, String language) =>
    hasUsableDocentScript(script, language);
bool _liveSpeechEnabled(LalaReadiness? readiness) {
  return readiness?.mode.speech == 'live-azure' ||
      readiness?.checks['live_speech'] == 'enabled';
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// C3: _sourceLabel / _weatherSourceLabel → shared/labels/source_label.dart.
String _sourceLabel(String? value, {String language = 'ko'}) =>
    sourceLabel(value, language: language);

String _weatherSourceLabel(String? value, {String language = 'ko'}) =>
    weatherSourceLabel(value, language: language);

String? _externalSourceLabel(Object? value, {String language = 'ko'}) {
  final normalized = (value?.toString() ?? '').trim();
  if (_isFallbackSourceCode(normalized)) {
    return _sourceLabel(normalized, language: language);
  }
  if (_isEnglish(language)) {
    return switch (normalized) {
      'tour_api' => 'Korea Tourism data',
      'kcisa' => 'Culture information data',
      'kopis' => 'Performing arts data',
      'dev_seed' => 'LALA curation',
      'local_fixture' => 'LALA local data',
      'canonical' => 'Official places',
      '' => null,
      final source => source,
    };
  }
  return switch (normalized) {
    'tour_api' => '한국관광공사',
    'kcisa' => '문화정보원',
    'kopis' => '공연예술통합전산망',
    'dev_seed' => '로컬 큐레이션',
    'local_fixture' => '로컬 데이터',
    'canonical' => '공식 장소',
    '' => null,
    final source => source,
  };
}

String _basisLabel(String value, {String language = 'ko'}) =>
    basisLabel(value, language: language);
// C3: _isFallbackSourceCode → shared/labels/source_label.dart (isFallbackSourceCode).
bool _isFallbackSourceCode(String? value) => isFallbackSourceCode(value);

List<String> _stringList(Object? value) {
  if (value is Iterable) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? const <String>[] : <String>[text];
}

int _asFeatureInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asFeatureDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _commaInt(num value) {
  final text = value.round().abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index += 1) {
    if (index > 0 && (text.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(text[index]);
  }
  return value < 0 ? '-$buffer' : buffer.toString();
}

String _formatWonCompact(num value, String language) {
  if (_isEnglish(language)) {
    return 'KRW ${_commaInt(value)}';
  }
  final rounded = value.round();
  if (rounded >= 10000) {
    return '${_commaInt(rounded / 10000)}만원';
  }
  return '${_commaInt(rounded)}원';
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
