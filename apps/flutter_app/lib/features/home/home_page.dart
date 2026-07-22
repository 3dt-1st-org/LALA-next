// ignore_for_file: unused_element

// C3 최종: main.dart 에서 이관. 본문 불변(이동만).
// LalaHomePage + _LalaHomePageState. 상태 관리는 이번엔 그대로(setState 유지).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/app/dashboard.dart';
import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/geo/geo_helpers.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/features/location/widgets/manual_location_sheet.dart';
import 'package:lala_next_app/features/map/domain/active_map_sheet.dart';
import 'package:lala_next_app/features/map/map_helpers.dart';
import 'package:lala_next_app/features/settings/widgets/user_settings_sheet.dart';
import 'package:lala_next_app/features/tour/tour_helpers.dart';
import 'package:lala_next_app/features/weather/weather_helpers.dart';
import 'package:lala_next_app/features/home/home_view_helpers.dart';
import 'package:lala_next_app/kakao_map_view.dart';
import 'package:lala_next_app/manual_location_options.dart';
import 'package:lala_next_app/smoke_state.dart';

const int _defaultMapLevel = 6;

const int _focusedPlaceMapLevel = 4;

const Duration _recommendationRequestRetryDelay = Duration(milliseconds: 450);

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
  ActiveMapSheet? _activeSheet;
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
        fallbackMessage: (_) => recommendationLoadFailureMessage(config.lang),
      );
      final health = (await healthFuture) ?? previousHealth;
      final readiness = (await readinessFuture) ?? previousReadiness;
      final places = await placesFuture;
      final activePlaces = places ?? previousPlaces;
      final placeItems = activePlaces?.data?.places ?? const <LalaPlace>[];
      final filteredItems = filterPlaces(placeItems, _selectedCategory);
      final effectiveItems = filteredItems.isEmpty ? placeItems : filteredItems;
      final autoDocentPlace = _autoDocentEnabled
          ? _nextAutoDocentPlace(effectiveItems)
          : null;
      final selectedPlace = placeById(effectiveItems, _selectedPlaceId);
      final firstPlace =
          autoDocentPlace ?? selectedPlace ?? featuredPlace(effectiveItems);
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
        final weatherContext = publicWeatherOrNull(_weather?.data);
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
              recommendationLoadFailureMessage(config.lang),
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
      return safeUiErrorMessage(
        error.message,
        fallbackMessage: fallbackMessage?.call(error),
      );
    }
    if (error is FormatException) {
      return safeUiErrorMessage(
        error.message,
        fallbackMessage: fallbackMessage?.call(error),
      );
    }
    return fallbackMessage?.call(error) ?? requestFailureMessage();
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
        weather: publicWeatherOrNull(_weather?.data),
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
          fallbackMessage: (_) => docentAudioFailureMessage(),
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
    final restaurants = restaurantTourPlaces(
      _visiblePlacesForCurrentCategory(),
    ).take(5).toList(growable: false);
    if (restaurants.isEmpty) {
      return;
    }
    final script = tourGuideScript(restaurants, _uiLanguage);
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
          fallbackMessage: (_) => tourAudioFailureMessage(),
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
    return placeById(places, _selectedPlaceId) ?? featuredPlace(places);
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
      _activeSheet = ActiveMapSheet.detail;
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

  void _openSheet(ActiveMapSheet sheet) {
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
    if (isLiveSpeechEnabled(readiness?.data) || !_voiceEnabled) {
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
    if (!isLiveSpeechEnabled(_readiness?.data)) {
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
    final filteredPlaces = filterPlaces(apiPlaces, _selectedCategory);
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
      useRootNavigator: true,
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
      useRootNavigator: true,
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
            builder: (context) => Dashboard(
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
