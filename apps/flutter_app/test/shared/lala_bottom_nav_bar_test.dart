import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/shared/widgets/lala_bottom_nav_bar.dart';

void main() {
  // 하단탭을 직접 구동하기 위한 최소 3-분기 셸.
  GoRouter buildRouter() => GoRouter(
        initialLocation: '/a',
        routes: <RouteBase>[
          StatefulShellRoute.indexedStack(
            builder: (BuildContext context, GoRouterState state,
                StatefulNavigationShell navigationShell) {
              return Scaffold(
                body: const SizedBox.shrink(),
                bottomNavigationBar:
                    LalaBottomNavBar(navigationShell: navigationShell),
              );
            },
            branches: <StatefulShellBranch>[
              StatefulShellBranch(
                routes: <RouteBase>[
                  GoRoute(
                    path: '/a',
                    builder: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: <RouteBase>[
                  GoRoute(
                    path: '/b',
                    builder: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: <RouteBase>[
                  GoRoute(
                    path: '/c',
                    builder: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

  testWidgets('Korean nav labels are 검색/지도/일정 (not 플랜)', (tester) async {
    OnboardingState.reset();
    await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('nav-plan')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('nav-plan')),
        matching: find.text('일정'),
      ),
      findsOneWidget,
    );
    expect(find.text('플랜'), findsNothing);
    expect(find.text('검색'), findsOneWidget);
    expect(find.text('지도'), findsOneWidget);
  });

  testWidgets('English nav labels are Search/Map/Plan', (tester) async {
    OnboardingState.reset();
    OnboardingState.selectLanguage('en');
    await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter()));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('nav-plan')),
        matching: find.text('Plan'),
      ),
      findsOneWidget,
    );
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('일정'), findsNothing);
  });
}
