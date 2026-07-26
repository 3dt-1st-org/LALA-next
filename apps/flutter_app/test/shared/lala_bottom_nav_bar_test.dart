import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/shared/widgets/lala_bottom_nav_bar.dart';

void main() {
  testWidgets(
    'Local Signals is the fourth tab with an exclusive English label',
    (tester) async {
      final router = GoRouter(
        initialLocation: LalaRoutePaths.search,
        routes: <RouteBase>[
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) => Scaffold(
              body: shell,
              bottomNavigationBar: LalaBottomNavBar(
                navigationShell: shell,
                language: 'en',
              ),
            ),
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

      await tester.tap(find.byKey(const ValueKey('nav-local-signals')));
      await tester.pumpAndSettle();
      expect(find.text('local-signals'), findsOneWidget);
    },
  );
}

StatefulShellBranch _branch(String path, String label) => StatefulShellBranch(
  routes: <RouteBase>[
    GoRoute(path: path, builder: (context, state) => Text(label)),
  ],
);
