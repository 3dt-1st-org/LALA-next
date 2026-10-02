import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_app/features/map/widgets/draggable_place_dock.dart';

void main() {
  testWidgets('returning to the map tab restores the initial dock height', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/map',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => shell,
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/map',
                  builder: (context, state) => Scaffold(
                    body: DraggablePlaceDock(
                      initialHeight: 180,
                      onDismiss: () {},
                      builder: (context, controller, height) => Container(
                        key: const ValueKey('return-panel'),
                        color: Colors.white,
                        child: ListView(
                          controller: controller,
                          children: const [
                            SizedBox(height: 80, child: Text('Handle')),
                            SizedBox(height: 1000, child: Text('Place')),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (context, state) =>
                      const Scaffold(body: Text('Home')),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Handle'), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('return-panel'))).height,
      600,
    );
    router.go('/home');
    await tester.pumpAndSettle();
    router.go('/map');
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('return-panel'))).height,
      180,
    );
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.controller!.offset, 0);
  });

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('place dock expands and dismisses with $kind', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DraggablePlaceDock(
              initialHeight: 180,
              onDismiss: () => dismissed = true,
              builder: (context, controller, height) => Container(
                key: const ValueKey('panel'),
                color: Colors.white,
                child: ListView(
                  controller: controller,
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 80, child: Text('Handle')),
                    Text('Place'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(const ValueKey('panel'))).width, 800);
      await tester.drag(find.text('Handle'), const Offset(0, -500), kind: kind);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('panel'))).height, 600);
      await tester.drag(find.text('Handle'), const Offset(0, 650), kind: kind);
      await tester.pumpAndSettle();
      expect(dismissed, isTrue);
    });
  }
}
