// ignore_for_file: unused_element

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:url_launcher/url_launcher.dart';

import 'kakao_map_view.dart';

void main() {
  runApp(const LalaApp());
}

typedef LalaBackendFactory = LalaBackend Function(LalaAppConfig config);

class LalaApp extends StatelessWidget {
  const LalaApp({
    super.key,
    this.backendFactory = LalaApiBackend.new,
    this.initialConfig = const LalaAppConfig.fromEnvironment(),
  });

  final LalaBackendFactory backendFactory;
  final LalaAppConfig initialConfig;

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
    this.radiusM = 50000,
    this.category = 'all',
    this.lang = 'ko',
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
      radiusM = 50000,
      category = const String.fromEnvironment(
        'LALA_PLACE_CATEGORY',
        defaultValue: 'all',
      ),
      lang = const String.fromEnvironment(
        'LALA_UI_LANGUAGE',
        defaultValue: 'ko',
      );

  final String baseUri;
  final String bearerToken;
  final String apiKey;
  final String kakaoJavascriptKey;
  final double lat;
  final double lng;
  final int radiusM;
  final String category;
  final String lang;

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
    String? category,
    String? lang,
  }) {
    return LalaAppConfig(
      baseUri: baseUri ?? this.baseUri,
      bearerToken: bearerToken ?? this.bearerToken,
      apiKey: apiKey ?? this.apiKey,
      kakaoJavascriptKey: kakaoJavascriptKey ?? this.kakaoJavascriptKey,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      radiusM: radiusM ?? this.radiusM,
      category: category ?? this.category,
      lang: lang ?? this.lang,
    );
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
      category: config.category,
      lang: config.lang,
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
    String mode = 'brief',
  }) {
    return _client.createDocentScript(
      placeId: place.placeId,
      placeName: _placeDisplayName(place, config.lang),
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
    super.key,
  });

  final LalaBackendFactory backendFactory;
  final LalaAppConfig initialConfig;

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
  static const Duration _weatherMaxAge = Duration(minutes: 10);

  late final LalaAppConfig _baseConfig;
  late double _queryLat;
  late double _queryLng;
  late LalaBackend _backend;

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
  double? _mapFocusLat;
  double? _mapFocusLng;
  int _mapLevel = 4;
  Timer? _mapCameraDebounce;
  Timer? _interventionToastTimer;
  String _uiLanguage = 'ko';
  double _fontScale = 1.0;

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig;
    _baseConfig = config;
    _queryLat = config.lat;
    _queryLng = config.lng;
    _uiLanguage = config.lang;
    _backend = widget.backendFactory(_currentConfig());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _mapCameraDebounce?.cancel();
    _interventionToastTimer?.cancel();
    _backend.close();
    super.dispose();
  }

  LalaAppConfig _currentConfig() {
    return _baseConfig.copyWith(
      lat: _queryLat,
      lng: _queryLng,
      category: _selectedCategory,
      lang: _uiLanguage,
    );
  }

  Future<void> _refresh({bool forceWeather = false}) async {
    final config = _currentConfig();
    setState(() {
      _loading = true;
      _error = null;
      _audioError = null;
      _docentAudio = null;
      _tourAudio = null;
      _tourAudioError = null;
      _tourAudioLoading = false;
    });

    _backend.close();
    _backend = widget.backendFactory(config);

    try {
      final health = await _backend.getHealth();
      final readiness = await _backend.getReadiness();
      final loadErrors = <String>[];
      Future<T?> loadOptional<T>(Future<T> Function() loader) async {
        try {
          return await loader();
        } on Object catch (error) {
          loadErrors.add(_safeErrorMessage(error));
          return null;
        }
      }

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
      final places = await loadOptional(_backend.getPlaces);
      final weather = shouldReloadWeather
          ? await loadOptional(_backend.getWeather)
          : previousWeather;
      final intervention = shouldReloadWeather
          ? await loadOptional(_backend.getIntervention)
          : previousIntervention;
      final dailyPlan = await loadOptional(_backend.createDailyPlan);
      LalaEnvelope<LalaDocentScript>? docentScript;
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
      if (firstPlace != null) {
        docentScript = await loadOptional(
          () => _backend.createDocentScript(place: firstPlace),
        );
      }
      final loadError = loadErrors.isEmpty
          ? null
          : loadErrors.toSet().take(2).join(' / ');

      if (!mounted) {
        return;
      }
      setState(() {
        _health = health;
        _readiness = readiness;
        _places = places ?? previousPlaces;
        _weather = weather ?? previousWeather;
        _intervention = intervention ?? previousIntervention;
        _dailyPlan = dailyPlan;
        _docentScript = docentScript;
        _docentAudio = null;
        _tourAudio = null;
        _audioError = null;
        _tourAudioError = null;
        _tourAudioLoading = false;
        _error = loadError;
        if (shouldReloadWeather) {
          _interventionToastDismissed = false;
        }
        if (places != null) {
          _lastPlacesFetchLat = config.lat;
          _lastPlacesFetchLng = config.lng;
        }
        if (weather != null && shouldReloadWeather) {
          _lastWeatherFetchAt = DateTime.now();
          _lastWeatherFetchLat = config.lat;
          _lastWeatherFetchLng = config.lng;
        }
        if (autoDocentPlace != null) {
          _applyAutoDocentPlace(autoDocentPlace, closeActiveSheet: false);
        }
      });
      _syncInterventionToastTimer();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _safeErrorMessage(error);
      });
      _cancelInterventionToastTimer();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _safeErrorMessage(Object error) {
    if (error is LalaApiException) {
      return _safeUiErrorMessage(error.message);
    }
    if (error is FormatException) {
      return _safeUiErrorMessage(error.message);
    }
    return _requestFailureMessage();
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
        _audioError = _safeErrorMessage(error);
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
        _tourAudioError = _safeErrorMessage(error);
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
      _mapLevel = 4;
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
      _mapLevel = 4;
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
      _selectedPlaceId = null;
      _activeSheet = null;
      _docentAudio = null;
      _audioError = null;
      _tourAudio = null;
      _tourAudioError = null;
      _tourAudioLoading = false;
      _showEvidence = false;
      _focusedClusterMemberIds = const <String>[];
      _queryLat = _baseConfig.lat;
      _queryLng = _baseConfig.lng;
      _mapFocusLat = _baseConfig.lat;
      _mapFocusLng = _baseConfig.lng;
      _mapLevel = 4;
      _recommendationRailExpanded = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
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

  void _toggleVoice() {
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
    });
  }

  void _retryLocationConsent() {
    setState(() {
      _locationConsentEnabled = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh(forceWeather: true);
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
    _mapLevel = 4;
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

            return _UserSettingsSheet(
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
              recommendationRailExpanded: _recommendationRailExpanded,
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
              onRetryLocation: _retryLocationConsent,
            ),
          ),
        ),
      ),
    );
  }
}

class _UserSettingsSheet extends StatelessWidget {
  const _UserSettingsSheet({
    required this.locationConsentEnabled,
    required this.uiLanguage,
    required this.fontScale,
    required this.onLocationConsentChanged,
    required this.onLanguageChanged,
    required this.onFontScaleChanged,
  });

  final bool locationConsentEnabled;
  final String uiLanguage;
  final double fontScale;
  final ValueChanged<bool> onLocationConsentChanged;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<double> onFontScaleChanged;

  @override
  Widget build(BuildContext context) {
    final title = _copy(uiLanguage, ko: '설정', en: 'Settings');
    final closeLabel = _copy(uiLanguage, ko: '닫기', en: 'Close');
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.48,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: const [
              BoxShadow(
                blurRadius: 28,
                offset: Offset(0, -10),
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
                    color: const Color(0xFFC8D0D9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: closeLabel,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1A202C),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                title: _copy(
                  uiLanguage,
                  ko: '개인정보 동의 안내',
                  en: 'Privacy notice',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _copy(
                        uiLanguage,
                        ko: '서비스 품질 향상을 위해 최소한의 이용 정보와 위치 기반 추천 정보가 사용됩니다.',
                        en: 'LALA uses minimal usage and location signals to improve recommendations.',
                      ),
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        height: 1.38,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () =>
                          _showPrivacyDetailsSheet(context, uiLanguage),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: const Color(0xFF2B6CB0),
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      child: Text(
                        _copy(uiLanguage, ko: '자세히 보기', en: 'Learn more'),
                      ),
                    ),
                  ],
                ),
              ),
              _SettingsSection(
                title: _copy(
                  uiLanguage,
                  ko: '위치기반 정보 제공 동의',
                  en: 'Location recommendations',
                ),
                trailing: Switch(
                  value: locationConsentEnabled,
                  onChanged: onLocationConsentChanged,
                ),
              ),
              _SettingsSection(
                title: _copy(uiLanguage, ko: '언어', en: 'Language'),
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'ko',
                      label: Text(_languageOptionLabel('ko', uiLanguage)),
                    ),
                    ButtonSegment(
                      value: 'en',
                      label: Text(_languageOptionLabel('en', uiLanguage)),
                    ),
                  ],
                  selected: {uiLanguage},
                  onSelectionChanged: (values) =>
                      onLanguageChanged(values.first),
                  style: SegmentedButton.styleFrom(
                    backgroundColor: Colors.white,
                    selectedBackgroundColor: const Color(0xFF2B6CB0),
                    selectedForegroundColor: Colors.white,
                  ),
                ),
              ),
              _SettingsSection(
                title: _copy(uiLanguage, ko: '글꼴 크기', en: 'Font size'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Slider(
                      value: fontScale,
                      min: 0.9,
                      max: 1.18,
                      divisions: 7,
                      label: 'x${fontScale.toStringAsFixed(2)}',
                      onChanged: onFontScaleChanged,
                    ),
                    Text(
                      'x${fontScale.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              _SettingsSection(
                title: _copy(uiLanguage, ko: '앱 정보', en: 'App info'),
                child: _MetricRow(
                  label: _copy(uiLanguage, ko: '버전', en: 'Version'),
                  value: '1.0',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> _showPrivacyDetailsSheet(
  BuildContext context,
  String language,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _PrivacyDetailsSheet(language: language),
  );
}

class _PrivacyDetailsSheet extends StatelessWidget {
  const _PrivacyDetailsSheet({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    final closeLabel = _copy(language, ko: '닫기', en: 'Close');
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.54,
      minChildSize: 0.34,
      maxChildSize: 0.82,
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            boxShadow: [
              BoxShadow(
                blurRadius: 28,
                offset: Offset(0, -10),
                color: Color(0x24000000),
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
                    color: const Color(0xFFC8D0D9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _copy(language, ko: '개인정보 동의 안내', en: 'Privacy notice'),
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: closeLabel,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1A202C),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _PrivacyDetailRow(
                icon: Icons.my_location_outlined,
                title: _copy(language, ko: '위치 기반 추천', en: 'Location context'),
                body: _copy(
                  language,
                  ko: '현재 화면의 지도 중심과 반경을 사용해 가까운 장소, 날씨, 일정을 계산합니다.',
                  en: 'LALA uses the current map center and radius for nearby places, weather, and plans.',
                ),
              ),
              _PrivacyDetailRow(
                icon: Icons.public_outlined,
                title: _copy(
                  language,
                  ko: '공식 데이터 우선',
                  en: 'Official data first',
                ),
                body: _copy(
                  language,
                  ko: '관광·문화·날씨·지역 소비 신호는 공식 기관 데이터와 공개 데이터를 우선 사용합니다.',
                  en: 'Tourism, culture, weather, and local signals prioritize official and public datasets.',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PrivacyDetailRow extends StatelessWidget {
  const _PrivacyDetailRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF2B6CB0), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, this.child, this.trailing});

  final String title;
  final Widget? child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          if (child != null) ...[const SizedBox(height: 12), child!],
        ],
      ),
    );
  }
}

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
    required this.recommendationRailExpanded,
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
    required this.onRetryLocation,
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
  final bool recommendationRailExpanded;
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
  final VoidCallback onRetryLocation;

  @override
  Widget build(BuildContext context) {
    final apiPlaces = places?.data?.places ?? const <LalaPlace>[];
    final effectiveSource = places?.data?.source;
    final allPlaces = apiPlaces;
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
    final visibleError = _localizedUiMessage(error, uiLanguage);
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
                child: _TourMapPill(
                  places: tourPlaces,
                  language: uiLanguage,
                  onPressed: () => onOpenSheet(_ActiveMapSheet.tour),
                ),
              ),
            if (visibleError != null)
              Positioned(
                left: 16,
                right: isWide ? null : 16,
                top: isWide ? 88 : 118,
                child: SizedBox(
                  width: isWide ? 420 : null,
                  child: _MapToast(
                    icon: Icons.error_outline,
                    label: visibleError,
                    actionLabel: _copy(uiLanguage, ko: '다시 시도', en: 'Retry'),
                    onAction: onRefresh,
                    color: Theme.of(context).colorScheme.errorContainer,
                  ),
                ),
              ),
            if (visibleError == null &&
                activeIntervention?.shouldIntervene == true &&
                !interventionToastDismissed)
              Positioned(
                left: 16,
                right: 16,
                top: isWide ? 92 : 110,
                child: Center(
                  child: _InterventionToast(
                    intervention: activeIntervention!,
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
                        activeDocent?.placeId == topPlace?.placeId &&
                        activeDocent?.script.trim().isNotEmpty == true &&
                        !audioLoading &&
                        topPlace != null &&
                        !detailDocentPlayedPlaceIds.contains(topPlace.placeId),
                    showEvidence: showEvidence,
                    onFetchAudio: onFetchAudio,
                    onAddToPlan: () => onOpenSheet(_ActiveMapSheet.planner),
                    onOpenDetail: () => onOpenSheet(_ActiveMapSheet.detail),
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
                    onOpenSettings: onOpenSettings,
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
            if (!locationConsentEnabled)
              Positioned.fill(
                child: _LocationConsentOverlay(
                  language: uiLanguage,
                  onOpenSettings: onOpenSettings,
                  onRetryLocation: onRetryLocation,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TopMapChrome extends StatelessWidget {
  const _TopMapChrome({
    required this.loading,
    required this.language,
    required this.selectedCategory,
    required this.onSelectCategory,
  });

  final bool loading;
  final String language;
  final String selectedCategory;
  final ValueChanged<String> onSelectCategory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _CategoryChip(
                  label: _categoryFilterLabel('all', language),
                  active: selectedCategory == 'all',
                  color: const Color(0xFF1A202C),
                  onTap: () => onSelectCategory('all'),
                ),
                _CategoryChip(
                  label: _categoryFilterLabel('attraction', language),
                  active: selectedCategory == 'attraction',
                  color: const Color(0xFFC53030),
                  onTap: () => onSelectCategory('attraction'),
                ),
                _CategoryChip(
                  label: _categoryFilterLabel('restaurant', language),
                  active: selectedCategory == 'restaurant',
                  color: const Color(0xFFF5C842),
                  onTap: () => onSelectCategory('restaurant'),
                ),
                _CategoryChip(
                  label: _categoryFilterLabel('event', language),
                  active: selectedCategory == 'event',
                  color: const Color(0xFF2B6CB0),
                  onTap: () => onSelectCategory('event'),
                ),
                _CategoryChip(
                  label: _categoryFilterLabel('culture_venue', language),
                  active: selectedCategory == 'culture_venue',
                  color: const Color(0xFF0F766E),
                  onTap: () => onSelectCategory('culture_venue'),
                ),
              ],
            ),
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
                            return _MapRailPlaceCard(
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

class _MapRailPlaceCard extends StatelessWidget {
  const _MapRailPlaceCard({
    required this.place,
    required this.language,
    required this.selected,
    required this.compact,
    this.onTap,
  });

  final LalaPlace place;
  final String language;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(place.category);
    final hasImage = _hasOfficialPlaceImage(place);
    final cardWidth = compact
        ? (hasImage ? 226.0 : 198.0)
        : (hasImage ? 252.0 : 222.0);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: ValueKey('tour-stop-action-${place.placeId}'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          key: ValueKey('map-rail-place-card-${place.placeId}'),
          width: cardWidth,
          padding: selected ? const EdgeInsets.all(3) : EdgeInsets.zero,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: selected ? _obangGradient() : null,
            border: selected
                ? null
                : Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      blurRadius: 16,
                      offset: Offset(0, 7),
                      color: Color(0x240F172A),
                    ),
                  ]
                : null,
          ),
          child: Container(
            key: selected ? ValueKey('obang-border-${place.placeId}') : null,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 7 : 8,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: selected ? 0.98 : 0.93),
              borderRadius: BorderRadius.circular(selected ? 15 : 18),
              border: selected
                  ? Border.all(color: Colors.white.withValues(alpha: 0.72))
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _placeDisplayName(place, language),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: selected ? color : const Color(0xFF111827),
                          fontWeight: FontWeight.w900,
                          height: 1.12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _RailCategoryBadge(place: place, language: language),
                      const SizedBox(height: 5),
                      Row(
                        key: ValueKey('rail-place-region-${place.placeId}'),
                        children: [
                          const Icon(
                            Icons.place_outlined,
                            size: 13,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _placeRegionLabel(place, language),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: const Color(0xFF64748B),
                                    fontWeight: FontWeight.w700,
                                    height: 1.05,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (place.distanceM > 0)
                            _TinyMeta('${place.distanceM}m'),
                        ],
                      ),
                    ],
                  ),
                ),
                if (hasImage) ...[
                  SizedBox(width: compact ? 8 : 10),
                  _RailPlaceThumb(place: place, compact: compact),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

LinearGradient _obangGradient() {
  return const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1A202C),
      Color(0xFF2B6CB0),
      Color(0xFFC53030),
      Color(0xFFFFFFFF),
      Color(0xFFF5C842),
      Color(0xFF1A202C),
    ],
    stops: [0, 0.22, 0.44, 0.62, 0.82, 1],
  );
}

class _RailCategoryBadge extends StatelessWidget {
  const _RailCategoryBadge({required this.place, required this.language});

  final LalaPlace place;
  final String language;

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(place.category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        _railCategoryLabel(place, language),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _RailPlaceThumb extends StatelessWidget {
  const _RailPlaceThumb({required this.place, required this.compact});

  final LalaPlace place;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dimension = compact ? 72.0 : 86.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        key: ValueKey('rail-place-thumb-${place.placeId}'),
        width: dimension,
        height: dimension,
        child: _PlaceImage(place: place, width: dimension, height: dimension),
      ),
    );
  }
}

class _PlannerMapPill extends StatelessWidget {
  const _PlannerMapPill({
    required this.dailyPlan,
    required this.language,
    required this.onPressed,
  });

  final LalaDailyPlan? dailyPlan;
  final String language;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final slots = dailyPlan?.slots ?? const <LalaPlanSlot>[];
    return _SmallStatusPill(
      key: const ValueKey('planner-pill-hit-target'),
      icon: Icons.event_note,
      label: language == 'en' ? 'Daily Plan' : '하루 일정',
      active: slots.isNotEmpty,
      onPressed: onPressed,
    );
  }
}

class _MapUtilityControlRow extends StatelessWidget {
  const _MapUtilityControlRow({
    required this.dailyPlan,
    required this.weather,
    required this.language,
    required this.onOpenPlanner,
    required this.onOpenWeather,
    required this.onOpenSettings,
  });

  final LalaDailyPlan? dailyPlan;
  final LalaWeather? weather;
  final String language;
  final VoidCallback onOpenPlanner;
  final VoidCallback onOpenWeather;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('map-utility-control-row'),
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _PlannerMapPill(
              dailyPlan: dailyPlan,
              language: language,
              onPressed: onOpenPlanner,
            ),
          ),
        ),
        _MapRoundButton(
          buttonKey: const ValueKey('settings-button'),
          tooltip: _copy(language, ko: '설정', en: 'Settings'),
          icon: Icons.settings,
          onPressed: onOpenSettings,
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: _WeatherMapPill(
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

class _TourMapPill extends StatelessWidget {
  const _TourMapPill({
    required this.places,
    required this.language,
    required this.onPressed,
  });

  final List<LalaPlace> places;
  final String language;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _SmallStatusPill(
      key: const ValueKey('tour-pill-hit-target'),
      icon: Icons.restaurant_menu,
      label: _copy(language, ko: '맛집 투어', en: 'Food tour'),
      active: places.isNotEmpty,
      onPressed: onPressed,
    );
  }
}

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
    required this.onFetchAudio,
    required this.onAddToPlan,
    required this.onOpenDetail,
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
  final VoidCallback onFetchAudio;
  final VoidCallback onAddToPlan;
  final VoidCallback onOpenDetail;
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
                _EmptyDockContent(language: uiLanguage)
              else ...[
                Row(
                  children: [
                    _CategoryBadge(
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
                    _TinyMeta(_placeRegionLabel(currentPlace, uiLanguage)),
                    _TinyMeta('${currentPlace.distanceM}m'),
                    _TinyMeta(_sourceLabel(source, language: uiLanguage)),
                  ],
                ),
                const SizedBox(height: 12),
                _DockDocentPreview(
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

class _DockDocentPreview extends StatelessWidget {
  const _DockDocentPreview({
    required this.place,
    required this.language,
    required this.script,
    required this.action,
    required this.audioLoading,
    required this.audioError,
    required this.docentAudio,
    required this.canFetchAudio,
    required this.onFetchAudio,
    required this.onAddToPlan,
    required this.onOpenDetail,
  });

  final LalaPlace place;
  final String language;
  final String? script;
  final String? action;
  final bool audioLoading;
  final String? audioError;
  final LalaAudioResponse? docentAudio;
  final bool canFetchAudio;
  final VoidCallback onFetchAudio;
  final VoidCallback onAddToPlan;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final body = _docentBody(place: place, script: script, language: language);
    final summary = _docentSummary(
      place: place,
      language: language,
      script: script,
      action: action,
    );
    final actionLabel = _docentActionLabel(
      place: place,
      action: action,
      language: language,
    );
    final showListenButton = canFetchAudio || audioLoading;
    return DecoratedBox(
      key: const ValueKey('dock-docent-preview'),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.record_voice_over_outlined,
                    color: Color(0xFF2B6CB0),
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _copy(
                          language,
                          ko: '${_placeDisplayName(place, language)} 도슨트',
                          en: '${_placeDisplayName(place, language)} docent',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (docentAudio != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      _audioBytesLabel(docentAudio!.bytes.length, language),
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111827),
                height: 1.38,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 6),
              _InlineIconText(icon: Icons.route_outlined, label: actionLabel),
            ],
            if (audioError != null) ...[
              const SizedBox(height: 6),
              Text(
                audioError!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (showListenButton) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canFetchAudio ? onFetchAudio : null,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      icon: audioLoading
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.volume_up, size: 18),
                      label: Text(
                        audioLoading
                            ? _copy(language, ko: '음성 생성 중', en: 'Preparing')
                            : _copy(language, ko: '정보 더 듣기', en: 'Listen'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onAddToPlan,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: Text(
                      _copy(language, ko: '오늘 코스에 추가', en: 'Add to plan'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2B6CB0),
                      side: const BorderSide(color: Color(0xFF2B6CB0)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton.filledTonal(
                    tooltip: _copy(language, ko: '상세 열기', en: 'Open details'),
                    onPressed: onOpenDetail,
                    icon: const Icon(Icons.keyboard_arrow_up),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF2B6CB0),
                      side: const BorderSide(color: Color(0xFFD7E3F5)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDockContent extends StatelessWidget {
  const _EmptyDockContent({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: Color(0xFFEAF2FF),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.travel_explore,
            color: Color(0xFF2B6CB0),
            size: 21,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _copy(
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
                _copy(
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
      _ActiveMapSheet.planner => language == 'en' ? 'Daily Plan' : '오늘 일정',
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
      _ActiveMapSheet.planner => 0.48,
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
                      source: source,
                      showEvidence: showEvidence,
                      savedPlaceIds: savedPlaceIds,
                      detailDocentPlayedPlaceIds: detailDocentPlayedPlaceIds,
                      onToggleEvidence: onToggleEvidence,
                      onToggleSavedPlace: onToggleSavedPlace,
                      onAddToPlan: onAddToPlan,
                      onFetchAudio: onFetchAudio,
                    ),
                    _ActiveMapSheet.planner => _PlannerSheetContent(
                      language: language,
                      weather: weather,
                      dailyPlan: dailyPlan,
                      intervention: intervention,
                      loading: loading,
                      onRegenerate: onRefresh,
                      onSelectPlace: onSelectPlace,
                    ),
                    _ActiveMapSheet.weather => _WeatherSheetContent(
                      language: language,
                      weather: weather,
                    ),
                    _ActiveMapSheet.tour => _TourSheetContent(
                      places: places,
                      language: language,
                      tourAudio: tourAudio,
                      audioLoading: tourAudioLoading,
                      audioError: tourAudioError,
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

class _PlannerSheetContent extends StatelessWidget {
  const _PlannerSheetContent({
    required this.language,
    required this.weather,
    required this.dailyPlan,
    required this.intervention,
    required this.loading,
    required this.onRegenerate,
    required this.onSelectPlace,
  });

  final String language;
  final LalaWeather? weather;
  final LalaDailyPlan? dailyPlan;
  final LalaIntervention? intervention;
  final bool loading;
  final VoidCallback onRegenerate;
  final ValueChanged<LalaPlace> onSelectPlace;

  @override
  Widget build(BuildContext context) {
    final slots = dailyPlan?.slots ?? const <LalaPlanSlot>[];
    final action = _docentActionLabel(
      place: intervention?.place,
      action: intervention?.recommendedAction,
      language: language,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlannerOverviewCard(
          language: language,
          weather: weather,
          dailyPlan: dailyPlan,
          loading: loading,
          onRegenerate: () => _confirmRegenerate(context),
        ),
        const SizedBox(height: 12),
        if (action != null)
          _CompactInfoTile(
            icon: Icons.alt_route_outlined,
            label: _copy(language, ko: '추천 동선', en: 'Suggested route'),
            value: action,
          ),
        if (action != null) const SizedBox(height: 12),
        if (slots.isEmpty)
          _MutedSheetCard(
            icon: Icons.route_outlined,
            label: _copy(
              language,
              ko: '현재 위치와 날씨 기준으로 코스를 준비 중입니다.',
              en: 'Preparing a route from your location and weather.',
            ),
          )
        else
          ...slots
              .take(5)
              .map(
                (slot) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PlanSlotTile(
                    slot: slot,
                    language: language,
                    onSelectPlace: onSelectPlace,
                  ),
                ),
              ),
      ],
    );
  }

  Future<void> _confirmRegenerate(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            _copy(language, ko: '하루 일정 재생성', en: 'Regenerate daily plan'),
          ),
          content: Text(
            _copy(
              language,
              ko: '현재 지도의 위치와 날씨를 기준으로 새 일정을 만들까요?',
              en: 'Create a new plan from the current map location and weather?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_copy(language, ko: '취소', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_copy(language, ko: '다시 생성', en: 'Regenerate')),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      onRegenerate();
    }
  }
}

class _PlannerOverviewCard extends StatelessWidget {
  const _PlannerOverviewCard({
    required this.language,
    required this.weather,
    required this.dailyPlan,
    required this.loading,
    required this.onRegenerate,
  });

  final String language;
  final LalaWeather? weather;
  final LalaDailyPlan? dailyPlan;
  final bool loading;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final location = weather?.location?.trim().isNotEmpty == true
        ? _locationLabel(weather!.location, language)
        : _copy(language, ko: '현재 위치', en: 'Current location');
    final weatherLabel = weather == null
        ? _copy(language, ko: '날씨 확인 중', en: 'Checking weather')
        : '${_outdoorLabel(weather!.outdoorStatus, language: language)} · ${_temperatureLabel(weather!.temp)} · ${_dustLabel(weather!.dust, language)}';
    final slotCount = dailyPlan?.slots.length ?? 0;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.alt_route_outlined,
              color: Color(0xFF0F766E),
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF14532D),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: [
                    _TinyMeta(weatherLabel),
                    if (slotCount > 0)
                      _TinyMeta(
                        _copy(
                          language,
                          ko: '$slotCount개 일정',
                          en: '$slotCount stops',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const ValueKey('planner-regenerate'),
            onPressed: loading ? null : onRegenerate,
            icon: loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 17),
            label: Text(_copy(language, ko: '일정 재생성', en: 'Regenerate')),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0F766E),
              side: const BorderSide(color: Color(0xFF86EFAC)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanSlotTile extends StatelessWidget {
  const _PlanSlotTile({
    required this.slot,
    required this.language,
    required this.onSelectPlace,
  });

  final LalaPlanSlot slot;
  final String language;
  final ValueChanged<LalaPlace> onSelectPlace;

  @override
  Widget build(BuildContext context) {
    final place = slot.place;
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: ValueKey('planner-slot-${place?.placeId ?? slot.period}'),
        borderRadius: BorderRadius.circular(18),
        onTap: place == null ? null : () => onSelectPlace(place),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFD7E3F5)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF2B6CB0).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _periodLabel(slot.period, language: language),
                  style: const TextStyle(
                    color: Color(0xFF2B6CB0),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _planSlotTitle(slot, language),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (place != null)
                      Text(
                        '${_placeDisplayName(place, language)} · ${_categoryLabel(place.category, language: language)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              if (place != null) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF94A3B8),
                  size: 22,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TourSheetContent extends StatelessWidget {
  const _TourSheetContent({
    required this.places,
    required this.language,
    required this.tourAudio,
    required this.audioLoading,
    required this.audioError,
    required this.onFetchAudio,
    required this.onSelectPlace,
  });

  final List<LalaPlace> places;
  final String language;
  final LalaAudioResponse? tourAudio;
  final bool audioLoading;
  final String? audioError;
  final VoidCallback onFetchAudio;
  final ValueChanged<LalaPlace> onSelectPlace;

  @override
  Widget build(BuildContext context) {
    final items = places.take(5).toList(growable: false);
    if (items.isEmpty) {
      return _MutedSheetCard(
        icon: Icons.restaurant_menu,
        label: _copy(
          language,
          ko: '근처 맛집 투어 후보를 찾고 있습니다.',
          en: 'Looking for nearby food tour stops.',
        ),
      );
    }

    final headline = _copy(
      language,
      ko: '가까운 맛집 ${items.length}곳을 이어 걷는 코스',
      en: '${items.length} nearby food stops for a walkable route',
    );
    final first = items.first;
    final script = _tourGuideScript(items, language);
    final sourceLabel = _copy(
      language,
      ko: '${items.length}개 맛집 · 공식 데이터 기반',
      en: '${items.length} restaurants · Official data',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFF5C842)),
          ),
          child: Row(
            children: [
              if (_hasOfficialPlaceImage(first)) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _PlaceImage(place: first, width: 64, height: 64),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF1A202C),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _copy(
                        language,
                        ko: '${_placeDisplayName(first, language)}부터 시작 · ${first.distanceM}m',
                        en: 'Start at ${_placeDisplayName(first, language)} · ${first.distanceM}m',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final place in items)
              _TourTag(
                key: ValueKey('tour-tag-${place.placeId}'),
                label: _placeDisplayName(place, language),
                onPressed: () => onSelectPlace(place),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _TourScriptCard(
          script: script,
          sourceLabel: sourceLabel,
          language: language,
        ),
        const SizedBox(height: 12),
        _TourAudioBar(
          language: language,
          audio: tourAudio,
          loading: audioLoading,
          error: audioError,
          onFetchAudio: onFetchAudio,
        ),
        const SizedBox(height: 14),
        ...items.indexed.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TourStopTile(
              key: ValueKey('tour-stop-${entry.$2.placeId}'),
              index: entry.$1,
              place: entry.$2,
              language: language,
              onTap: () => onSelectPlace(entry.$2),
            ),
          ),
        ),
      ],
    );
  }
}

class _TourTag extends StatelessWidget {
  const _TourTag({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.restaurant_menu, size: 16),
      label: Text(label, overflow: TextOverflow.ellipsis),
      onPressed: onPressed,
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFF5C842)),
      labelStyle: const TextStyle(
        color: Color(0xFF744210),
        fontWeight: FontWeight.w900,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}

class _TourScriptCard extends StatelessWidget {
  const _TourScriptCard({
    required this.script,
    required this.sourceLabel,
    required this.language,
  });

  final String script;
  final String sourceLabel;
  final String language;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 16,
            offset: Offset(0, 7),
            color: Color(0x10000000),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.record_voice_over_outlined,
                size: 19,
                color: Color(0xFFC87F11),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _copy(language, ko: '투어 도슨트 스크립트', en: 'Tour docent script'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _TinyMeta(sourceLabel),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            script,
            style: const TextStyle(
              color: Color(0xFF1A202C),
              fontWeight: FontWeight.w600,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _TourAudioBar extends StatelessWidget {
  const _TourAudioBar({
    required this.language,
    required this.audio,
    required this.loading,
    required this.error,
    required this.onFetchAudio,
  });

  final String language;
  final LalaAudioResponse? audio;
  final bool loading;
  final String? error;
  final VoidCallback onFetchAudio;

  @override
  Widget build(BuildContext context) {
    final hasAudio = audio != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF5C842)),
      ),
      child: Row(
        children: [
          Icon(
            hasAudio ? Icons.graphic_eq : Icons.volume_up_outlined,
            color: const Color(0xFFC87F11),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasAudio
                      ? _copy(language, ko: '투어 음성 준비됨', en: 'Tour audio ready')
                      : _copy(
                          language,
                          ko: '도슨트 음성으로 듣기',
                          en: 'Listen as a docent audio guide',
                        ),
                  style: const TextStyle(
                    color: Color(0xFF744210),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ] else if (hasAudio) ...[
                  const SizedBox(height: 3),
                  Text(
                    _copy(
                      language,
                      ko: '오디오 캐시 ${audio!.bytes.length}바이트',
                      en: '${audio!.bytes.length} bytes cached',
                    ),
                    style: const TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: loading ? null : onFetchAudio,
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(hasAudio ? Icons.replay : Icons.play_arrow),
            label: Text(
              loading
                  ? _copy(language, ko: '변환 중', en: 'Converting')
                  : hasAudio
                  ? _copy(language, ko: '다시 준비', en: 'Prepare again')
                  : _copy(language, ko: '오디오 준비', en: 'Prepare audio'),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC87F11),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _TourStopTile extends StatelessWidget {
  const _TourStopTile({
    super.key,
    required this.index,
    required this.place,
    required this.language,
    required this.onTap,
  });

  final int index;
  final LalaPlace place;
  final String language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spending = place.score?.components.localSpendingScore;
    final spendingLabel = spending == null
        ? _basisLabel(
            place.score?.dataBasis ?? place.source,
            language: language,
          )
        : '${(spending.clamp(0.0, 1.0) * 100).round()}';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                blurRadius: 14,
                offset: Offset(0, 7),
                color: Color(0x10000000),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFC53030).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Color(0xFFC53030),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _placeDisplayName(place, language),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _TinyMeta('${place.distanceM}m'),
                        _TinyMeta(
                          _copy(
                            language,
                            ko: '소비 신호 $spendingLabel',
                            en: 'Spend $spendingLabel',
                          ),
                        ),
                        if (place.regionKo?.trim().isNotEmpty == true ||
                            place.regionEn?.trim().isNotEmpty == true)
                          _TinyMeta(_placeRegionLabel(place, language)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF94A3B8),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _tourGuideScript(List<LalaPlace> places, String language) {
  final items = places.take(5).toList(growable: false);
  if (items.isEmpty) {
    return _copy(
      language,
      ko: '근처 맛집 후보를 찾으면 로컬 투어 스크립트를 준비합니다.',
      en: 'LALA prepares a local food tour script when nearby food stops are found.',
    );
  }
  final names = items
      .map((place) => _placeDisplayName(place, language))
      .toList();
  final first = names.first;
  final tail = names.skip(1).take(3).toList();
  final localSignal = items
      .map((place) => place.score?.components.localSpendingScore ?? 0)
      .fold<double>(0, math.max);
  if (_isEnglish(language)) {
    final middle = tail.isEmpty ? '' : ' Continue through ${tail.join(', ')}.';
    final signal = localSignal >= 0.7
        ? ' These stops show strong local spending signals.'
        : ' The route favors nearby public and local context.';
    return 'Start at $first and keep the walk compact for a real neighborhood food route.$middle$signal Tap each stop for details before you go.';
  }
  final middle = tail.isEmpty ? '' : ' 이어서 ${tail.join(', ')} 쪽으로 걸어가면 좋아요.';
  final signal = localSignal >= 0.7
      ? ' 지역 소비 신호가 살아있는 맛집들을 우선 연결했습니다.'
      : ' 가까운 거리와 공공 장소 맥락을 함께 보고 묶은 코스입니다.';
  return '$first에서 시작해 동네 흐름을 따라 짧게 걷는 맛집 코스입니다.$middle$signal 출발 전 각 정류장을 눌러 상세 정보를 확인해보세요.';
}

class _WeatherSheetContent extends StatelessWidget {
  const _WeatherSheetContent({required this.language, required this.weather});

  final String language;
  final LalaWeather? weather;

  @override
  Widget build(BuildContext context) {
    final data = _publicWeatherOrNull(weather);
    if (data == null) {
      return _WeatherUnavailableCard(language: language);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WeatherHeroCard(weather: data, language: language),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _WeatherFact(
              label: _copy(language, ko: '미세먼지', en: 'Dust'),
              value: _dustLabel(data.dust, language),
            ),
            _WeatherFact(label: 'PM10', value: data.dust.pm10),
            _WeatherFact(label: 'PM2.5', value: data.dust.pm25),
            _WeatherFact(
              label: _copy(language, ko: '야외 상태', en: 'Outdoor'),
              value: _outdoorLabel(data.outdoorStatus, language: language),
            ),
          ],
        ),
        if (data.forecast.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            _copy(language, ko: '날씨 추이', en: 'Forecast trend'),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          _WeatherForecastChartCard(items: data.forecast, language: language),
          const SizedBox(height: 10),
          SizedBox(
            height: 82,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: data.forecast.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = data.forecast[index];
                return _ForecastChip(item: item, language: language);
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _WeatherForecastChartCard extends StatelessWidget {
  const _WeatherForecastChartCard({
    required this.items,
    required this.language,
  });

  final List<LalaForecastItem> items;
  final String language;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(8).toList(growable: false);
    final columnWidth = visibleItems.length <= 4 ? 72.0 : 62.0;
    final chartWidth = math.max(
      MediaQuery.sizeOf(context).width - 72,
      visibleItems.length * columnWidth,
    );
    final points = _weatherChartPoints(
      items: visibleItems,
      columnWidth: columnWidth,
      chartHeight: 96,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: chartWidth,
          child: Column(
            children: [
              SizedBox(
                height: 98,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _WeatherForecastChartPainter(points: points),
                      ),
                    ),
                    for (final point in points)
                      Positioned(
                        left: point.x - 18,
                        top: math.max(0, point.y - 26),
                        width: 36,
                        child: Text(
                          point.label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF1A202C),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  for (final item in visibleItems)
                    SizedBox(
                      width: columnWidth,
                      child: Icon(
                        _weatherForecastIcon(item.icon),
                        size: 22,
                        color: const Color(0xFF2B6CB0),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (final item in visibleItems)
                    SizedBox(
                      width: columnWidth,
                      child: Text(
                        _weatherChartTimeLabel(item.time, language: language),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeatherChartPoint {
  const _WeatherChartPoint({
    required this.x,
    required this.y,
    required this.label,
  });

  final double x;
  final double y;
  final String label;
}

class _WeatherForecastChartPainter extends CustomPainter {
  const _WeatherForecastChartPainter({required this.points});

  final List<_WeatherChartPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    for (final y in <double>[26, 52, 78]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (points.isEmpty) {
      return;
    }

    final path = Path()..moveTo(points.first.x, points.first.y);
    for (var index = 1; index < points.length; index += 1) {
      final previous = points[index - 1];
      final current = points[index];
      final midX = (previous.x + current.x) / 2;
      path.cubicTo(midX, previous.y, midX, current.y, current.x, current.y);
    }

    final linePaint = Paint()
      ..color = const Color(0xFF2B6CB0)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);

    final fillPaint = Paint()..color = const Color(0xFFF5C842);
    final strokePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    for (final point in points) {
      final offset = Offset(point.x, point.y);
      canvas.drawCircle(offset, 5.5, fillPaint);
      canvas.drawCircle(offset, 5.5, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherForecastChartPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

class _WeatherHeroCard extends StatelessWidget {
  const _WeatherHeroCard({required this.weather, required this.language});

  final LalaWeather weather;
  final String language;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wb_cloudy_outlined,
            size: 42,
            color: Color(0xFF2B6CB0),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _locationLabel(weather.location, language),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  _temperatureLabel(weather.temp),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          _ProofChip(
            key: const ValueKey('weather-source-chip'),
            label: _weatherSourceLabel(weather.source, language: language),
          ),
        ],
      ),
    );
  }
}

class _WeatherUnavailableCard extends StatelessWidget {
  const _WeatherUnavailableCard({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('weather-unavailable-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 38,
            color: Color(0xFF64748B),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _copy(
                    language,
                    ko: '날씨 데이터 준비 중',
                    en: 'Weather data is being prepared',
                  ),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _copy(
                    language,
                    ko: '실시간 관측값이 확인될 때 온도와 미세먼지를 표시합니다.',
                    en: 'Temperature and dust appear when verified observations are available.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherFact extends StatelessWidget {
  const _WeatherFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: _CompactInfoTile(
        icon: Icons.check_circle_outline,
        label: label,
        value: value,
      ),
    );
  }
}

class _ForecastChip extends StatelessWidget {
  const _ForecastChip({required this.item, required this.language});

  final LalaForecastItem item;
  final String language;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            language == 'en' ? item.time : _weatherChartTimeLabel(item.time),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _temperatureLabel(item.temp),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _MutedSheetCard extends StatelessWidget {
  const _MutedSheetCard({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF64748B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
        _FeaturedPlaceHeader(
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
          _EventInfoCard(place: currentPlace, language: language),
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
          _SignalGrid(
            language: language,
            localSpending: components?.localSpendingScore,
            demandDispersion: components?.demandDispersionScore,
            cultureRelevance: components?.cultureRelevanceScore,
            weatherFit: components?.weatherFitScore,
          ),
        ],
        const SizedBox(height: 12),
        _DocentSubtitle(
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
              effectiveDocent?.script.trim().isNotEmpty == true &&
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

class _FeaturedPlaceHeader extends StatelessWidget {
  const _FeaturedPlaceHeader({
    required this.place,
    required this.language,
    required this.showEvidence,
    required this.saved,
    required this.onToggleSaved,
  });

  final LalaPlace place;
  final String language;
  final bool showEvidence;
  final bool saved;
  final VoidCallback onToggleSaved;

  @override
  Widget build(BuildContext context) {
    final score = place.score?.percent ?? 86;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hasOfficialPlaceImage(place)) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              key: const ValueKey('detail-place-hero-image'),
              height: 170,
              child: _PlaceImage(
                place: place,
                width: double.infinity,
                height: 170,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CategoryBadge(category: place.category, language: language),
                  const SizedBox(height: 7),
                  Text(
                    _placeDisplayName(place, language),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF111827),
                      height: 1.08,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: saved
                  ? _copy(language, ko: '저장됨', en: 'Saved')
                  : _copy(language, ko: '저장', en: 'Save'),
              onPressed: onToggleSaved,
              color: saved ? const Color(0xFFC53030) : const Color(0xFF64748B),
              icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _InlineIconText(
          icon: Icons.place_outlined,
          label: _placeRegionLabel(place, language),
        ),
        if (place.address.trim().isNotEmpty) ...[
          const SizedBox(height: 5),
          _InlineIconText(
            icon: Icons.map_outlined,
            label:
                _singleLanguageText(place.address, language) ??
                _placeRegionLabel(place, language),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _InlineIconText(
              icon: Icons.directions_walk,
              label: '${place.distanceM}m',
            ),
            if (!showEvidence)
              _InlineIconText(
                icon: Icons.explore_outlined,
                label: _copy(language, ko: '로컬 추천', en: 'Local pick'),
              ),
            if (showEvidence) ...[
              Text(
                _copy(language, ko: '로컬 점수', en: 'Local score'),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF1A202C),
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '$score',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFFC53030),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                '/100',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
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
                      _ContextFactChip(icon: fact.icon, label: fact.label),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _ContextFact {
  const _ContextFact({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _ContextFactChip extends StatelessWidget {
  const _ContextFactChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF475569)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: const Color(0xFF334155),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventInfoCard extends StatelessWidget {
  const _EventInfoCard({required this.place, required this.language});

  final LalaPlace place;
  final String language;

  @override
  Widget build(BuildContext context) {
    final isOngoing = place.isOngoing != false;
    final dateText = _eventDateRangeText(place, language);
    final eventUrl = _validEventUri(place.eventUrl);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
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
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.event_available_outlined,
                  color: Color(0xFF1A202C),
                  size: 19,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _copy(language, ko: '행사 정보', en: 'Event info'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _EventStatusPill(isOngoing: isOngoing, language: language),
            ],
          ),
          if (dateText != null) ...[
            const SizedBox(height: 10),
            _InlineIconText(
              icon: Icons.calendar_month_outlined,
              label: dateText,
            ),
          ],
          if (place.isApproximateLocation == true) ...[
            const SizedBox(height: 8),
            _InlineIconText(
              icon: Icons.near_me_disabled_outlined,
              label: _copy(
                language,
                ko: '정확한 좌표가 없어 시 중심 위치로 표시돼요',
                en: 'Exact coordinates are unavailable, so the city center is shown.',
              ),
            ),
          ],
          if (eventUrl != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () =>
                    launchUrl(eventUrl, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(
                  _copy(language, ko: '행사 상세 보기', en: 'Open event details'),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2B6CB0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 11,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EventStatusPill extends StatelessWidget {
  const _EventStatusPill({required this.isOngoing, required this.language});

  final bool isOngoing;
  final String language;

  @override
  Widget build(BuildContext context) {
    final color = isOngoing ? const Color(0xFF2B6CB0) : const Color(0xFF94A3B8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Text(
        isOngoing
            ? _copy(language, ko: '진행 중', en: 'Ongoing')
            : _copy(language, ko: '종료', en: 'Ended'),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _InlineIconText extends StatelessWidget {
  const _InlineIconText({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: const Color(0xFF64748B)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _SignalGrid extends StatelessWidget {
  const _SignalGrid({
    required this.language,
    required this.localSpending,
    required this.demandDispersion,
    required this.cultureRelevance,
    required this.weatherFit,
  });

  final String language;
  final double? localSpending;
  final double? demandDispersion;
  final double? cultureRelevance;
  final double? weatherFit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SignalMeter(
              label: _copy(language, ko: '내국인 소비', en: 'Local spending'),
              value: localSpending ?? 0.82,
              color: const Color(0xFFC53030),
            ),
          ),
          Expanded(
            child: _SignalMeter(
              label: _copy(language, ko: '수요 분산', en: 'Demand spread'),
              value: demandDispersion ?? 0.78,
              color: const Color(0xFFF5C842),
            ),
          ),
          Expanded(
            child: _SignalMeter(
              label: _copy(language, ko: '문화 연계', en: 'Culture fit'),
              value: cultureRelevance ?? 0.91,
              color: const Color(0xFF2B6CB0),
            ),
          ),
          Expanded(
            child: _SignalMeter(
              label: _copy(language, ko: '날씨 적합', en: 'Weather fit'),
              value: weatherFit ?? 0.74,
              color: const Color(0xFF0F766E),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalMeter extends StatelessWidget {
  const _SignalMeter({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bounded = value.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF1A202C),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            bounded.toStringAsFixed(2),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF475569),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: bounded,
              minHeight: 7,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

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
            _copy(language, ko: '공식 데이터 근거', en: 'Official data evidence'),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w900,
            ),
          ),
          ...labels.map((label) => _ProofChip(label: label)),
        ],
      ),
    );
  }
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
              ko: '날씨 ${weather.dust.gradeKo}',
              en: 'Weather ${_dustLabel(weather.dust, language)}',
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

class _ProofChip extends StatelessWidget {
  const _ProofChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.check_circle, size: 17),
      label: Text(label),
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFD7E3F5)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w800),
    );
  }
}

class _PlaceRail extends StatelessWidget {
  const _PlaceRail({
    required this.places,
    required this.source,
    required this.language,
  });

  final List<LalaPlace> places;
  final String? source;
  final String language;

  @override
  Widget build(BuildContext context) {
    final items = places.isEmpty
        ? const <LalaPlace>[]
        : places.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.expand_less, size: 18),
            const SizedBox(width: 6),
            Text(
              _copy(language, ko: '추천 장소', en: 'Recommended places'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const Spacer(),
            _InlineMeta(
              _copy(
                language,
                ko: '${items.length}곳 · ${_sourceLabel(source, language: language)}',
                en: '${items.length} places · ${_sourceLabel(source, language: language)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          _EmptyPlaceState(language: language)
        else
          SizedBox(
            height: 164,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _RecommendedPlaceCard(
                place: items[index],
                selected: index == 0,
                language: language,
              ),
            ),
          ),
      ],
    );
  }
}

class _RouteAndDocentPanel extends StatelessWidget {
  const _RouteAndDocentPanel({
    required this.place,
    required this.language,
    required this.weather,
    required this.intervention,
    required this.dailyPlan,
    required this.docentScript,
    required this.docentAudio,
    required this.audioLoading,
    required this.audioError,
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
  final VoidCallback onFetchAudio;

  @override
  Widget build(BuildContext context) {
    final script = docentScript?.script;
    final canFetchAudio =
        script != null && script.trim().isNotEmpty && !audioLoading;
    final slots = dailyPlan?.slots ?? const <LalaPlanSlot>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _CompactInfoTile(
                icon: Icons.route,
                label: _copy(language, ko: '오늘 코스', en: 'Today route'),
                value: slots.isEmpty
                    ? _copy(
                        language,
                        ko: '날씨 기준 대체 동선 준비 중',
                        en: 'Preparing a weather-aware route',
                      )
                    : _planSlotTitle(slots.first, language),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CompactInfoTile(
                icon: Icons.cloud,
                label: _copy(language, ko: '날씨', en: 'Weather'),
                value: weather == null
                    ? _copy(language, ko: '확인 중', en: 'Checking')
                    : '${_temperatureLabel(weather!.temp)} · ${_dustLabel(weather!.dust, language)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _DocentSubtitle(
          place: place,
          language: language,
          script: script,
          action: intervention?.recommendedAction,
          audioLoading: audioLoading,
          audioError: audioError,
          docentAudio: docentAudio,
          canFetchAudio: canFetchAudio,
          onFetchAudio: onFetchAudio,
        ),
      ],
    );
  }
}

class _DocentSubtitle extends StatelessWidget {
  const _DocentSubtitle({
    required this.place,
    required this.language,
    required this.script,
    required this.action,
    required this.audioLoading,
    required this.audioError,
    required this.docentAudio,
    required this.canFetchAudio,
    required this.onFetchAudio,
    this.onAddToPlan,
  });

  final LalaPlace? place;
  final String language;
  final String? script;
  final String? action;
  final bool audioLoading;
  final String? audioError;
  final LalaAudioResponse? docentAudio;
  final bool canFetchAudio;
  final VoidCallback onFetchAudio;
  final VoidCallback? onAddToPlan;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final body = _docentBody(place: place, script: script, language: language);
    final summary = _docentSummary(
      place: place,
      language: language,
      script: script,
      action: action,
    );
    final actionLabel = _docentActionLabel(
      place: place,
      action: action,
      language: language,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(16),
            border: const Border(
              left: BorderSide(color: Color(0xFF2B6CB0), width: 4),
            ),
            boxShadow: const [
              BoxShadow(
                blurRadius: 24,
                offset: Offset(0, 8),
                color: Color(0x24121F2D),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.record_voice_over_outlined,
                      color: Color(0xFF2B6CB0),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place == null
                              ? _copy(
                                  language,
                                  ko: '로컬 도슨트',
                                  en: 'Local docent',
                                )
                              : _copy(
                                  language,
                                  ko: '${_placeDisplayName(place!, language)} 도슨트',
                                  en: '${_placeDisplayName(place!, language)} docent',
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (docentAudio != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        _audioBytesLabel(docentAudio!.bytes.length, language),
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  body,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.route_outlined,
                      size: 15,
                      color: Color(0xFF2B6CB0),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        actionLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (audioError != null) ...[
                const SizedBox(height: 8),
                Text(
                  audioError!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.error,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (canFetchAudio || audioLoading) ...[
              Expanded(
                child: FilledButton.icon(
                  onPressed: canFetchAudio ? onFetchAudio : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: audioLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.volume_up),
                  label: Text(
                    audioLoading
                        ? _copy(language, ko: '음성 생성 중', en: 'Preparing audio')
                        : _copy(language, ko: '정보 더 듣기', en: 'Listen'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            if (onAddToPlan != null)
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add_circle_outline),
                  label: Text(
                    _copy(language, ko: '오늘 코스에 추가', en: 'Add to plan'),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2B6CB0),
                    side: const BorderSide(color: Color(0xFF2B6CB0)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: onAddToPlan,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

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
    final mapPlaces = _clusterMapPlaces(places, selected, mapLevel);

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
        Positioned(
          left: 22,
          top: 260,
          child: _MapLocationLabel(
            label: weather?.location?.trim().isNotEmpty == true
                ? _locationLabel(weather!.location, language)
                : _locationLabel('수원시', language),
          ),
        ),
      ],
    );
  }

  List<KakaoMapPlace> _clusterMapPlaces(
    List<LalaPlace> places,
    LalaPlace? selected,
    int mapLevel,
  ) {
    final selectedId = selected?.placeId;
    final selectedMarkers = <KakaoMapPlace>[];
    final buckets = <String, List<LalaPlace>>{};
    final shouldExpandClusters = mapLevel <= 3;

    for (final place in places.take(48)) {
      if (place.placeId == selectedId) {
        selectedMarkers.add(_toMapPlace(place, selected: true));
        continue;
      }
      if (shouldExpandClusters) {
        selectedMarkers.add(_toMapPlace(place));
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
            group.fold<double>(0, (sum, place) => sum + place.lat) /
            group.length;
        final lng =
            group.fold<double>(0, (sum, place) => sum + place.lng) /
            group.length;
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
        clustered.addAll(group.map(_toMapPlace));
      }
    }

    return [...clustered, ...selectedMarkers];
  }

  KakaoMapPlace _toMapPlace(LalaPlace place, {bool selected = false}) {
    return KakaoMapPlace(
      id: place.placeId,
      name: _placeDisplayName(place, language),
      category: place.category,
      lat: place.lat,
      lng: place.lng,
      selected: selected,
    );
  }
}

class _MapLocationLabel extends StatelessWidget {
  const _MapLocationLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            blurRadius: 14,
            offset: Offset(0, 5),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF1A202C),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
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
        _AutoDocentFab(
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

class _AutoDocentFab extends StatelessWidget {
  const _AutoDocentFab({
    super.key,
    required this.tooltip,
    required this.label,
    required this.active,
    required this.statusLabel,
    required this.onPressed,
  });

  final String tooltip;
  final String label;
  final bool active;
  final String statusLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = active
        ? const Color(0xFF2B6CB0)
        : const Color(0xFF1A202C).withValues(alpha: 0.84);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: label,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            fixedSize: const Size.square(74),
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            backgroundColor: backgroundColor,
            foregroundColor: Colors.white,
            elevation: 9,
            shadowColor: const Color(0x33000000),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome, size: 19),
              const SizedBox(height: 3),
              Text(
                statusLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

class _RecommendedPlaceCard extends StatelessWidget {
  const _RecommendedPlaceCard({
    required this.place,
    required this.selected,
    this.language = 'ko',
  });

  final LalaPlace place;
  final bool selected;
  final String language;

  @override
  Widget build(BuildContext context) {
    final categoryColor = _categoryColor(place.category);
    final hasImage = _hasOfficialPlaceImage(place);
    return Container(
      key: ValueKey('recommended-place-card-${place.placeId}'),
      width: hasImage ? 270 : 232,
      padding: EdgeInsets.all(hasImage ? 14 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? categoryColor : const Color(0xFFE2E8F0),
          width: selected ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 16,
            offset: Offset(0, 8),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    _CategoryBadge(
                      category: place.category,
                      language: language,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${place.distanceM}m',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _placeDisplayName(place, language),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _placeCardSubtitle(place, language),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          if (hasImage) ...[
            const SizedBox(width: 10),
            _PlaceThumb(place: place),
          ],
        ],
      ),
    );
  }

  Color _categoryColor(String category) {
    return switch (category) {
      'restaurant' => const Color(0xFFC53030),
      'event' => const Color(0xFFF5C842),
      'culture_venue' => const Color(0xFF2B6CB0),
      _ => const Color(0xFF1A202C),
    };
  }

  String _placeCardSubtitle(LalaPlace place, String language) {
    final address = _singleLanguageText(place.address, language);
    if (address != null) {
      return address;
    }
    return _placeRegionLabel(place, language);
  }
}

class _PlaceThumb extends StatelessWidget {
  const _PlaceThumb({required this.place});

  final LalaPlace place;

  @override
  Widget build(BuildContext context) {
    if (!_hasOfficialPlaceImage(place)) {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: _PlaceImage(place: place, width: 76, height: 76),
    );
  }
}

class _PlaceImage extends StatelessWidget {
  const _PlaceImage({
    required this.place,
    required this.width,
    required this.height,
  });

  final LalaPlace place;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final imageUri = _normalizedPlaceImageUri(place.imageUrl);
    if (imageUri != null) {
      return Image.network(
        imageUri.toString(),
        width: width,
        height: height,
        fit: BoxFit.cover,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }
    return const SizedBox.shrink();
  }
}

bool _hasOfficialPlaceImage(LalaPlace place) {
  return _normalizedPlaceImageUri(place.imageUrl) != null;
}

Uri? _normalizedPlaceImageUri(String? rawUrl) {
  final imageUrl = rawUrl?.trim();
  if (imageUrl == null || imageUrl.isEmpty) {
    return null;
  }
  final parsedImageUrl = Uri.tryParse(imageUrl);
  if (parsedImageUrl == null ||
      !parsedImageUrl.hasScheme ||
      parsedImageUrl.host.isEmpty) {
    return null;
  }
  if (parsedImageUrl.scheme == 'http' &&
      parsedImageUrl.host == 'tong.visitkorea.or.kr') {
    return parsedImageUrl.replace(scheme: 'https');
  }
  return parsedImageUrl;
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category, this.language = 'ko'});

  final String category;
  final String language;

  @override
  Widget build(BuildContext context) {
    final color = switch (category) {
      'restaurant' => const Color(0xFFC53030),
      'event' => const Color(0xFFF5C842),
      'culture_venue' => const Color(0xFF2B6CB0),
      _ => const Color(0xFF1A202C),
    };
    final textColor = category == 'event'
        ? const Color(0xFF1A202C)
        : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _categoryLabel(category, language: language),
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CompactInfoTile extends StatelessWidget {
  const _CompactInfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF2B6CB0)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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

class _WeatherMapPill extends StatelessWidget {
  const _WeatherMapPill({
    super.key,
    required this.weather,
    required this.language,
    required this.onPressed,
  });

  final LalaWeather? weather;
  final String language;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final dustPrefix = language == 'en' ? 'Dust' : '미세먼지';
    final data = _publicWeatherOrNull(weather);
    final label = data == null
        ? _copy(language, ko: '날씨 데이터 준비 중', en: 'Weather pending')
        : '${_temperatureLabel(data.temp)} · $dustPrefix ${_dustLabel(data.dust, language)}';
    return _SmallStatusPill(
      key: const ValueKey('weather-pill-hit-target'),
      icon: Icons.thermostat,
      label: label,
      active: true,
      onPressed: onPressed,
    );
  }
}

class _SmallStatusPill extends StatelessWidget {
  const _SmallStatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withValues(alpha: 0.98)
                  : Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 12,
                  offset: Offset(0, 4),
                  color: Color(0x12000000),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: active
                      ? const Color(0xFF2B6CB0)
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
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

class _InlineMeta extends StatelessWidget {
  const _InlineMeta(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: const Color(0xFF64748B),
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _TinyMeta extends StatelessWidget {
  const _TinyMeta(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MapToast extends StatelessWidget {
  const _MapToast({
    required this.icon,
    required this.label,
    required this.color,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onErrorContainer;
    final accent = Theme.of(context).colorScheme.error;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 8),
            Flexible(
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
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('map-error-retry'),
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
            ],
          ],
        ),
      ),
    );
  }
}

class _InterventionToast extends StatelessWidget {
  const _InterventionToast({
    required this.intervention,
    required this.language,
    required this.onOpenPlanner,
    required this.onDismiss,
  });

  final LalaIntervention intervention;
  final String language;
  final VoidCallback onOpenPlanner;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final label = _interventionToastLabel(intervention, language);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                blurRadius: 18,
                offset: Offset(0, 8),
                color: Color(0x30000000),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.tips_and_updates_outlined,
                color: Color(0xFFF5C842),
                size: 19,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    height: 1.22,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('intervention-toast-plan'),
                onPressed: onOpenPlanner,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: const Color(0xFFF5C842),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
                child: Text(_copy(language, ko: '일정 보기', en: 'Plan')),
              ),
              IconButton(
                key: const ValueKey('intervention-toast-close'),
                tooltip: _copy(language, ko: '닫기', en: 'Close'),
                onPressed: onDismiss,
                icon: const Icon(Icons.close, size: 16),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(32, 32),
                  foregroundColor: const Color(0xFFCBD5E1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPlaceState extends StatelessWidget {
  const _EmptyPlaceState({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        _copy(
          language,
          ko: '이 주변 추천을 준비 중입니다.',
          en: 'Recommendations are still being prepared here.',
        ),
      ),
    );
  }
}

bool _isEnglish(String language) => language == 'en';

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
  return _isEnglish(language) ? en : ko;
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
    ko: '요청을 처리하지 못했습니다.',
    en: 'Unable to complete the request.',
  );
}

String _safeUiErrorMessage(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return _requestFailureMessage();
  }
  if (_containsKorean(trimmed)) {
    return trimmed;
  }
  return _requestFailureMessage();
}

String _requestFailureMessage() {
  return '요청을 처리하지 못했습니다. Unable to complete the request.';
}

String _languageOptionLabel(String optionLanguage, String uiLanguage) {
  if (_isEnglish(uiLanguage)) {
    return optionLanguage == 'en' ? 'English' : 'Korean';
  }
  return optionLanguage == 'en' ? '영어' : '한국어';
}

String _locationLabel(String? value, String language) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return _copy(language, ko: '수원', en: 'Suwon');
  }
  final normalized = trimmed.toLowerCase();
  final localized = _singleLanguageText(trimmed, language);
  if (_isEnglish(language)) {
    if (localized == null || localized.isEmpty) {
      return switch (trimmed) {
        '수원' || '수원시' => 'Suwon',
        _ => 'Nearby area',
      };
    }
    return switch (localized) {
      '수원' || '수원시' => 'Suwon',
      final location => location,
    };
  }
  if (localized == null || localized.isEmpty) {
    return switch (normalized) {
      'suwon' || 'suwon-si' || 'suwon city' => '수원',
      _ => '주변 지역',
    };
  }
  return switch (normalized) {
    'suwon' || 'suwon-si' || 'suwon city' => '수원',
    _ => localized,
  };
}

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
  return '날씨가 바뀌었어요. 오늘 일정을 다시 확인해보세요.';
}

String _categoryLabel(String category, {String language = 'ko'}) {
  if (_isEnglish(language)) {
    return switch (category) {
      'restaurant' => 'Food',
      'event' => 'Event',
      'culture_venue' => 'Culture',
      'attraction' => 'Attraction',
      _ => 'Local',
    };
  }
  return switch (category) {
    'restaurant' => '맛집',
    'event' => '행사',
    'culture_venue' => '문화',
    'attraction' => '명소',
    _ => '로컬',
  };
}

String _categoryFilterLabel(String category, String language) {
  if (language == 'en') {
    return switch (category) {
      'all' => 'All',
      'restaurant' => 'Restaurants',
      'event' => 'Events',
      'culture_venue' => 'Culture',
      'attraction' => 'Attractions',
      _ => 'Local',
    };
  }
  return switch (category) {
    'all' => '전체',
    _ => _categoryLabel(category, language: language),
  };
}

String _railCategoryLabel(LalaPlace place, String language) {
  final category = _categoryLabel(place.category, language: language);
  if (place.category != 'event') {
    return category;
  }
  final status = place.isOngoing == false
      ? _copy(language, ko: '종료', en: 'Ended')
      : _copy(language, ko: '진행 중', en: 'Ongoing');
  return '$category · $status';
}

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

String _placeDisplayName(LalaPlace place, String language) {
  if (_isEnglish(language)) {
    final nameEn = _singleLanguageText(place.nameEn, language);
    if (nameEn != null) {
      return nameEn;
    }
    final primaryName = _singleLanguageText(place.name, language);
    if (primaryName != null) {
      return primaryName;
    }
    return 'Local place';
  }
  final nameKo = _singleLanguageText(place.nameKo, language);
  if (nameKo != null) {
    return nameKo;
  }
  final primaryName = _singleLanguageText(place.name, language);
  if (primaryName != null) {
    return primaryName;
  }
  return '이 장소';
}

String _placeRegionLabel(LalaPlace place, String language) {
  if (_isEnglish(language)) {
    final regionEn = _singleLanguageText(place.regionEn, language);
    if (regionEn != null) {
      return regionEn;
    }
    final regionKo = _singleLanguageText(place.regionKo, 'ko');
    if (regionKo != null) {
      final localizedRegion = _locationLabel(regionKo, language);
      if (!_containsKorean(localizedRegion)) {
        return localizedRegion;
      }
    }
    final address = _singleLanguageText(place.address, language);
    if (address != null) {
      return address;
    }
    return 'Nearby area';
  }
  final regionKo = _singleLanguageText(place.regionKo, language);
  if (regionKo != null) {
    return regionKo;
  }
  final address = _singleLanguageText(place.address, language);
  if (address != null) {
    return address;
  }
  return '주변 지역';
}

bool _containsKorean(String value) => RegExp(r'[가-힣]').hasMatch(value);

bool _looksEnglishText(String value) => RegExp(r'[A-Za-z]{3,}').hasMatch(value);

bool _hasMixedKoreanEnglish(String value) {
  return _containsKorean(value) && _looksEnglishText(value);
}

String? _singleLanguageText(String? value, String language) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  if (_isEnglish(language)) {
    if (_containsKorean(trimmed)) {
      return _extractEnglishText(trimmed);
    }
    return trimmed;
  }
  if (!_containsKorean(trimmed) && _looksEnglishText(trimmed)) {
    return null;
  }
  if (_hasMixedKoreanEnglish(trimmed)) {
    return _extractKoreanText(trimmed);
  }
  return trimmed;
}

String? _extractEnglishText(String value) {
  final withoutKorean = value.replaceAll(RegExp(r'[가-힣]+'), ' ');
  final cleaned = _cleanLocalizedFragment(withoutKorean);
  return _looksEnglishText(cleaned) ? cleaned : null;
}

String? _extractKoreanText(String value) {
  final withoutEnglish = value.replaceAll(
    RegExp(r"[A-Za-z][A-Za-z0-9&'.,()/-]*(?:\s+[A-Za-z][A-Za-z0-9&'.,()/-]*)*"),
    ' ',
  );
  final cleaned = _cleanLocalizedFragment(withoutEnglish);
  return _containsKorean(cleaned) ? cleaned : null;
}

String _cleanLocalizedFragment(String value) {
  return value
      .replaceAll(RegExp(r'[\[\]{}()|/·]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^[,.:;~-]+|[,.:;~-]+$'), '')
      .trim();
}

String _audioBytesLabel(int bytes, String language) {
  return _isEnglish(language) ? '$bytes bytes' : '$bytes바이트';
}

bool _shouldShowEventInfo(LalaPlace place) {
  return place.category == 'event' ||
      place.eventStartDate?.trim().isNotEmpty == true ||
      place.eventEndDate?.trim().isNotEmpty == true ||
      place.eventUrl?.trim().isNotEmpty == true ||
      place.isOngoing != null ||
      place.isApproximateLocation == true;
}

Uri? _validEventUri(String? rawUrl) {
  final trimmed = rawUrl?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return null;
  }
  if (uri.scheme != 'https' && uri.scheme != 'http') {
    return null;
  }
  return uri;
}

String? _eventDateRangeText(LalaPlace place, String language) {
  final start = _formatEventDate(place.eventStartDate, language);
  final end = _formatEventDate(place.eventEndDate, language);
  if (start == null && end == null) {
    return null;
  }
  if (start != null && end != null) {
    return '$start ~ $end';
  }
  if (start != null) {
    return _copy(language, ko: '$start부터', en: 'From $start');
  }
  return _copy(language, ko: '~$end까지', en: 'Until $end');
}

String? _formatEventDate(String? rawDate, String language) {
  final trimmed = rawDate?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(trimmed);
  if (match == null) {
    return _singleLanguageText(trimmed, language) ?? trimmed;
  }
  final year = match.group(1)!;
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (_isEnglish(language)) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[month - 1]} $day, $year';
  }
  return '$year년 ${month.toString().padLeft(2, '0')}월 ${day.toString().padLeft(2, '0')}일';
}

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

List<_ContextFact> _placeContextFacts({
  required LalaPlace place,
  required String language,
  required LalaWeather? weather,
  required bool includeEvidence,
}) {
  final score = place.score;
  final features = score?.features ?? const <String, dynamic>{};
  final facts = <_ContextFact>[];

  void add(IconData icon, String? label) {
    final trimmed = label?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == '-') {
      return;
    }
    if (facts.any((fact) => fact.label == trimmed)) {
      return;
    }
    facts.add(_ContextFact(icon: icon, label: trimmed));
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
      '${_outdoorLabel(weather.outdoorStatus, language: language)} · ${_temperatureLabel(weather.temp)}',
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

String _planSlotTitle(LalaPlanSlot slot, String language) {
  final title = slot.title.trim();
  final place = slot.place;
  if (title.isEmpty) {
    return _copy(language, ko: '일정 준비 중', en: 'Preparing stop');
  }
  final localizedTitle = _singleLanguageText(title, language);
  if (localizedTitle != null && localizedTitle.isNotEmpty) {
    return localizedTitle;
  }
  if (_isEnglish(language) && _containsKorean(title)) {
    final placeName = place == null
        ? _copy(language, ko: '이 장소', en: 'this place')
        : _placeDisplayName(place, language);
    return '${_periodLabel(slot.period, language: language)} at $placeName';
  }
  if (!_isEnglish(language) &&
      _looksEnglishText(title) &&
      !_containsKorean(title)) {
    final placeName = place == null
        ? _copy(language, ko: '이 장소', en: 'this place')
        : _placeDisplayName(place, language);
    return '${_periodLabel(slot.period, language: language)} $placeName';
  }
  return title;
}

Color _categoryColor(String category) {
  return switch (category) {
    'restaurant' => const Color(0xFFC53030),
    'event' => const Color(0xFFF5C842),
    'culture_venue' => const Color(0xFF2B6CB0),
    'attraction' => const Color(0xFF1A202C),
    _ => const Color(0xFF1A202C),
  };
}

LalaWeather? _publicWeatherOrNull(LalaWeather? weather) {
  if (weather == null || _isPlaceholderWeatherSource(weather.source)) {
    return null;
  }
  return weather;
}

bool _isPlaceholderWeatherSource(String? source) {
  return switch ((source ?? '').trim()) {
    '' || 'skeleton' || 'fallback' || 'demo_fallback' => true,
    _ => false,
  };
}

String _temperatureLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '-';
  }
  if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(trimmed)) {
    return '$trimmed°C';
  }
  if (RegExp(r'^-?\d+(\.\d+)?C$').hasMatch(trimmed)) {
    return trimmed.replaceFirst('C', '°C');
  }
  return trimmed;
}

double? _temperatureValue(String value) {
  final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  return double.tryParse(match.group(0)!);
}

List<_WeatherChartPoint> _weatherChartPoints({
  required List<LalaForecastItem> items,
  required double columnWidth,
  required double chartHeight,
}) {
  final values = items.map((item) => _temperatureValue(item.temp)).toList();
  final validValues = values.whereType<double>().toList(growable: false);
  final maxValue = validValues.isEmpty ? 1.0 : validValues.reduce(math.max);
  final minValue = validValues.isEmpty ? 0.0 : validValues.reduce(math.min);
  final range = math.max(0.1, maxValue - minValue);
  const topPadding = 28.0;
  const bottomPadding = 18.0;
  final drawHeight = math.max(1.0, chartHeight - topPadding - bottomPadding);

  return [
    for (var index = 0; index < items.length; index += 1)
      _WeatherChartPoint(
        x: index * columnWidth + columnWidth / 2,
        y:
            topPadding +
            (((maxValue - (values[index] ?? minValue)) / range) * drawHeight),
        label: values[index] == null ? '--' : '${values[index]!.round()}°',
      ),
  ];
}

String _weatherChartTimeLabel(String raw, {String language = 'ko'}) {
  if (_isEnglish(language)) {
    return raw.trim();
  }
  final trimmed = raw.trim();
  final match = RegExp(r'(\d{1,2})(?=:\d{2})').firstMatch(trimmed);
  if (match == null) {
    return trimmed;
  }
  return '${match.group(1)!.padLeft(2, '0')}시';
}

IconData _weatherForecastIcon(String icon) {
  final normalized = icon.toLowerCase();
  if (normalized.contains('rain') || normalized.contains('shower')) {
    return Icons.water_drop_outlined;
  }
  if (normalized.contains('snow') || normalized.contains('sleet')) {
    return Icons.ac_unit;
  }
  if (normalized.contains('fog') || normalized.contains('dust')) {
    return Icons.blur_on;
  }
  if (normalized.contains('clear') || normalized.contains('sun')) {
    return Icons.wb_sunny_outlined;
  }
  return Icons.wb_cloudy_outlined;
}

String _periodLabel(String period, {String language = 'ko'}) {
  if (_isEnglish(language)) {
    return switch (period) {
      'morning' => 'Morning',
      'afternoon' => 'Afternoon',
      'evening' => 'Evening',
      _ =>
        period.isEmpty
            ? '-'
            : period.length <= 3
            ? period
            : period.substring(0, 3),
    };
  }
  return switch (period) {
    'morning' => '오전',
    'afternoon' => '오후',
    'evening' => '저녁',
    _ =>
      period.isEmpty
          ? '-'
          : period.length <= 2
          ? period
          : period.substring(0, 2),
  };
}

String _outdoorLabel(String status, {String language = 'ko'}) {
  if (_isEnglish(language)) {
    return switch (status) {
      'good' => 'Good',
      'normal' => 'Normal',
      'bad' => 'Caution',
      _ => status,
    };
  }
  return switch (status) {
    'good' => '좋음',
    'normal' => '보통',
    'bad' => '주의',
    _ => status,
  };
}

String _dustLabel(LalaDust dust, String language) {
  if (!_isEnglish(language)) {
    final gradeKo = _singleLanguageText(dust.gradeKo, language);
    return gradeKo ?? dust.grade;
  }
  return switch (dust.grade.trim()) {
    'good' => 'Good',
    'normal' => 'Normal',
    'bad' => 'Bad',
    'very_bad' => 'Very bad',
    final grade when grade.isEmpty => dust.gradeKo,
    final grade => grade,
  };
}

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

String _docentBody({
  required LalaPlace? place,
  required String? script,
  required String language,
}) {
  final trimmed = script?.trim();
  final placeName = place == null ? null : _placeDisplayName(place, language);
  if (trimmed == null || trimmed.isEmpty) {
    if (_isEnglish(language)) {
      return placeName == null
          ? 'Move the map to prepare nearby local experiences and docent notes.'
          : 'Preparing the cultural context and nearby local experience for $placeName.';
    }
    return placeName == null
        ? '지도를 움직이면 가까운 로컬 경험과 도슨트가 준비됩니다.'
        : '$placeName의 문화 맥락과 주변 로컬 경험을 도슨트로 준비하고 있습니다.';
  }

  final lower = trimmed.toLowerCase();
  if (lower.contains('migration skeleton') ||
      lower.contains('azure openai') ||
      RegExp(r'^this is a .+ docent script').hasMatch(lower)) {
    return _fallbackDocentBody(placeName: placeName, language: language);
  }

  final localized = _singleLanguageText(trimmed, language);
  if (localized != null && localized.isNotEmpty) {
    return localized;
  }
  return _fallbackDocentBody(placeName: placeName, language: language);
}

String _fallbackDocentBody({
  required String? placeName,
  required String language,
}) {
  if (_isEnglish(language)) {
    return placeName == null
        ? 'Preparing a local story from official tourism, culture, and spending signals.'
        : '$placeName connects official tourism and culture data with nearby local spending signals.';
  }
  return placeName == null
      ? '공식 관광·문화 데이터와 지역 소비 신호를 바탕으로 로컬 이야기를 준비하고 있습니다.'
      : '$placeName은 공식 관광·문화 데이터와 지역 소비 신호를 함께 살펴볼 수 있는 로컬 코스입니다.';
}

String _docentSummary({
  required LalaPlace? place,
  required String language,
  required String? script,
  required String? action,
}) {
  final body = _docentBody(
    place: place,
    script: script,
    language: language,
  ).trim();
  if (body.isNotEmpty) {
    return _compactDocentSummary(body);
  }

  final trimmedAction = action?.trim();
  if (trimmedAction != null && trimmedAction.isNotEmpty) {
    return _docentActionLabel(
          place: place,
          action: trimmedAction,
          language: language,
        ) ??
        trimmedAction;
  }

  final placeName = place == null ? null : _placeDisplayName(place, language);
  if (_isEnglish(language)) {
    return placeName == null
        ? 'Preparing local experiences around your current location.'
        : 'Preparing the cultural context and route around $placeName.';
  }
  return placeName == null
      ? '현재 위치 주변의 로컬 경험을 준비하고 있습니다.'
      : '$placeName 주변의 문화 맥락과 동선을 준비하고 있습니다.';
}

String _compactDocentSummary(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ');
  final sentence = RegExp(
    r'^(.{18,80}?[.!?。]|.{18,80}?다[. ]?)',
  ).firstMatch(normalized)?.group(1)?.trim();
  if (sentence != null && sentence.isNotEmpty) {
    return sentence;
  }
  return normalized.length > 56
      ? '${normalized.substring(0, 56)}...'
      : normalized;
}

String? _docentActionLabel({
  required LalaPlace? place,
  required String? action,
  String language = 'ko',
}) {
  final trimmed = action?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final placeName = place == null
      ? _copy(language, ko: '이 장소', en: 'this place')
      : _placeDisplayName(place, language);
  final localizedAction = _singleLanguageText(trimmed, language);
  if (localizedAction != null && localizedAction.isNotEmpty) {
    return localizedAction;
  }
  final looksEnglish = _looksEnglishText(trimmed);
  if (looksEnglish) {
    if (_isEnglish(language)) {
      return trimmed;
    }
    return '$placeName 주변 골목과 지역 상권을 함께 걷는 코스로 이어집니다.';
  }
  if (_isEnglish(language)) {
    return place == null
        ? 'This route continues through nearby local streets and businesses.'
        : 'This route continues through local streets and businesses around $placeName.';
  }
  return trimmed;
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

String _sourceLabel(String? value, {String language = 'ko'}) {
  if (_isEnglish(language)) {
    return switch ((value ?? '').trim()) {
      'db' => 'Live recommendations',
      'mixed' => 'Live + official data',
      'public_mvp_snapshot' => 'Official data',
      'demo_fallback' => 'LALA curation',
      'skeleton' => 'LALA curation',
      '' => '-',
      final source => source,
    };
  }
  return switch ((value ?? '').trim()) {
    'db' => '실시간 추천',
    'mixed' => '실시간·공식 데이터',
    'public_mvp_snapshot' => '공식 데이터',
    'demo_fallback' => '로컬 큐레이션',
    'skeleton' => '로컬 큐레이션',
    '' => '-',
    final source => source,
  };
}

String _weatherSourceLabel(String? value, {String language = 'ko'}) {
  if (_isEnglish(language)) {
    return switch ((value ?? '').trim()) {
      'db' => 'Live weather',
      'kma_ultra_srt_ncst' => 'KMA live weather',
      'mixed' => 'Live + official weather',
      'public_mvp_snapshot' => 'Official weather',
      'demo_fallback' => 'Weather pending',
      'skeleton' => 'Weather pending',
      'fallback' => 'Weather pending',
      '' => '-',
      final source => _sourceLabel(source, language: language),
    };
  }
  return switch ((value ?? '').trim()) {
    'db' => '실시간 날씨',
    'kma_ultra_srt_ncst' => '기상청 실황',
    'mixed' => '실시간·공식 날씨',
    'public_mvp_snapshot' => '공식 날씨',
    'demo_fallback' => '날씨 준비 중',
    'skeleton' => '날씨 준비 중',
    'fallback' => '날씨 준비 중',
    '' => '-',
    final source => _sourceLabel(source, language: language),
  };
}

String? _externalSourceLabel(Object? value, {String language = 'ko'}) {
  if (_isEnglish(language)) {
    return switch ((value?.toString() ?? '').trim()) {
      'tour_api' => 'Korea Tourism data',
      'kcisa' => 'Culture information data',
      'kopis' => 'Performing arts data',
      'dev_seed' => 'LALA curation',
      'public_mvp_snapshot' => 'Official data',
      'canonical' => 'Official places',
      '' => null,
      final source => source,
    };
  }
  return switch ((value?.toString() ?? '').trim()) {
    'tour_api' => '한국관광공사',
    'kcisa' => '문화정보원',
    'kopis' => '공연예술통합전산망',
    'dev_seed' => '로컬 큐레이션',
    'public_mvp_snapshot' => '공식 데이터',
    'canonical' => '공식 장소',
    '' => null,
    final source => source,
  };
}

String _basisLabel(String value, {String language = 'ko'}) {
  if (_isEnglish(language)) {
    return switch (value.trim()) {
      'actual_data' => 'Real data',
      'demo_seed' => 'LALA curation',
      'public_mvp_snapshot' => 'Official data',
      'demo_fallback' => 'LALA curation',
      final basis when basis.isEmpty => '-',
      final basis => basis,
    };
  }
  return switch (value.trim()) {
    'actual_data' => '실데이터',
    'demo_seed' => '로컬 큐레이션',
    'public_mvp_snapshot' => '공식 데이터',
    'demo_fallback' => '로컬 큐레이션',
    final basis when basis.isEmpty => '-',
    final basis => basis,
  };
}

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

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
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
