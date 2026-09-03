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
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/app/lala_main_shell.dart';
import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/navigation/local_signal_action.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/onboarding/presentation/pages/account_link_page.dart';
import 'package:lala_next_app/features/onboarding/presentation/pages/language_page.dart';
import 'package:lala_next_app/features/onboarding/presentation/pages/location_consent_page.dart';
import 'package:lala_next_app/features/onboarding/presentation/pages/splash_page.dart';
import 'package:lala_next_app/features/onboarding/presentation/pages/start_page.dart';
import 'package:lala_next_app/features/map_route/presentation/pages/map_route_page.dart';
import 'package:lala_next_app/features/plan/presentation/pages/plan_page.dart';
import 'package:lala_next_app/features/search/presentation/pages/search_page.dart';
import 'package:lala_next_app/features/local_signals/presentation/pages/local_signals_page.dart';
import 'package:lala_next_app/features/local_signals/presentation/pages/local_signal_detail_page.dart';
import 'package:lala_next_app/features/intervention/presentation/pages/intervention_comparison_page.dart';
import 'package:lala_next_app/features/place/presentation/pages/place_detail_page.dart';
import 'package:lala_next_app/features/preferences/presentation/travel_preferences_page.dart';
import 'package:lala_next_app/features/preferences/presentation/preference_sync_conflict_page.dart';
import 'package:lala_next_app/features/profile/presentation/pages/account_page.dart';
import 'package:lala_next_app/features/profile/presentation/pages/profile_page.dart';
import 'package:lala_next_app/features/settings/presentation/pages/privacy_location_page.dart';
import 'package:lala_next_app/features/trip_library/presentation/pages/past_trips_page.dart';
import 'package:lala_next_app/features/trip_library/presentation/pages/saved_places_page.dart';
import 'package:lala_next_app/features/trip_library/presentation/pages/trip_settings_page.dart';
import 'package:lala_next_app/features/trip_library/presentation/pages/visit_confirmation_page.dart';
import 'package:lala_next_app/features/community/presentation/pages/community_feed_page.dart';
import 'package:lala_next_app/features/community/presentation/pages/community_post_detail_page.dart';
import 'package:lala_next_app/features/community/presentation/pages/community_create_post_page.dart';
import 'package:lala_next_app/features/community/presentation/pages/chat_room_list_page.dart';
import 'package:lala_next_app/features/community/presentation/pages/chat_room_page.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_controller.dart';
import 'package:lala_next_app/features/docent/presentation/pages/docent_player_page.dart';

GoRouter createLalaRouter({
  required LalaBackendFactory backendFactory,
  required LalaAppConfig initialConfig,
  required LalaLocationProvider locationProvider,
  required List<Duration> recommendationRecoveryDelays,
  LalaAuthController? authController,
  LalaAuthControllerFactory? authControllerFactory,
  LocalSignalActionController? localSignalActionController,

  /// 이슈 #120 §4: 앱 루트 단일 도슨트 경험 소유자 — 쉘 미니플레이어와
  /// 전체 플레이어 라우트가 같은 컨트롤러를 공유한다.
  required DocentExperienceController docentExperienceController,
}) {
  assert(authController != null || authControllerFactory != null);
  final signalActionController =
      localSignalActionController ?? LocalSignalActionController();
  return GoRouter(
    initialLocation: LalaRoutePaths.mapRoute,
    refreshListenable: OnboardingState.completedListenable,
    redirect: (BuildContext context, GoRouterState state) {
      final completed = OnboardingState.isCompleted;
      final isOnboarding = state.matchedLocation.startsWith(
        LalaRoutePaths.onboardingPrefix,
      );
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
            OnboardingLocationConsentPage(
              locationProvider: locationProvider,
              showAccountLink: authController?.config.enabled ?? false,
            ),
      ),
      if (authController != null)
        GoRoute(
          path: LalaRoutePaths.onboardingAccount,
          builder: (BuildContext context, GoRouterState state) =>
              OnboardingAccountLinkPage(authController: authController),
        ),
      // --- Main shell (search/map/plan/Local Signals/profile) ---
      StatefulShellRoute.indexedStack(
        builder:
            (
              BuildContext context,
              GoRouterState state,
              StatefulNavigationShell navigationShell,
            ) {
              return LalaMainShell(
                navigationShell: navigationShell,
                docentExperienceController: docentExperienceController,
              );
            },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: LalaRoutePaths.search,
                builder: (BuildContext context, GoRouterState state) =>
                    SearchPage(
                      initialConfig: initialConfig,
                      docentExperienceController: docentExperienceController,
                    ),
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
                      authController: authController,
                      authControllerFactory: authControllerFactory,
                      localSignalActionController: signalActionController,
                      docentExperienceController: docentExperienceController,
                    ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: LalaRoutePaths.plan,
                builder: (BuildContext context, GoRouterState state) =>
                    PlanPage(
                      initialConfig: initialConfig,
                      docentExperienceController: docentExperienceController,
                    ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: LalaRoutePaths.localSignals,
                builder: (BuildContext context, GoRouterState state) =>
                    LocalSignalsPage(
                      backendFactory: backendFactory,
                      initialConfig: initialConfig,
                      onPlaceAction: (request) {
                        signalActionController.dispatch(request);
                        context.go(LalaRoutePaths.mapRoute);
                      },
                      onOpenDetail: (arguments) {
                        final aggregate = arguments.aggregate;
                        final detailId =
                            arguments.signal?.id ??
                            '${aggregate?.placeId ?? 'aggregate'}-'
                                '${aggregate?.weekStart ?? 'unknown'}';
                        context.push(
                          LalaRoutePaths.localSignalDetailFor(detailId),
                          extra: arguments,
                        );
                      },
                    ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: LalaRoutePaths.profile,
                builder: (BuildContext context, GoRouterState state) =>
                    ProfilePage(authController: authController),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: LalaRoutePaths.placeDetail,
        builder: (BuildContext context, GoRouterState state) {
          final placeId = state.pathParameters['placeId'] ?? '';
          final initialPlace = state.extra is LalaPlace
              ? state.extra! as LalaPlace
              : null;
          return PlaceDetailPage(
            placeId: placeId,
            initialPlace: initialPlace,
            backendFactory: backendFactory,
            initialConfig: initialConfig,
            actionController: signalActionController,
            docentExperienceController: docentExperienceController,
          );
        },
      ),
      GoRoute(
        path: LalaRoutePaths.localSignalDetail,
        builder: (BuildContext context, GoRouterState state) =>
            LocalSignalDetailPage(
              signalId: state.pathParameters['signalId'] ?? '',
              language: OnboardingState.language,
              initialConfig: initialConfig,
              arguments: state.extra is LocalSignalDetailArguments
                  ? state.extra! as LocalSignalDetailArguments
                  : null,
              authController: authController,
              onPlaceAction: (request) {
                signalActionController.dispatch(request);
                context.go(LalaRoutePaths.mapRoute);
              },
            ),
      ),
      if (authController != null)
        GoRoute(
          path: LalaRoutePaths.account,
          builder: (BuildContext context, GoRouterState state) =>
              AccountPage(authController: authController),
        ),
      GoRoute(
        path: LalaRoutePaths.travelPreferences,
        builder: (BuildContext context, GoRouterState state) =>
            TravelPreferencesPage(language: OnboardingState.language),
      ),
      GoRoute(
        path: LalaRoutePaths.preferenceSyncConflict,
        builder: (BuildContext context, GoRouterState state) =>
            PreferenceSyncConflictPage(language: OnboardingState.language),
      ),
      GoRoute(
        path: LalaRoutePaths.privacyLocation,
        builder: (BuildContext context, GoRouterState state) =>
            PrivacyLocationPage(authController: authController),
      ),
      GoRoute(
        path: LalaRoutePaths.savedPlaces,
        builder: (BuildContext context, GoRouterState state) => SavedPlacesPage(
          backendFactory: backendFactory,
          initialConfig: initialConfig,
          actionController: signalActionController,
        ),
      ),
      GoRoute(
        path: LalaRoutePaths.pastTrips,
        builder: (BuildContext context, GoRouterState state) =>
            const PastTripsPage(),
      ),
      GoRoute(
        path: LalaRoutePaths.tripSettings,
        builder: (BuildContext context, GoRouterState state) =>
            TripSettingsPage(planDate: state.pathParameters['planDate'] ?? ''),
      ),
      GoRoute(
        path: LalaRoutePaths.visitConfirmation,
        builder: (BuildContext context, GoRouterState state) =>
            VisitConfirmationPage(
              planDate: state.pathParameters['planDate'] ?? '',
              slotPeriod: state.pathParameters['slotPeriod'] ?? '',
              slot: state.extra is LalaPlanSlot
                  ? state.extra! as LalaPlanSlot
                  : null,
            ),
      ),
      GoRoute(
        path: LalaRoutePaths.interventionComparison,
        builder: (BuildContext context, GoRouterState state) =>
            InterventionComparisonPage(
              language: OnboardingState.language,
              arguments: state.extra is InterventionComparisonArguments
                  ? state.extra! as InterventionComparisonArguments
                  : null,
            ),
      ),
      // --- ONMU P3b: 커뮤니티 push 라우트(메인 쉘 외부). context.push 로 진입해
      // 탭 상태를 유지한 채 풀스크린으로 올라간다. ---
      // 이슈 #120 §6.3: 도슨트 전체 플레이어도 동일 push 패턴을 따른다.
      GoRoute(
        path: LalaRoutePaths.docentPlayer,
        builder: (BuildContext context, GoRouterState state) =>
            DocentPlayerPage(controller: docentExperienceController),
      ),
      GoRoute(
        path: LalaRoutePaths.community,
        builder: (BuildContext context, GoRouterState state) =>
            CommunityFeedPage(initialConfig: initialConfig),
      ),
      GoRoute(
        path: LalaRoutePaths.communityPost,
        builder: (BuildContext context, GoRouterState state) {
          final postId = state.pathParameters['id'] ?? '';
          return CommunityPostDetailPage(
            postId: postId,
            initialConfig: initialConfig,
          );
        },
      ),
      GoRoute(
        path: LalaRoutePaths.communityCreate,
        builder: (BuildContext context, GoRouterState state) =>
            CommunityCreatePostPage(initialConfig: initialConfig),
      ),
      // --- ONMU P3c: 커뮤니티 채팅 push 라우트 ---
      GoRoute(
        path: LalaRoutePaths.communityChat,
        builder: (BuildContext context, GoRouterState state) =>
            ChatRoomListPage(initialConfig: initialConfig),
      ),
      GoRoute(
        path: LalaRoutePaths.communityChatRoom,
        builder: (BuildContext context, GoRouterState state) {
          final roomId = state.pathParameters['id'] ?? '';
          return ChatRoomPage(roomId: roomId, initialConfig: initialConfig);
        },
      ),
    ],
  );
}
