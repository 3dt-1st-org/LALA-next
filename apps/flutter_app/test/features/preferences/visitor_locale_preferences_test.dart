// Round 2 Lane A gate: preference pages (S-53..S-57) must not leak Korean unit
// copy onto visitor-locale screens. The minute suffix ('분') was the one
// remaining Hangul leak found in the visitor-access audit — it rendered inside
// ja/zh chips and summaries.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/preferences/presentation/restaurant_communication_sheet.dart';
import 'package:lala_next_app/features/preferences/presentation/travel_preferences_page.dart';
import 'package:lala_next_app/shared/speech/system_speech.dart';

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

  for (final locale in _visitorLocales) {
    group('food preferences at $locale', () {
      testWidgets('spice and order request labels are localized, not Korean', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(402, 874);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: FoodPreferencesPage(
              language: locale,
              initialValue: const TravelPreferences(
                spiceLevel: SpicePreference.mild,
                orderRequests: {RestaurantOrderRequest.quietTable},
              ),
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
          reason:
              'Korean copy leaked onto the food page at "$locale": $offenders',
        );

        // The bounded labels render in the visitor locale, selected or not.
        for (final value in SpicePreference.values) {
          expect(
            find.byKey(ValueKey('spice-level-${value.name}')),
            findsOneWidget,
          );
        }
        for (final value in RestaurantOrderRequest.values) {
          expect(
            find.byKey(ValueKey('enum-RestaurantOrderRequest.${value.name}')),
            findsOneWidget,
          );
        }
      });
    });
  }

  testWidgets('all five locales render the bounded restaurant card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const preferences = TravelPreferences(
      spiceLevel: SpicePreference.spicy,
      orderRequests: {RestaurantOrderRequest.staffRecommendation},
      allergens: {Allergen.nuts},
    );

    for (final locale in ['ko', 'en', 'ja', 'zh-Hans', 'zh-Hant']) {
      await tester.pumpWidget(
        MaterialApp(
          home: RestaurantCommunicationSheet(
            language: locale,
            preferences: preferences,
            speech: _NoopSpeech(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Korean staff card is intentionally Korean in every locale...
      expect(find.textContaining('맵기: 매운 음식을 잘 먹습니다.'), findsOneWidget);
      // ...and the visitor mirror renders translated copy.
      final visitorCard = find.byKey(
        const ValueKey('restaurant-visitor-request-card'),
      );
      if (locale == 'ko') {
        expect(visitorCard, findsNothing);
      } else {
        expect(visitorCard, findsOneWidget);
        final mirror = tester
            .widgetList<SelectableText>(
              find.descendant(
                of: visitorCard,
                matching: find.byType(SelectableText),
              ),
            )
            .first
            .data!;
        expect(_hangul.hasMatch(mirror), isFalse, reason: mirror);
        final spiceMirror = switch (locale) {
          'en' => 'Spice level: I enjoy spicy food.',
          'ja' => '辛さ：辛いものが好きです。',
          'zh-Hans' => '辣度：我喜欢吃辣。',
          _ => '辣度：我喜歡吃辣。',
        };
        expect(mirror, contains(spiceMirror));
      }
      expect(tester.takeException(), isNull);
    }
  });
}

class _NoopSpeech implements SystemSpeech {
  @override
  Future<bool> isKoreanAvailable() async => false;

  @override
  Future<SystemSpeechOutcome> speakKorean(String text) async =>
      SystemSpeechOutcome.unavailable;

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}

  @override
  void setOnUtteranceFinished(void Function() onFinished) {}
}
