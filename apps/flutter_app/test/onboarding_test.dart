import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/onboarding_screen.dart';
import 'package:lala_next_app/manual_location_options.dart';

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> next(WidgetTester tester) async {
  await tapVisible(tester, find.byKey(const ValueKey('onboarding-primary')));
  if (find.byKey(const ValueKey('location-allow')).evaluate().isNotEmpty) {
    await tapVisible(tester, find.byKey(const ValueKey('location-allow')));
  }
}

void main() {
  testWidgets('Folding and unfolding preserves onboarding selection', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(344, 882);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    OnboardingResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          onRequestLocation: () async => OnboardingLocationStatus.granted,
          onSelectDestination: (_) async => manualLocationOptions.first,
          onComplete: (value) => result = value,
        ),
      ),
    );
    await next(tester);
    await tapVisible(tester, find.byKey(const ValueKey('country-JP')));
    await next(tester);
    for (final size in [
      const Size(673, 841),
      const Size(1000, 700),
      const Size(344, 882),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(find.text('どんな旅が好きですか？'), findsOneWidget);
      final button = tester.getRect(
        find.byKey(const ValueKey('onboarding-primary')),
      );
      expect(button.bottom, lessThan(size.height));
      expect(button.top, greaterThan(0));
      expect(tester.takeException(), isNull);
    }
    await tapVisible(tester, find.byKey(const ValueKey('onboarding-skip')));
    await tapVisible(tester, find.byKey(const ValueKey('onboarding-skip')));
    await tapVisible(tester, find.byKey(const ValueKey('onboarding-skip')));
    expect(result!.country, 'JP');
    expect(result!.language, 'ja');
  });

  for (final size in [
    const Size(390, 844),
    const Size(440, 956),
    const Size(344, 882),
    const Size(673, 841),
    const Size(841, 673),
    const Size(320, 568),
    const Size(844, 390),
    const Size(1000, 600),
    const Size(1024, 1366),
    const Size(1366, 1024),
    const Size(1440, 900),
    const Size(1920, 1080),
  ]) {
    testWidgets('All five steps fit and complete at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      OnboardingResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            onRequestLocation: () async => OnboardingLocationStatus.granted,
            onSelectDestination: (_) async => manualLocationOptions.first,
            onComplete: (value) => result = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('LALA'), findsOneWidget);
      expect(find.byIcon(Icons.travel_explore_rounded), findsNothing);
      final copy = tester.getRect(
        find.byKey(const ValueKey('onboarding-welcome-copy')),
      );
      final art = tester.getRect(find.byKey(const ValueKey('onboarding-art')));
      if (size.width >= 900) {
        expect(copy.overlaps(art), isFalse);
        expect(copy.left, greaterThanOrEqualTo(art.right));
        expect(
          find.byKey(const ValueKey('onboarding-side-fade')),
          findsOneWidget,
        );
        expect(art.left, 0);
        expect(art.width, greaterThan(size.width / 2));
        expect(
          tester.getSize(find.byKey(const ValueKey('onboarding-wide'))).width,
          size.width,
        );
      } else {
        expect(copy.overlaps(art), isTrue);
        expect(
          find.byKey(const ValueKey('onboarding-side-fade')),
          findsNothing,
        );
        expect(copy.top, greaterThanOrEqualTo(art.top));
        expect(copy.bottom, lessThanOrEqualTo(art.bottom));
      }
      final footer = tester.getRect(
        find.byKey(const ValueKey('onboarding-welcome-footer')),
      );
      if (size.width >= 900) {
        final footerViewport = tester.getRect(
          find.byKey(const ValueKey('onboarding-welcome-footer-scroll')),
        );
        expect(footerViewport.bottom, closeTo(size.height, 1));
        if (footer.height + 44 <= size.height * .65) {
          expect(footer.bottom, closeTo(size.height - 24, 1));
        }
      } else {
        expect(footer.top, closeTo(art.bottom + 50, 1));
        expect(
          find.byKey(const ValueKey('onboarding-welcome-footer-scroll')),
          findsNothing,
        );
      }
      final primaryBeforeScroll = tester.getRect(
        find.byKey(const ValueKey('onboarding-primary')),
      );
      await tester.drag(
        find.byKey(const ValueKey('onboarding-scroll')),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();
      final primaryAfterScroll = tester.getRect(
        find.byKey(const ValueKey('onboarding-primary')),
      );
      if (size.width >= 900) {
        expect(primaryAfterScroll, primaryBeforeScroll);
      } else if (footer.bottom + 24 > size.height) {
        expect(primaryAfterScroll.top, lessThan(primaryBeforeScroll.top));
      }
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('onboarding-bottom-fade')),
        size.width >= 900 ? findsNothing : findsOneWidget,
      );
      expect(tester.getSize(find.byType(Image)).width, greaterThan(0));
      Rect? fixedToolbar;
      Rect? fixedPrimary;
      for (var step = 0; step < 4; step++) {
        await next(tester);
        expect(find.byKey(const ValueKey('onboarding-art')), findsNothing);
        final toolbar = tester.getRect(
          find.byKey(const ValueKey('onboarding-toolbar')),
        );
        final skip = tester.getRect(
          find.byKey(const ValueKey('onboarding-skip')),
        );
        expect(skip.right, closeTo(toolbar.right, .01));
        final stepLabel = tester.getRect(
          find.byKey(const ValueKey('onboarding-step-label')),
        );
        expect(stepLabel.center.dx, closeTo(toolbar.center.dx, .01));
        expect(
          stepLabel.overlaps(skip),
          isFalse,
          reason: 'step=$step label=$stepLabel skip=$skip toolbar=$toolbar',
        );
        final primary = tester.getRect(
          find.byKey(const ValueKey('onboarding-primary')),
        );
        fixedPrimary ??= primary;
        expect(primary.top, closeTo(fixedPrimary.top, .01));
        expect(primary.bottom, lessThan(size.height));
        if (size.width >= 900 && size.height > size.width) {
          expect(primary.bottom, lessThan(820));
        }
        if (size.width >= 900) {
          fixedToolbar ??= toolbar;
          expect(toolbar, fixedToolbar);
        }
        await tester.drag(
          find.byKey(const ValueKey('onboarding-scroll')),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('onboarding-primary'))),
          primary,
        );
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Listen as you explore'), findsOneWidget);
      await next(tester);
      expect(result, isNotNull);
      expect(result!.isGuest, isTrue);
      expect(result!.requestLocation, isTrue);
      expect(result!.country, 'US');
      expect(result!.travelMode, 'explore_now');
    });
  }

  for (final country in [
    ('KR', 'ko'),
    ('US', 'en'),
    ('JP', 'ja'),
    ('CN', 'zh-CN'),
    ('TW', 'zh-TW'),
    ('HK', 'zh-TW'),
    ('OTHER', 'en'),
  ]) {
    testWidgets('Country ${country.$1} automatically selects ${country.$2}', (
      tester,
    ) async {
      OnboardingResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            onRequestLocation: () async => OnboardingLocationStatus.granted,
            onSelectDestination: (_) async => manualLocationOptions.first,
            initialLanguage: 'ko',
            onComplete: (value) => result = value,
          ),
        ),
      );
      await next(tester);
      expect(find.byKey(const ValueKey('country-JP')), findsOneWidget);
      expect(find.byKey(const ValueKey('country-CN')), findsOneWidget);
      expect(find.byKey(const ValueKey('country-TW')), findsOneWidget);
      expect(find.text('Language (언어)'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'English'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '한국어'), findsNothing);
      await tapVisible(tester, find.byKey(ValueKey('country-${country.$1}')));
      await next(tester);
      final headings = {
        'ko': '어떤 여행을 좋아하세요?',
        'en': 'What do you love about travel?',
        'ja': 'どんな旅が好きですか？',
        'zh-CN': '你喜欢怎样的旅行？',
        'zh-TW': '你喜歡怎樣的旅行？',
      };
      expect(find.text(headings[country.$2]!), findsOneWidget);
      for (final heading in headings.entries) {
        if (heading.key != country.$2) {
          expect(find.text(heading.value), findsNothing);
        }
      }
      await next(tester);
      expect(
        find.text('Explore nearby'),
        country.$2 == 'en' ? findsOneWidget : findsNothing,
      );
      await next(tester);
      expect(
        find.byKey(const ValueKey('onboarding-docent-illustration')),
        findsOneWidget,
      );
      expect(find.text('Playback Speed (음성 속도)'), findsNothing);
      expect(
        find.text('Playback speed'),
        country.$2 == 'en' ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.byKey(const ValueKey('onboarding-skip')));
      expect(result!.country, country.$1);
      expect(result!.language, country.$2);
      expect(result!.contentLanguage, country.$2 == 'ko' ? 'ko' : 'en');
    });
  }

  testWidgets(
    'Selections survive back navigation and are passed on completion',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      OnboardingResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            onRequestLocation: () async => OnboardingLocationStatus.granted,
            onSelectDestination: (_) async => manualLocationOptions.first,
            onComplete: (value) => result = value,
          ),
        ),
      );
      await next(tester);
      await tapVisible(tester, find.byKey(const ValueKey('country-KR')));
      expect(find.text('다음'), findsOneWidget);
      await next(tester);
      await tapVisible(tester, find.byKey(const ValueKey('style-food')));
      await tapVisible(tester, find.byKey(const ValueKey('style-nature')));
      await tapVisible(tester, find.byKey(const ValueKey('style-kculture')));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await next(tester);
      await tapVisible(tester, find.byKey(const ValueKey('mode-plan_trip')));
      await tapVisible(tester, find.byKey(const ValueKey('onboarding-back')));
      await next(tester);
      await next(tester);

      await tapVisible(tester, find.text('빠르게\n1.2x'));
      await tapVisible(tester, find.text('나중에 할게요'));
      expect(result!.country, 'KR');
      expect(result!.language, 'ko');
      expect(result!.travelStyles, ['history', 'food', 'nature']);
      expect(result!.travelMode, 'plan_trip');
      expect(result!.autoDocent, isFalse);
      expect(result!.playbackSpeed, 1.2);
      expect(result!.requestLocation, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Large text remains scrollable and final skip preserves permission',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      OnboardingResult? result;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: OnboardingScreen(
            onRequestLocation: () async => OnboardingLocationStatus.granted,
            onSelectDestination: (_) async => manualLocationOptions.first,
            initialLanguage: 'ko',
            onComplete: (value) => result = value,
          ),
        ),
      );
      for (var step = 0; step < 4; step++) {
        await next(tester);
        expect(tester.takeException(), isNull);
      }
      await tapVisible(tester, find.byKey(const ValueKey('onboarding-skip')));
      expect(result!.requestLocation, isTrue);
      expect(result!.language, 'ko');
    },
  );
}
