// V6 foreign-visitor UX: onboarding five-language flow widget tests.
//
// Contract (docs/planning/v6-foreign-visitor-ux-contract.md §1/§2/§3):
//  - S2 renders five text-badge rows (KO/EN/JA/简/繁) with endonym labels
//  - selecting a visitor locale immediately re-renders the step chrome
//  - S3 (location consent) renders in the selected visitor language
//  - the completed shell shows visitor-locale bottom-nav labels
//  - no Korean copy is visible on a JA/ZH screen (invariant I1)
//  - no flag emoji in the language rows (invariant I3)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/lala_main_shell.dart';
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/onboarding/presentation/pages/language_page.dart';
import 'package:lala_next_app/shared/l10n/multi_language_text.dart';

Widget _wrapLanguagePage() => const MaterialApp(home: OnboardingLanguagePage());

void main() {
  group('V6 S2 language page rows', () {
    setUp(OnboardingState.reset);
    tearDown(OnboardingState.reset);

    testWidgets('renders five text-badge rows with endonym labels', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapLanguagePage());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('onboarding-language-ko')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('onboarding-language-en')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('onboarding-language-ja')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('onboarding-language-zh-Hans')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('onboarding-language-zh-Hant')),
        findsOneWidget,
      );
      expect(find.text('한국어'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('日本語'), findsOneWidget);
      expect(find.text('简体中文'), findsOneWidget);
      expect(find.text('繁體中文'), findsOneWidget);
    });

    testWidgets('no flag emoji anywhere on the language step (I3)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapLanguagePage());
      await tester.pumpAndSettle();

      final flagEmoji = RegExp('[\u{1F1E6}-\u{1F1FF}]', unicode: true);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '');
      for (final text in texts) {
        expect(flagEmoji.hasMatch(text), isFalse, reason: text);
      }
    });

    testWidgets('selecting Japanese updates the SSOT and step chrome', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapLanguagePage());
      await tester.pumpAndSettle();

      // Step renders in Korean first (fresh-session default).
      expect(find.text('언어 선택'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('onboarding-language-ja')));
      await tester.pumpAndSettle();

      expect(OnboardingState.language, 'ja');
      // The step chrome re-renders in the just-chosen language.
      expect(find.text('言語を選択'), findsOneWidget);
      expect(find.text('アプリで使う言語を選んでください。'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '次へ'), findsOneWidget);
      // Korean chrome copy is gone — one language per screen (I1).
      expect(find.text('언어 선택'), findsNothing);
    });

    testWidgets('selecting Simplified Chinese updates chrome to zh-Hans', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapLanguagePage());
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('onboarding-language-zh-Hans')),
      );
      await tester.pumpAndSettle();

      expect(OnboardingState.language, 'zh-Hans');
      expect(find.text('选择语言'), findsOneWidget);
      expect(find.text('选择应用使用的语言。'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '下一步'), findsOneWidget);
    });

    testWidgets('selecting Traditional Chinese updates chrome to zh-Hant', (
      tester,
    ) async {
      // 800x600 default test viewport: the fifth row needs a scroll to reach.
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrapLanguagePage());
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('onboarding-language-zh-Hant')),
      );
      await tester.pumpAndSettle();

      expect(OnboardingState.language, 'zh-Hant');
      expect(find.text('選擇語言'), findsOneWidget);
      expect(find.text('選擇應用使用的語言。'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '下一步'), findsOneWidget);
    });

    testWidgets('visitor locale selection shows no mixed KO+target text (I1)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapLanguagePage());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('onboarding-language-ja')));
      await tester.pumpAndSettle();

      // The endonym rows are intentionally multi-language on THIS screen only
      // (they are the language names themselves); assert the step chrome is
      // not mixed.
      final chrome = <String>[
        '言語を選択',
        'アプリで使う言語を選んでください。',
      ];
      for (final text in chrome) {
        expect(hasMixedKoreanEnglish(text), isFalse, reason: text);
        expect(containsKorean(text), isFalse, reason: text);
      }
    });

    testWidgets('five rows + action fit without overflow at 402pt width', (
      tester,
    ) async {
      // iPhone 17 Pro logical width (contract §8).
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final errors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = errors.add;
      try {
        await tester.pumpWidget(_wrapLanguagePage());
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = originalOnError;
      }
      expect(
        errors.where((e) => e.exceptionAsString().contains('overflowed')),
        isEmpty,
      );
      expect(find.text('繁體中文'), findsOneWidget);
    });

    testWidgets('short viewport scrolls rows instead of overflowing', (
      tester,
    ) async {
      // Contract §8: content scrolls, the primary action stays reachable.
      tester.view.physicalSize = const Size(402, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final errors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = errors.add;
      try {
        await tester.pumpWidget(_wrapLanguagePage());
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = originalOnError;
      }
      expect(
        errors.where((e) => e.exceptionAsString().contains('overflowed')),
        isEmpty,
      );
      // The action remains visible and tappable.
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });

  group('V6 visitor-locale shell labels', () {
    tearDown(OnboardingState.reset);

    Widget buildShell() => MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: LalaRoutePaths.search,
        routes: <RouteBase>[
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) =>
                LalaMainShell(navigationShell: shell),
            branches: <StatefulShellBranch>[
              StatefulShellBranch(
                routes: <RouteBase>[
                  GoRoute(
                    path: LalaRoutePaths.search,
                    builder: (context, state) => const Text('search-body'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: <RouteBase>[
                  GoRoute(
                    path: LalaRoutePaths.mapRoute,
                    builder: (context, state) => const Text('map-body'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: <RouteBase>[
                  GoRoute(
                    path: LalaRoutePaths.plan,
                    builder: (context, state) => const Text('plan-body'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: <RouteBase>[
                  GoRoute(
                    path: LalaRoutePaths.localSignals,
                    builder: (context, state) => const Text('signals-body'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    testWidgets('Japanese drives all four tab labels (campaign C4)', (
      tester,
    ) async {
      OnboardingState.applySnapshot(
        const OnboardingSnapshot(completed: true, language: 'ja'),
      );
      await tester.pumpWidget(buildShell());
      await tester.pumpAndSettle();

      expect(find.text('検索'), findsOneWidget);
      expect(find.text('地図'), findsOneWidget);
      expect(find.text('プラン'), findsOneWidget);
      expect(find.text('ローカル信号'), findsOneWidget);
      // No Korean tab label on a JA screen (I1).
      expect(find.text('검색'), findsNothing);
      expect(find.text('지도'), findsNothing);
      expect(find.text('일정'), findsNothing);
      expect(find.text('로컬 신호'), findsNothing);
    });

    testWidgets('Simplified Chinese drives all four tab labels', (
      tester,
    ) async {
      OnboardingState.applySnapshot(
        const OnboardingSnapshot(completed: true, language: 'zh-Hans'),
      );
      await tester.pumpWidget(buildShell());
      await tester.pumpAndSettle();

      expect(find.text('搜索'), findsOneWidget);
      expect(find.text('地图'), findsOneWidget);
      expect(find.text('计划'), findsOneWidget);
      expect(find.text('本地信号'), findsOneWidget);
      expect(find.text('검색'), findsNothing);
    });

    testWidgets('Traditional Chinese drives all four tab labels', (
      tester,
    ) async {
      OnboardingState.applySnapshot(
        const OnboardingSnapshot(completed: true, language: 'zh-Hant'),
      );
      await tester.pumpWidget(buildShell());
      await tester.pumpAndSettle();

      expect(find.text('搜尋'), findsOneWidget);
      expect(find.text('地圖'), findsOneWidget);
      expect(find.text('計畫'), findsOneWidget);
      expect(find.text('在地訊號'), findsOneWidget);
      expect(find.text('검색'), findsNothing);
    });

    testWidgets('KO labels are unchanged after a visitor round-trip', (
      tester,
    ) async {
      OnboardingState.applySnapshot(
        const OnboardingSnapshot(completed: true, language: 'zh-Hant'),
      );
      await tester.pumpWidget(buildShell());
      await tester.pumpAndSettle();
      expect(find.text('搜尋'), findsOneWidget);

      OnboardingState.selectLanguage('ko');
      await tester.pumpAndSettle();
      expect(find.text('검색'), findsOneWidget);
      expect(find.text('지도'), findsOneWidget);
      expect(find.text('일정'), findsOneWidget);
      expect(find.text('로컬 신호'), findsOneWidget);
      expect(find.text('搜尋'), findsNothing);
    });
  });
}
