// Round 2 Lane A gate: preference pages (S-53..S-57) must not leak Korean unit
// copy onto visitor-locale screens. The minute suffix ('분') was the one
// remaining Hangul leak found in the visitor-access audit — it rendered inside
// ja/zh chips and summaries.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/preferences/presentation/travel_preferences_page.dart';

const _visitorLocales = <String>['ja', 'zh-Hans', 'zh-Hant'];

final RegExp _hangul = RegExp(
  '[\u{AC00}-\u{D7AF}\u{1100}-\u{11FF}]',
  unicode: true,
);

List<String> _visibleTexts(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
      .where((text) => text.isNotEmpty)
      .toList(growable: false);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final locale in _visitorLocales) {
    group('mobility preferences at $locale', () {
      testWidgets('minute chips use the locale unit, not Korean 분', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(402, 874);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: MobilityPreferencesPage(
              language: locale,
              initialValue: const TravelPreferences(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final offenders = _visibleTexts(
          tester,
        ).where((text) => _hangul.hasMatch(text)).toList(growable: false);
        expect(
          offenders,
          isEmpty,
          reason: 'Korean unit copy leaked onto S-55 at "$locale": $offenders',
        );

        final minuteUnit = switch (locale) {
          'ja' => '分',
          'zh-Hans' => '分钟',
          _ => '分鐘',
        };
        expect(find.text('30$minuteUnit'), findsOneWidget);
        expect(find.textContaining('분'), findsNothing);
      });
    });
  }
}
