// ONMU P0: GoRouter + StatefulShellRoute.indexedStack(3 분기).
// 분기: 검색(/search) · 지도(/map-route) · 플랜(/plan).
// LalaMainShell 빌더가 하단 네비게이션 바를 제공하고, 지도 분기는 기존 LalaHomePage 를 래핑한다.
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/lala_main_shell.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
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
    routes: <RouteBase>[
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
