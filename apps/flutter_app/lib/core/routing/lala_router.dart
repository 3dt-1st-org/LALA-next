// ONMU P0: GoRouter + StatefulShellRoute.indexedStack(3 분기).
// 분기: 검색(/search) · 지도(/map-route) · 플랜(/plan).
// LalaMainShell 빌더가 하단 네비게이션 바를 제공하고, 지도 분기는 기존 LalaHomePage 를 래핑한다.
//
// ONMU P2: 온보딩 플로우 통합.
// - 상단에 온보딩 4단계 풀스크린 라우트(splash/start/language/location) 추가.
// - GoRouter.redirect + refreshListenable 로 온보딩 게이트:
//   미완료 시 메인 라우트 접근을 /onboarding/splash 로 차단하고,
//   완료(OnboardingState.markCompleted) 시 /map-route 로 전환한다.
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/lala_main_shell.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/onboarding/presentation/pages/language_page.dart';
import 'package:lala_next_app/features/onboarding/presentation/pages/location_consent_page.dart';
import 'package:lala_next_app/features/onboarding/presentation/pages/splash_page.dart';
import 'package:lala_next_app/features/onboarding/presentation/pages/start_page.dart';
import 'package:lala_next_app/features/map_route/presentation/pages/map_route_page.dart';
import 'package:lala_next_app/features/plan/presentation/pages/plan_page.dart';
import 'package:lala_next_app/features/search/presentation/pages/search_page.dart';

GoRouter createLalaRouter({
  required LalaBackendFactory backendFactory,
  required LalaAppConfig initialConfig,
  required LalaLocationProvider locationProvider,
  required List<Duration> recommendationRecoveryDelays,
  required LalaAuthControllerFactory authControllerFactory,
}) {
  return GoRouter(
    initialLocation: LalaRoutePaths.mapRoute,
    refreshListenable: OnboardingState.completedListenable,
    redirect: (BuildContext context, GoRouterState state) {
      final completed = OnboardingState.isCompleted;
      final isOnboarding = state.matchedLocation
          .startsWith(LalaRoutePaths.onboardingPrefix);
      // 온보딩 미완료 시 메인 라우트를 스플래시로 차단.
      if (!completed && !isOnboarding) {
        return LalaRoutePaths.onboardingSplash;
      }
      // 완료 후 온보딩 라우트 잔류 시 메인 쉘로 정리(뒤로가기로 온보딩에 머무는 것 방지).
      if (completed && isOnboarding) {
        return LalaRoutePaths.mapRoute;
      }
      return null;
    },
    routes: <RouteBase>[
      // --- 온보딩(풀스크린, 하단바 없음) ---
      GoRoute(
        path: LalaRoutePaths.onboardingSplash,
        builder: (BuildContext context, GoRouterState state) =>
            const OnboardingSplashPage(),
      ),
      GoRoute(
        path: LalaRoutePaths.onboardingStart,
        builder: (BuildContext context, GoRouterState state) =>
            const OnboardingStartPage(),
      ),
      GoRoute(
        path: LalaRoutePaths.onboardingLanguage,
        builder: (BuildContext context, GoRouterState state) =>
            const OnboardingLanguagePage(),
      ),
      GoRoute(
        path: LalaRoutePaths.onboardingLocation,
        builder: (BuildContext context, GoRouterState state) =>
            OnboardingLocationConsentPage(locationProvider: locationProvider),
      ),
      // --- 메인 쉘(검색/지도/플랜 3-탭) ---
      StatefulShellRoute.indexedStack(
        builder: (BuildContext context, GoRouterState state,
            StatefulNavigationShell navigationShell) {
          return LalaMainShell(navigationShell: navigationShell);
        },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: LalaRoutePaths.search,
                builder: (BuildContext context, GoRouterState state) =>
                    const SearchPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: LalaRoutePaths.mapRoute,
                builder: (BuildContext context, GoRouterState state) =>
                    MapRoutePage(
                      backendFactory: backendFactory,
                      initialConfig: initialConfig,
                      locationProvider: locationProvider,
                      recommendationRecoveryDelays:
                          recommendationRecoveryDelays,
                      authControllerFactory: authControllerFactory,
                    ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: LalaRoutePaths.plan,
                builder: (BuildContext context, GoRouterState state) =>
                    const PlanPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
