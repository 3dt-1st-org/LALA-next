// ONMU P0: 지도 탭 — 기존 LalaHomePage(지도/추천/도슨트/플래너 Dashboard)를 그대로 래핑.
// 하단 네비게이션 쉘 안에서도 앱의 기존 동작이 1:1로 유지된다.
import 'package:flutter/material.dart';

import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/features/home/home_page.dart';

class MapRoutePage extends StatelessWidget {
  const MapRoutePage({
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
  Widget build(BuildContext context) {
    return LalaHomePage(
      backendFactory: backendFactory,
      initialConfig: initialConfig,
      locationProvider: locationProvider,
      recommendationRecoveryDelays: recommendationRecoveryDelays,
      authControllerFactory: authControllerFactory,
    );
  }
}
