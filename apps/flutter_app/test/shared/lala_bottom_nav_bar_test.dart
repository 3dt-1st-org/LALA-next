import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/lala_main_shell.dart';
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';

void main() {
  setUp(() {
    OnboardingState.applySnapshot(
      const OnboardingSnapshot(completed: true, language: 'en'),
    );
  });
  tearDown(OnboardingState.reset);

  testWidgets('restored English drives reactive shell labels without Home', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: LalaRoutePaths.search,
      routes: <RouteBase>[
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) =>
              LalaMainShell(navigationShell: shell),
          branches: <StatefulShellBranch>[
            _branch(LalaRoutePaths.search, 'search'),
            _branch(LalaRoutePaths.mapRoute, 'map'),
            _branch(LalaRoutePaths.plan, 'plan'),
            _branch(LalaRoutePaths.localSignals, 'local-signals'),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('nav-local-signals')), findsOneWidget);
    expect(find.text('Local Signals'), findsOneWidget);
    expect(find.text('로컬 신호'), findsNothing);

    OnboardingState.selectLanguage('ko');
    await tester.pump();
    expect(find.text('검색'), findsOneWidget);
    expect(find.text('지도'), findsOneWidget);
    expect(find.text('일정'), findsOneWidget);
    expect(find.text('로컬 신호'), findsOneWidget);
    expect(find.text('Search'), findsNothing);

    OnboardingState.selectLanguage('en');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('nav-local-signals')));
    await tester.pumpAndSettle();
    expect(find.text('local-signals'), findsOneWidget);
  });
}

StatefulShellBranch _branch(String path, String label) => StatefulShellBranch(
  routes: <RouteBase>[
    GoRoute(path: path, builder: (context, state) => Text(label)),
  ],
);
