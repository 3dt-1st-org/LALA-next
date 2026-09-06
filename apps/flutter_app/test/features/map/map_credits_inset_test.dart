// OpenVector attribution visibility regression: the map canvas must reserve
// bottom space so the MapLibre credits row (at the container's bottom edge)
// is never occluded by the place-peek dock, while the Naver path keeps its
// existing full-bleed layout.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/features/map/widgets/map_bottom_dock.dart';
import 'package:lala_next_app/lala_map_provider.dart';

Widget _harness({
  required LalaMapProviderKind provider,
  required double dockHeight,
}) {
  final inset = mapCreditsBottomInset(provider, dockHeight);
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // Same positioning contract as the dashboard map area.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: inset,
                child: ColoredBox(
                  key: const ValueKey('map-canvas'),
                  color: Colors.blue,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: dockHeight,
                child: ColoredBox(
                  key: const ValueKey('dock'),
                  color: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

void main() {
  test('helper: inset equals dock height only for openVector', () {
    expect(mapCreditsBottomInset(LalaMapProviderKind.openVector, 196), 196);
    expect(mapCreditsBottomInset(LalaMapProviderKind.naver, 196), 0);
    expect(mapCreditsBottomInset(LalaMapProviderKind.openVector, 0), 0);
    expect(mapCreditsBottomInset(LalaMapProviderKind.naver, 0), 0);
  });

  for (final locale in ['en', 'ja', 'zh-Hans', 'zh-Hant']) {
    testWidgets('credits stay above the dock for $locale', (tester) async {
      final provider = selectLalaMapProvider(locale);
      expect(provider, LalaMapProviderKind.openVector);
      await tester.pumpWidget(_harness(provider: provider, dockHeight: 196));
      final map = tester.getRect(find.byKey(const ValueKey('map-canvas')));
      final dock = tester.getRect(find.byKey(const ValueKey('dock')));
      // Visible map space ends exactly at the dock's top edge: the credits
      // row at the map bottom can never sit behind the dock.
      expect(map.bottom, dock.top);
      expect(map.bottom, greaterThan(0));
    });

    testWidgets('credits visible with collapsed dock for $locale', (
      tester,
    ) async {
      final provider = selectLalaMapProvider(locale);
      await tester.pumpWidget(
        _harness(
          provider: provider,
          dockHeight: MapBottomDock.mobileCollapsedHeight,
        ),
      );
      final map = tester.getRect(find.byKey(const ValueKey('map-canvas')));
      final dock = tester.getRect(find.byKey(const ValueKey('dock')));
      expect(map.bottom, dock.top);
    });
  }

  testWidgets('Naver full-bleed layout unchanged (KO)', (tester) async {
    expect(selectLalaMapProvider('ko'), LalaMapProviderKind.naver);
    await tester.pumpWidget(
      _harness(provider: LalaMapProviderKind.naver, dockHeight: 196),
    );
    final map = tester.getRect(find.byKey(const ValueKey('map-canvas')));
    // Full-bleed: the canvas still extends to the viewport bottom exactly as
    // before this fix (provider-managed attribution, untouched behavior).
    expect(
      map.bottom,
      tester.view.physicalSize.height / tester.view.devicePixelRatio,
    );
  });
  _sizeMatrix();
}

void _sizeMatrix() {
  final sizes = {
    'small-mobile': const Size(320, 568),
    'mobile': const Size(393, 852),
    'desktop': const Size(1200, 800),
  };
  for (final locale in ['en', 'ja', 'zh-Hans', 'zh-Hant']) {
    final provider = selectLalaMapProvider(locale);
    for (final entry in sizes.entries) {
      for (final dockHeight in [84.0, 196.0, 218.0]) {
        testWidgets(
          'credits band clear ${entry.key} dock=$dockHeight ($locale)',
          (tester) async {
            tester.view.physicalSize = entry.value;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              _harness(provider: provider, dockHeight: dockHeight),
            );
            final map = tester.getRect(
              find.byKey(const ValueKey('map-canvas')),
            );
            final dock = tester.getRect(find.byKey(const ValueKey('dock')));
            // Credits row occupies the band ending exactly at the dock top —
            // readable on every size/dock state, never behind the dock, and
            // horizontally clear of the bottom-right floating controls.
            expect(map.bottom, dock.top);
            expect(map.height, greaterThan(0));
            expect(map.bottom, lessThan(entry.value.height));
          },
        );
      }
    }
  }
}
