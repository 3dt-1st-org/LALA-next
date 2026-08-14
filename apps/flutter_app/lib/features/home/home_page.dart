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
import 'package:lala_next_app/core/location/app_settings_opener.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/navigation/local_signal_action.dart';
import 'package:lala_next_app/core/state/plan_context_store.dart';
import 'package:lala_next_app/core/state/saved_place_store.dart';
import 'package:lala_next_app/core/state/selected_place_store.dart';
import 'package:lala_next_app/features/location/widgets/manual_location_sheet.dart';
import 'package:lala_next_app/features/location/widgets/permanently_denied_recovery.dart';
import 'package:lala_next_app/features/map/domain/active_map_sheet.dart';
import 'package:lala_next_app/features/map/map_helpers.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
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
    this.localSignalActionController,
    super.key,
  });

  final LalaBackendFactory backendFactory;
  final LalaAppConfig initialConfig;
  final LalaLocationProvider locationProvider;
  final List<Duration> recommendationRecoveryDelays;
  final LalaAuthControllerFactory authControllerFactory;
  final LocalSignalActionController? localSignalActionController;

  @override
  State<LalaHomePage> createState() => _LalaHomePageState();

  /// Test-only seam (D4/D5): simulates the Kakao map firing a camera-idle
  /// event, driving the real debounce → _refresh path so the bounds-threading
  /// and request-epoch guard can be exercised without a live map platform.
  @visibleForTesting
  static void simulateCameraIdleForTesting(
    BuildContext context,
    KakaoMapCamera camera,
  ) {
    final state = context.findAncestorStateOfType<_LalaHomePageState>();
    state?._handleMapCameraIdle(camera);
  }

  /// Test-only seam (D5 response-ordering): dispatches a _refresh directly
  /// (bypassing the camera-idle gate/debounce) so two overlapping queries with
  /// out-of-order resolution can exercise the request-epoch guard. Fire-and-
  /// forget, matching the real debounce call site (the refresh suspends at the
  /// places await and is resolved later by the test's completer).
  @visibleForTesting
  static void simulateRefreshForTesting(BuildContext context) {
    final state = context.findAncestorStateOfType<_LalaHomePageState>();
    state?._refresh();
  }

  /// Test-only diagnostic (D5): the loaded places' first name + count, so the
  /// request-epoch guard can be verified against the candidate SET held in
  /// state (the newer result) rather than via fragile text-finding.
  @visibleForTesting
  static ({int count, String? firstName, bool loading}) placesStateForTesting(
    BuildContext context,
  ) {
    final state = context.findAncestorStateOfType<_LalaHomePageState>();
    final places = state?._places?.data?.places ?? const <LalaPlace>[];
    return (
      count: places.length,
      firstName: places.isEmpty ? null : places.first.name,
      loading: state?._loading ?? false,
    );
  }
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
  // 추천(places) 로드 실패의 honest 종류(unavailable vs error). _error 문자열만으로는
  // 도달 실패와 서비스 오류를 구분할 수 없어 별도로 보존한다(§13.5). null = 실패 없음.
  RecommendationFailureKind? _placeFailureKind;
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
  ActiveMapSheet? _activeSheet;
  bool _voiceEnabled = true;
  bool _autoDocentEnabled = false;
  bool _showEvidence = false;
  bool _interventionToastDismissed = false;
  bool _locationConsentEnabled = true;
  bool _locationRequestInFlight = false;
  bool _locationFallbackNoticeVisible = false;
  // OS-level permanent denial gets a dedicated recovery surface (Open settings
  // where supported + manual escape), distinct from the ordinary denied toast.
  bool _locationPermanentlyDenied = false;
  bool _locationStartPromptVisible = false;
  bool _recommendationRailExpanded = true;
  List<String> _focusedClusterMemberIds = const <String>[];
  final Set<String> _savedPlaceIds = <String>{};
  final Set<String> _detailDocentPlayedPlaceIds = <String>{};
  DateTime? _lastAutoDocentAt;
  String? _lastAutoDocentPlaceId;
  double? _lastPlacesFetchLat;
  double? _lastPlacesFetchLng;
  // V1 bounds-query (D5): track the map level at the last successful places
  // fetch so a pure zoom (center unchanged) still triggers a reload.
  int? _lastPlacesFetchLevel;
  // V1 bounds-query (D4): latest viewport rectangle from the camera; threaded
  // into _currentConfig() → LalaAppConfig.bounds. null → center+radius (B2).
  KakaoMapBounds? _latestMapBounds;
  // V1 bounds-query (D5 response-ordering): monotonic epoch captured per
  // _refresh dispatch; a stale earlier reply is discarded when a newer query
  // has fired. Additive — also hardens the existing center+radius path.
  int _refreshEpoch = 0;
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
  LocalSignalPlaceActionRequest? _pendingLocalSignalAction;
  bool _localSignalActionRefreshAttempted = false;
  bool _localSignalActionCanonicalLookupAttempted = false;
  // Cross-tab shared-state listeners (§13.4). The map is the selected-place SSOT
  // writer; the listener rebuilds so a selection made on another tab reflects here
  // too. The plan listener adopts a timeline published by the plan tab instead of
  // the map fetching independently (eliminates dual-fetch divergence).
  late final VoidCallback _onSelectedPlaceChanged;
  late final VoidCallback _onPlanChanged;
  // V5-B SAVE: the saved-place set is hydrated from SavedPlaceStore on cold start
  // (bootstrap restores it from lala.v5.*) and kept in sync here so a save toggled
  // anywhere reflects on the map/detail header too.
  late final VoidCallback _onSavedPlacesChanged;
  // Why: separates a selection this tab published (its own call site already
  // drove the sheet/camera) from an external publish (search tab) that the store
  // listener must adopt through the local-tap path.
  String? _lastSelectionPublishedHere;

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig;
    _baseConfig = config;
    // 온보딩/다른 탭에서 확정된 컨텍스트(수동 선택 또는 현재 위치)가 있으면 그 좌표로
    // 시드한다. 없으면 공개된 기본 지역(LalaAppConfig)으로 폴백한다.
    final region = RegionContextStore.current;
    _queryLat = region?.lat ?? config.lat;
    _queryLng = region?.lng ?? config.lng;
    _uiLanguage = OnboardingState.language;
    _locationStartPromptVisible = config.requireLocationStartConfirmation;
    _authController = widget.authControllerFactory(
      LalaAppAuthDependencies(apiBaseUri: Uri.parse(config.baseUri)),
    );
    _lastAuthStatus = _authController.state.status;
    _authController.addListener(_handleAuthStateChanged);
    OnboardingState.languageListenable.addListener(_handleUiLanguageChanged);
    widget.localSignalActionController?.addListener(_handleLocalSignalAction);
    // Selected place: rebuild when the shared id changes so another tab's selection
    // reflects here. The map resolves SelectedPlaceStore.current against its own
    // candidate set at build time (placeById ?? featuredPlace) — identical behavior
    // to the old private field, now sourced from the shared holder.
    // An EXTERNAL publish (search tab) that resolves against the loaded places is
    // adopted through _selectPlace so the detail sheet/category/camera behave
    // exactly like a map-originated tap; map-originated publishes no-op past the
    // guard (their call site already drove that UI).
    _onSelectedPlaceChanged = () {
      if (!mounted) {
        return;
      }
      final id = SelectedPlaceStore.current;
      if (id != null && id != _lastSelectionPublishedHere) {
        final place = placeById(
          _places?.data?.places ?? const <LalaPlace>[],
          id,
        );
        if (place != null) {
          _selectPlace(place, ensureVisible: true);
          return;
        }
      }
      setState(() {});
    };
    SelectedPlaceStore.listenable.addListener(_onSelectedPlaceChanged);
    // Plan: adopt a timeline published by the plan tab. No-op-skip our own
    // publishes (same instance) and external clears (null) so a valid local plan
    // is never wiped by another tab's transient null.
    _onPlanChanged = () {
      if (!mounted) {
        return;
      }
      final next = PlanContextStore.current;
      if (next == null || next == _dailyPlan?.data) {
        return;
      }
      setState(() {
        _dailyPlan = LalaEnvelope<LalaDailyPlan>(
          ok: true,
          data: next,
          meta: const <String, dynamic>{},
          error: null,
          statusCode: 200,
          requestId: null,
        );
      });
    };
    PlanContextStore.listenable.addListener(_onPlanChanged);
    _backend = widget.backendFactory(_currentConfig());
    // V5-B SAVE: hydrate the local mirror from the cold-start-restored store, then
    // subscribe so future toggles (this tab or elsewhere) stay in sync + durable.
    _savedPlaceIds.addAll(SavedPlaceStore.current);
    _onSavedPlacesChanged = () {
      if (!mounted) {
        return;
      }
      setState(() {
        _savedPlaceIds
          ..clear()
          ..addAll(SavedPlaceStore.current);
      });
    };
    SavedPlaceStore.listenable.addListener(_onSavedPlacesChanged);
    unawaited(_initializeAuth());
    if (!config.requireLocationStartConfirmation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (region?.source == RegionSource.manual) {
            // A restored manual region is an explicit durable choice. Start the
            // map from it without asking for live coordinates; the current-
            // location control remains the only action that may replace it.
            _refresh(forceWeather: true);
          } else {
            _requestLocationThenRefresh(initial: true);
          }
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
    OnboardingState.languageListenable.removeListener(_handleUiLanguageChanged);
    SelectedPlaceStore.listenable.removeListener(_onSelectedPlaceChanged);
    PlanContextStore.listenable.removeListener(_onPlanChanged);
    SavedPlaceStore.listenable.removeListener(_onSavedPlacesChanged);
    widget.localSignalActionController?.removeListener(
      _handleLocalSignalAction,
    );
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
      // V1 bounds-query (D4): carry the latest viewport rectangle into the
      // /places call site; null preserves the center+radius fallback (B2).
      bounds: _latestMapBounds,
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
    _publishSelection(null);
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
        _locationPermanentlyDenied = false;
        _currentLocation = location;
        _queryLat = location.lat;
        _queryLng = location.lng;
        _mapFocusLat = location.lat;
        _mapFocusLng = location.lng;
        _mapLevel = _defaultMapLevel;
        _locationRequestInFlight = false;
      });
      // 검색/플랜 탭이 같은 현재 위치 컨텍스트로 동작하도록 공유 저장소에 반영한다.
      RegionContextStore.set(
        RegionContext.current(lat: location.lat, lng: location.lng),
      );
      await _refresh(forceWeather: true);
    } else {
      setState(() {
        _locationRequestInFlight = false;
        // Why: permanentlyDenied is an OS-level denial the system dialog can't
        // re-surface, so it gets a dedicated recovery surface (Open settings +
        // manual escape) instead of the ordinary retry toast. denied keeps the
        // retry toast; unavailable only surfaces it on initial/reset.
        if (resolvedResult.status ==
            LalaLocationResultStatus.permanentlyDenied) {
          _locationPermanentlyDenied = true;
          _locationFallbackNoticeVisible = false;
        } else if (resolvedResult.status == LalaLocationResultStatus.denied) {
          _locationPermanentlyDenied = false;
          _locationFallbackNoticeVisible = true;
        } else if (initial || resetSelection) {
          _locationPermanentlyDenied = false;
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
    // D5 response-ordering: capture a monotonic epoch for this dispatch; result
    // application is skipped if a newer _refresh has since fired (stale discard).
    final epoch = ++_refreshEpoch;
    final config = _currentConfig();
    setState(() {
      _loading = true;
      if (!fromAutoRecovery) {
        _error = null;
        _placeFailureKind = null;
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
      // places 실패 종류(unavailable vs error)를 honest 하게 구분하기 위해 예외를
      // 별도 캡처한다(§13.5). loadOptional 은 메시지로 평탄화해 종류가 사라지므로,
      // 로더 자체를 감싸 throw 를 포착한다.
      Object? placesFailure;
      Future<LalaEnvelope<LalaPlacesResponse>?> loadPlacesCapture() async {
        try {
          return await loadWithSingleRetry(
            _backend.getPlaces,
            shouldRetry: true,
            retryDelay: _recommendationRequestRetryDelay,
          );
        } on Object catch (error) {
          placesFailure = error;
          // loadOptional 과 동일한 fallback 메시지를 loadErrors 에 반영한다.
          loadErrors.add(recommendationLoadFailureMessage(config.lang));
          return null;
        }
      }

      final placesFuture = loadPlacesCapture();
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
      final selectedPlace = placeById(
        effectiveItems,
        SelectedPlaceStore.current,
      );
      final firstPlace =
          autoDocentPlace ?? selectedPlace ?? featuredPlace(effectiveItems);
      final coreLoadError = loadErrors.isEmpty
          ? null
          : loadErrors.toSet().take(2).join(' / ');

      if (!mounted || epoch != _refreshEpoch) {
        return;
      }
      setState(() {
        _health = health;
        _readiness = readiness;
        _syncSpeechCapabilityFromReadiness(readiness);
        _places = places ?? previousPlaces;
        // places 가 새로 로드되었으면 실패 종류를 지운다(성공). 그렇지 않고 포착된
        // 예외가 있으면 unavailable/error 로 분류해 보존한다(§13.5 honest states).
        _placeFailureKind = places != null
            ? null
            : (placesFailure == null
                  ? _placeFailureKind
                  : recommendationFailureKind(placesFailure));
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
          // D5: record the map level at this successful fetch so a later pure
          // zoom (center unchanged) is detected as a level change.
          _lastPlacesFetchLevel = _mapLevel;
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

        if (!mounted || epoch != _refreshEpoch) {
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

      if (!mounted || epoch != _refreshEpoch) {
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
      // Cross-tab plan SSOT (§13.4): publish the fetched plan so the plan tab and
      // any other reader share the same timeline instead of independently
      // refetching and diverging. Only a real result is published — a failed fetch
      // (null) must not wipe a valid shared plan.
      final sharedPlan = dailyPlan?.data;
      if (sharedPlan != null) {
        PlanContextStore.set(sharedPlan);
      }
    } on Object catch (error) {
      if (!mounted || epoch != _refreshEpoch) {
        return;
      }
      setState(() {
        _error = _safeErrorMessage(
          error,
          fallbackMessage: (_) => recommendationLoadFailureMessage(config.lang),
        );
      });
      _cancelInterventionToastTimer();
      _scheduleRecommendationRecovery(reason: 'refresh-exception');
    } finally {
      // D5: a stale dispatch must not clear the loading indicator while a newer
      // query is still in flight.
      if (mounted && epoch == _refreshEpoch) {
        setState(() {
          _loading = false;
        });
      }
      _tryResolveLocalSignalAction();
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
    return placeById(places, SelectedPlaceStore.current) ??
        featuredPlace(places);
  }

  void _selectCategory(String category) {
    setState(() {
      _selectedCategory = category;
      _publishSelection(null);
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

  /// The map tab's sole write seam into the shared selection store. Records the
  /// published id so the store listener can tell map-originated publishes (which
  /// drive their own UI here) from external ones (search tab) it must adopt.
  void _publishSelection(String? id) {
    _lastSelectionPublishedHere = id;
    SelectedPlaceStore.set(id);
  }

  void _selectPlace(
    LalaPlace place, {
    bool ensureVisible = false,
    LalaEnvelope<LalaPlacesResponse>? loadedPlaces,
  }) {
    setState(() {
      if (loadedPlaces != null) {
        _places = loadedPlaces;
      }
      if (ensureVisible &&
          _selectedCategory != 'all' &&
          _selectedCategory != place.category) {
        _selectedCategory = place.category;
      }
      _publishSelection(place.placeId);
      _activeSheet = ActiveMapSheet.detail;
      _docentAudio = null;
      _audioError = null;
      _focusedClusterMemberIds = const <String>[];
      _mapFocusLat = place.lat;
      _mapFocusLng = place.lng;
      _mapLevel = _focusedPlaceMapLevel;
    });
  }

  void _handleLocalSignalAction() {
    final request = widget.localSignalActionController?.takePending();
    if (request == null || !mounted) return;
    _pendingLocalSignalAction = request;
    _localSignalActionRefreshAttempted = false;
    _localSignalActionCanonicalLookupAttempted = false;
    _tryResolveLocalSignalAction();
  }

  void _tryResolveLocalSignalAction() {
    final request = _pendingLocalSignalAction;
    if (request == null || !mounted || _loading) return;

    final place = placeById(
      _places?.data?.places ?? const <LalaPlace>[],
      request.placeId,
    );
    if (place == null &&
        _places == null &&
        !_localSignalActionRefreshAttempted) {
      _localSignalActionRefreshAttempted = true;
      unawaited(_refresh(forceWeather: true));
      return;
    }
    if (place == null) {
      final loadedCategory = _places?.data?.query.category;
      if (loadedCategory != 'all' &&
          !_localSignalActionCanonicalLookupAttempted) {
        _localSignalActionCanonicalLookupAttempted = true;
        unawaited(_resolveLocalSignalPlaceAcrossCategories(request));
        return;
      }
      _pendingLocalSignalAction = null;
      _showLocalSignalActionUnavailable();
      return;
    }

    _pendingLocalSignalAction = null;
    _localSignalActionRefreshAttempted = false;
    _localSignalActionCanonicalLookupAttempted = false;
    _selectPlace(place, ensureVisible: true);
    if (request.action == LocalSignalPlaceAction.addToPlan) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && SelectedPlaceStore.current == place.placeId) {
          _openSheet(ActiveMapSheet.planner);
        }
      });
    }
  }

  Future<void> _resolveLocalSignalPlaceAcrossCategories(
    LocalSignalPlaceActionRequest request,
  ) async {
    final lookupBackend = widget.backendFactory(
      _currentConfig().copyWith(category: 'all'),
    );
    try {
      final response = await lookupBackend.getPlaces();
      final payload = response.data;
      if (!response.ok ||
          response.statusCode < 200 ||
          response.statusCode >= 300 ||
          payload == null ||
          payload.query.category != 'all') {
        throw StateError('Canonical place lookup was not usable.');
      }
      final places = payload.places;
      final place = placeById(places, request.placeId);
      if (!mounted || _pendingLocalSignalAction != request) {
        return;
      }
      if (place == null) {
        _pendingLocalSignalAction = null;
        _showLocalSignalActionUnavailable();
        return;
      }

      _pendingLocalSignalAction = null;
      _localSignalActionCanonicalLookupAttempted = false;
      _selectPlace(place, ensureVisible: true, loadedPlaces: response);
      if (request.action == LocalSignalPlaceAction.addToPlan) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && SelectedPlaceStore.current == place.placeId) {
            _openSheet(ActiveMapSheet.planner);
          }
        });
      }
    } on Object catch (error) {
      if (mounted && _pendingLocalSignalAction == request) {
        _pendingLocalSignalAction = null;
        _showLocalSignalActionLookupError(error);
      }
    } finally {
      lookupBackend.close();
    }
  }

  void _showLocalSignalActionLookupError(Object error) {
    final message = _safeErrorMessage(
      error,
      fallbackMessage: (_) => _uiLanguage == 'en'
          ? 'This place could not be confirmed right now.'
          : '장소 정보를 지금 확인하지 못했어요.',
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showLocalSignalActionUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _uiLanguage == 'en'
              ? 'This place is not available in the current map results.'
              : '현재 지도 결과에서 연결된 장소를 찾지 못했어요.',
        ),
      ),
    );
  }

  void _clearPlaceSelection() {
    setState(() {
      _publishSelection(null);
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
      _publishSelection(
        cluster.clusterMemberIds.isEmpty
            ? null
            : cluster.clusterMemberIds.first,
      );
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
      // V1 bounds-query (D5): reload on a pure zoom too (center unchanged but
      // map level changed) so the viewport rectangle refreshes on zoom.
      lastFetchLevel: _lastPlacesFetchLevel,
      currentLevel: normalizedLevel,
    );
    setState(() {
      _queryLat = camera.lat;
      _queryLng = camera.lng;
      _mapFocusLat = camera.lat;
      _mapFocusLng = camera.lng;
      _mapLevel = normalizedLevel;
      // V1 bounds-query (D4): keep the latest viewport rectangle for the next
      // _refresh; null (map without getBounds) restores the center+radius path.
      _latestMapBounds = camera.bounds;
      if (shouldReloadPlaces) {
        _publishSelection(null);
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
    // V5-B SAVE: the store is the SSOT and persists to lala.v5.* via the
    // write-through listener in ActionPersistence. The _onSavedPlacesChanged
    // listener syncs the local mirror + rebuilds.
    SavedPlaceStore.toggle(placeId);
  }

  void _toggleRecommendationRail() {
    setState(() {
      _recommendationRailExpanded = !_recommendationRailExpanded;
    });
  }

  void _setUiLanguage(String language) {
    OnboardingState.selectLanguage(language);
  }

  void _handleUiLanguageChanged() {
    final language = OnboardingState.language;
    if (!mounted || _uiLanguage == language) {
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
      _locationPermanentlyDenied = false;
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
      _locationPermanentlyDenied = false;
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
      _locationPermanentlyDenied = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _requestLocationThenRefresh(initial: true, resetSelection: true);
      }
    });
  }

  // Real hand-off to the OS app settings page where supported. The recovery card
  // only renders this action when canOpenAppSettings is true (native), so it is
  // never a fake action; after the user grants and returns they tap Retry.
  Future<void> _openAppSettingsForLocation() async {
    await openAppSettings();
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
    _publishSelection(place.placeId);
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
      _locationPermanentlyDenied = false;
      _locationStartPromptVisible = false;
      _currentLocation = null;
      _queryLat = selected.lat;
      _queryLng = selected.lng;
      _mapFocusLat = selected.lat;
      _mapFocusLng = selected.lng;
      _mapLevel = _defaultMapLevel;
    });
    // 수동 선택을 검색/플랜 탭과 공유한다(온보딩 선택이 폐기되지 않도록).
    // Why: await the manual-id write before the UI refresh so a kill right after
    // the pick cannot lose the region the user just chose.
    await RegionContextStore.setAndFlush(RegionContext.manual(selected));
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
          child: Stack(
            children: <Widget>[
              Builder(
                builder: (context) => Dashboard(
                  loading: _loading,
                  error: _error,
                  placeFailureKind: _placeFailureKind,
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
                  selectedPlaceId: SelectedPlaceStore.current,
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
                  recommendationRecoveryAttempt:
                      _recommendationRecoveryAttempts,
                  focusedClusterMemberIds: _focusedClusterMemberIds,
                  queryLat: _queryLat,
                  queryLng: _queryLng,
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
              // permanentlyDenied recovery: a calm, non-blocking card over the
              // map. The map stays usable beneath it; the manual escape and the
              // real "Open settings" action (native only) resolve the state.
              if (_locationPermanentlyDenied)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: SafeArea(
                    child: SingleChildScrollView(
                      child: PermanentlyDeniedRecovery(
                        language: _uiLanguage,
                        canOpenSettings: canOpenAppSettings,
                        onOpenSettings: _openAppSettingsForLocation,
                        onRetry: _retryLocationConsent,
                        onChooseArea: () => _openManualLocationSheet(context),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
