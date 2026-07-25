// Wave-1 location/weather: focused tests for the permanently-denied recovery
// surface and the platform-safe "open settings" hand-off.
//
// - Native-capable: the real "Open settings" action is offered and wired.
// - Web/unsupported: the action is omitted (no fake action), the honest
//   browser-specific copy is shown, and the manual-region escape remains.
// - ko/en copy stays exclusive.
// - The hand-off abstraction reports a stable capability and never throws when
//   the platform can't fulfill it (graceful false).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/core/location/app_settings_opener.dart';
import 'package:lala_next_app/features/location/widgets/permanently_denied_recovery.dart';

void main() {
  group('app_settings_opener abstraction', () {
    test('canOpenAppSettings is a stable bool', () {
      // flutter test runs on the Dart VM (io), so the native impl is loaded and
      // this is true on the host; on web the stub reports false. Either way a
      // stable bool the UI can branch on.
      expect(canOpenAppSettings, isA<bool>());
    });

    test('openAppSettings never throws when the plugin is unavailable', () async {
      // No native plugin is wired under flutter test, so the native hand-off hits
      // a missing channel and must degrade to `false` rather than throwing or
      // pretending success.
      expect(await openAppSettings(), isFalse);
    });
  });

  group('PermanentlyDeniedRecovery', () {
    testWidgets(
      'native-capable: offers and wires a real Open settings action plus manual escape',
      (tester) async {
        var opened = 0;
        var chose = 0;
        var retried = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PermanentlyDeniedRecovery(
                language: 'en',
                canOpenSettings: true,
                onOpenSettings: () => opened++,
                onRetry: () => retried++,
                onChooseArea: () => chose++,
              ),
            ),
          ),
        );

        expect(
          find.byKey(const ValueKey('permanently-denied-open-settings')),
          findsOneWidget,
        );
        expect(find.text('Open settings'), findsOneWidget);
        expect(find.text('Choose area'), findsOneWidget);
        // Honest system-settings explanation, not the browser-only fallback.
        expect(find.textContaining('system settings'), findsWidgets);

        await tester.tap(
          find.byKey(const ValueKey('permanently-denied-open-settings')),
        );
        await tester.tap(
          find.byKey(const ValueKey('permanently-denied-choose-area')),
        );
        await tester.tap(
          find.byKey(const ValueKey('permanently-denied-retry')),
        );
        expect(opened, 1);
        expect(chose, 1);
        expect(retried, 1);
      },
    );

    testWidgets('native-capable Korean copy is exclusive', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PermanentlyDeniedRecovery(
              language: 'ko',
              canOpenSettings: true,
              onOpenSettings: () {},
              onChooseArea: () {},
            ),
          ),
        ),
      );
      expect(find.text('설정 열기'), findsOneWidget);
      expect(find.text('지역 직접 선택'), findsOneWidget);
      // English copy must not leak into the Korean surface.
      expect(find.text('Open settings'), findsNothing);
      expect(find.text('Choose area'), findsNothing);
    });

    testWidgets(
      'web/unsupported: hides Open settings and keeps an honest manual escape',
      (tester) async {
        var chose = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PermanentlyDeniedRecovery(
                language: 'en',
                canOpenSettings: false,
                onChooseArea: () => chose++,
              ),
            ),
          ),
        );

        // No fake "Open settings" action on a platform that can't fulfill it.
        expect(
          find.byKey(const ValueKey('permanently-denied-open-settings')),
          findsNothing,
        );
        expect(find.text('Open settings'), findsNothing);
        // Honest browser-specific explanation + the always-available manual path.
        expect(find.textContaining('browser'), findsWidgets);
        expect(find.text('Choose area'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('permanently-denied-choose-area')),
        );
        expect(chose, 1);
      },
    );

    testWidgets('web/unsupported Korean honest copy stays exclusive', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PermanentlyDeniedRecovery(
              language: 'ko',
              canOpenSettings: false,
              onChooseArea: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining('브라우저'), findsWidgets);
      expect(find.text('지역 직접 선택'), findsOneWidget);
      expect(find.text('Choose area'), findsNothing);
    });
  });
}
