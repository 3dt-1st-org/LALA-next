// C3 최종: main.dart 에서 이관.
// ONMU P0: MaterialApp(home:) → MaterialApp.router(StatefulShellRoute 3-탭).
// theme/title/의존성 주입 게이트는 그대로. LalaHomePage 는 /map-route 분기에서 래핑된다.
// const 생성자를 유지(main.dart 의 const LalaApp() 보존)하기 위해 State 에서 라우터를 캐시한다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/navigation/local_signal_action.dart';
import 'package:lala_next_app/app/map_sheet_visibility.dart';
import 'package:lala_next_app/core/routing/lala_router.dart';
import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_controller.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_remote.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_remote.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_store.dart';

const List<Duration> _defaultRecommendationRecoveryDelays = <Duration>[
  Duration(seconds: 8),
  Duration(seconds: 16),
  Duration(seconds: 30),
];

class LalaApp extends StatefulWidget {
  const LalaApp({
    super.key,
    this.backendFactory = LalaApiBackend.new,
    this.initialConfig = const LalaAppConfig.fromEnvironment(),
    this.locationProvider = const GeolocatorLalaLocationProvider(),
    this.recommendationRecoveryDelays = _defaultRecommendationRecoveryDelays,
    this.authControllerFactory = createLalaAuthController,
    this.localSignalActionController,
    this.docentExperienceController,
  });

  final LalaBackendFactory backendFactory;
  final LalaAppConfig initialConfig;
  final LalaLocationProvider locationProvider;
  final List<Duration> recommendationRecoveryDelays;
  final LalaAuthControllerFactory authControllerFactory;
  final LocalSignalActionController? localSignalActionController;

  /// 이슈 #120 §4: 앱 루트 단일 도슨트 경험 소유자. null 이면 State 가 생산용
  /// 컨트롤러를 생성·해제한다(주입된 컨트롤러는 호출자 소유 — 해제하지 않는다).
  final DocentExperienceController? docentExperienceController;

  @override
  State<LalaApp> createState() => _LalaAppState();
}

class _LalaAppState extends State<LalaApp> {
  late final LalaAuthController _authController;
  late final LalaAppConfig _appConfig;
  late final GoRouter _router;
  late final TravelPreferencesRemote _travelPreferencesRemote;
  late final TripLibraryRemote _tripLibraryRemote;
  bool _preferenceAccountConnected = false;
  bool _tripLibraryAccountConnected = false;
  DocentExperienceController? _ownedDocentExperience;

  @override
  void initState() {
    super.initState();
    _authController = widget.authControllerFactory(
      LalaAppAuthDependencies(
        apiBaseUri: Uri.parse(widget.initialConfig.baseUri),
      ),
    );
    _appConfig = _authController.config.enabled
        ? widget.initialConfig.copyWith(
            accessTokenProvider: _authController.accessToken,
          )
        : widget.initialConfig;
    _travelPreferencesRemote = LalaTravelPreferencesRemote(
      LalaApiClient(
        baseUri: Uri.parse(widget.initialConfig.baseUri),
        accessTokenProvider: _authController.accessToken,
      ),
    );
    _tripLibraryRemote = LalaTripLibraryRemote(
      LalaApiClient(
        baseUri: Uri.parse(widget.initialConfig.baseUri),
        accessTokenProvider: _authController.accessToken,
      ),
    );
    unawaited(TripLibraryStore.instance.ensureLoaded());
    _authController.addListener(_onAuthStateChanged);
    final docentExperienceController =
        widget.docentExperienceController ??
        (_ownedDocentExperience = DocentExperienceController(
          backendFactory: widget.backendFactory,
          baseConfig: _appConfig,
        ));
    _router = createLalaRouter(
      backendFactory: widget.backendFactory,
      initialConfig: _appConfig,
      locationProvider: widget.locationProvider,
      recommendationRecoveryDelays: widget.recommendationRecoveryDelays,
      authController: _authController,
      localSignalActionController: widget.localSignalActionController,
      docentExperienceController: docentExperienceController,
    );
    unawaited(_authController.initialize());
    // 앱 시작(및 각 테스트) 시 네비게이션 바가 보이도록 시트 활성 상태를 리셋한다.
    lalaMapSheetActive.value = false;
  }

  @override
  void dispose() {
    _authController.removeListener(_onAuthStateChanged);
    if (_preferenceAccountConnected) {
      TravelPreferencesStore.instance.disconnectAccount();
    }
    if (_tripLibraryAccountConnected) {
      TripLibraryStore.instance.disconnectAccount();
    }
    _router.dispose();
    _authController.dispose();
    // 직접 만든 도슨트 컨트롤러만 해제한다(플레이어/백엔드 정리는 비동기).
    final owned = _ownedDocentExperience;
    if (owned != null) {
      unawaited(owned.dispose());
    }
    super.dispose();
  }

  void _onAuthStateChanged() {
    final state = _authController.state;
    final accountReady =
        state.authenticated &&
        state.accountSyncStatus == LalaAccountSyncStatus.ready;
    if (accountReady && !_preferenceAccountConnected) {
      _preferenceAccountConnected = true;
      unawaited(
        TravelPreferencesStore.instance.connectAccount(
          _travelPreferencesRemote,
        ),
      );
    }
    if (accountReady && !_tripLibraryAccountConnected) {
      _tripLibraryAccountConnected = true;
      unawaited(TripLibraryStore.instance.connectAccount(_tripLibraryRemote));
    }
    if (!state.authenticated) {
      if (_preferenceAccountConnected) {
        _preferenceAccountConnected = false;
        TravelPreferencesStore.instance.disconnectAccount();
      }
      if (_tripLibraryAccountConnected) {
        _tripLibraryAccountConnected = false;
        TripLibraryStore.instance.disconnectAccount();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: LalaVisualColors.primaryBlue,
          brightness: Brightness.light,
        ).copyWith(
          primary: LalaVisualColors.primaryBlue,
          onPrimary: Colors.white,
          primaryContainer: LalaVisualColors.primarySoft,
          onPrimaryContainer: LalaVisualColors.ink,
          secondary: LalaVisualColors.culture,
          tertiary: LalaVisualColors.attraction,
          surface: LalaVisualColors.surface,
          surfaceContainerLowest: Colors.white,
          outline: LalaVisualColors.line,
          outlineVariant: LalaVisualColors.line,
        );

    return MaterialApp.router(
      title: 'LALA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: LalaVisualColors.surface,
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
      routerConfig: _router,
    );
  }
}
