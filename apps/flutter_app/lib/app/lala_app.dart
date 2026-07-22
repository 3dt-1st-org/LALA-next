// C3 최종: main.dart 에서 이관.
// ONMU P0: MaterialApp(home:) → MaterialApp.router(StatefulShellRoute 3-탭).
// theme/title/의존성 주입 게이트는 그대로. LalaHomePage 는 /map-route 분기에서 래핑된다.
// const 생성자를 유지(main.dart 의 const LalaApp() 보존)하기 위해 State 에서 라우터를 캐시한다.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/app/map_sheet_visibility.dart';
import 'package:lala_next_app/core/routing/lala_router.dart';

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
  });

  final LalaBackendFactory backendFactory;
  final LalaAppConfig initialConfig;
  final LalaLocationProvider locationProvider;
  final List<Duration> recommendationRecoveryDelays;
  final LalaAuthControllerFactory authControllerFactory;

  @override
  State<LalaApp> createState() => _LalaAppState();
}

class _LalaAppState extends State<LalaApp> {
  // 위젯 의존성은 불변이므로 라우터는 initState 에서 한 번만 구성한다.
  late final GoRouter _router = createLalaRouter(
    backendFactory: widget.backendFactory,
    initialConfig: widget.initialConfig,
    locationProvider: widget.locationProvider,
    recommendationRecoveryDelays: widget.recommendationRecoveryDelays,
    authControllerFactory: widget.authControllerFactory,
  );

  @override
  void initState() {
    super.initState();
    // 앱 시작(및 각 테스트) 시 네비게이션 바가 보이도록 시트 활성 상태를 리셋한다.
    lalaMapSheetActive.value = false;
  }

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

    return MaterialApp.router(
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
      routerConfig: _router,
    );
  }
}
