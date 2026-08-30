// 온보딩 첫 질문(S1) 기능 계약 회귀(lala-functional-ui-contract 02-screen-contracts S1).
// - Next 는 선택 전 disabled, 행 탭만으로 자동 이동 없음, 선택 후 enabled.
// - 언어 메뉴는 KO/EN/JA/zh-Hans/zh-Hant 다섯 텍스트 배지/고유명만 노출(국기 없음).
// - 긴 EN/JA/zh 라벨이 393x852(모바일 웹 기준)에서 오버플로/클리핑 없이 표시.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/onboarding/presentation/pages/language_page.dart';
import 'package:lala_next_app/features/onboarding/presentation/pages/start_page.dart';

void main() {
  group('S1 first question interaction contract', () {
    setUp(OnboardingState.reset);
    tearDown(OnboardingState.reset);

    Widget buildRouter() {
      final router = GoRouter(
        initialLocation: LalaRoutePaths.onboardingStart,
        routes: <RouteBase>[
          GoRoute(
            path: LalaRoutePaths.onboardingStart,
            builder: (context, state) => const OnboardingStartPage(),
          ),
          GoRoute(
            path: LalaRoutePaths.onboardingLanguage,
            builder: (context, state) => const OnboardingLanguagePage(),
          ),
        ],
      );
      addTearDown(router.dispose);
      return MaterialApp.router(routerConfig: router);
    }

    testWidgets(
      'Next is disabled before a choice and rows never auto-navigate',
      (tester) async {
        await tester.pumpWidget(buildRouter());
        await tester.pumpAndSettle();

        // 진행 표시 + 워드마크 헤더가 첫 질문에 함께 있다.
        expect(find.text('1 / 3'), findsOneWidget);

        // 선택 전 Next 는 비활성.
        final disabledNext = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '다음'),
        );
        expect(disabledNext.onPressed, isNull);

        // 행 탭은 선택만 갱신 — 자동 이동 금지(S1 계약).
        await tester.tap(
          find.byKey(const ValueKey('onboarding-travel-domestic')),
        );
        await tester.pumpAndSettle();

        expect(find.text('어떤 여행을\n계획 중인가요?'), findsOneWidget);
        expect(find.text('언어 선택'), findsNothing);

        // 선택 후 Next 는 활성화되고 눌러야만 다음 단계로 이동한다.
        final enabledNext = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '다음'),
        );
        expect(enabledNext.onPressed, isNotNull);

        await tester.tap(find.widgetWithText(FilledButton, '다음'));
        await tester.pumpAndSettle();
        expect(find.text('언어 선택'), findsOneWidget);
      },
    );

    testWidgets('quick menu exposes exactly the five supported locales', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: OnboardingStartPage()));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('onboarding-quick-language-menu')),
      );
      await tester.pumpAndSettle();

      const expectedCodes = <String>['ko', 'en', 'ja', 'zh-Hans', 'zh-Hant'];
      for (final code in expectedCodes) {
        expect(
          find.byKey(ValueKey('onboarding-quick-language-$code')),
          findsOneWidget,
        );
      }
      // 메뉴 항목 수 = 5(그 외 항목 없음).
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is PopupMenuItem<String> &&
              w.key != null &&
              (w.key as ValueKey<String>).value.startsWith(
                'onboarding-quick-language-',
              ),
        ),
        findsNWidgets(5),
      );

      // 고유명 라벨 노출(국기 emoji 아님).
      expect(find.text('한국어'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('日本語'), findsOneWidget);
      expect(find.text('简体中文'), findsOneWidget);
      expect(find.text('繁體中文'), findsOneWidget);
      final flagEmoji = RegExp('[\u{1F1E6}-\u{1F1FF}]', unicode: true);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '');
      for (final text in texts) {
        expect(flagEmoji.hasMatch(text), isFalse, reason: text);
      }
    });

    testWidgets('English rows use the Visiting Korea foreign label', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: OnboardingStartPage()));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('onboarding-quick-language-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('onboarding-quick-language-en')),
      );
      await tester.pumpAndSettle();

      // 계약 문구: 해외 방문 행의 EN 라벨은 Visiting Korea.
      expect(find.text('Domestic trip'), findsOneWidget);
      expect(find.text('Visiting Korea'), findsOneWidget);
      expect(find.text('Overseas trip'), findsNothing);
    });

    testWidgets('selected row shows outline plus a distinct selected icon', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: OnboardingStartPage()));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('onboarding-travel-domestic')),
      );
      await tester.pumpAndSettle();

      // 선택 행에는 check 아이콘이, 미선택 행에는 chevron 이 있다(색상 외 신호).
      List<IconData?> rowIcons(String rowKey) {
        return tester
            .widgetList<Icon>(
              find.descendant(
                of: find.byKey(ValueKey(rowKey)),
                matching: find.byType(Icon),
              ),
            )
            .map((icon) => icon.icon)
            .toList();
      }

      expect(
        rowIcons('onboarding-travel-domestic'),
        contains(Icons.check_circle_rounded),
      );
      expect(
        rowIcons('onboarding-travel-overseas'),
        contains(Icons.radio_button_unchecked),
      );
      expect(
        rowIcons('onboarding-travel-overseas'),
        isNot(contains(Icons.check_circle_rounded)),
      );
      // 행이 내비게이션을 암시하는 chevron 표시는 선택 여부와 무관하게 없다.
      expect(
        rowIcons('onboarding-travel-domestic'),
        isNot(contains(Icons.chevron_right_rounded)),
      );
      expect(
        rowIcons('onboarding-travel-overseas'),
        isNot(contains(Icons.chevron_right_rounded)),
      );
    });
  });

  group('S1 long-locale layout at 393x852', () {
    setUp(OnboardingState.reset);
    tearDown(OnboardingState.reset);

    // 각 언어 선택 시 첫 질문 화면 전체(헤딩 + 주 액션)가 그 언어로 바뀌는지 확인.
    const headings = <String, String>{
      'ko': '어떤 여행을\n계획 중인가요?',
      'en': 'What kind of trip\nare you planning?',
      'ja': 'どんな旅を\n計画していますか？',
      'zh-Hans': '您正在计划\n什么样的旅行？',
      'zh-Hant': '您正在計劃\n什麼樣的旅行？',
    };
    const nextLabels = <String, String>{
      'ko': '다음',
      'en': 'Next',
      'ja': '次へ',
      'zh-Hans': '下一步',
      'zh-Hant': '下一步',
    };

    for (final entry in headings.entries) {
      testWidgets('${entry.key} labels fit 393x852 without overflow', (
        tester,
      ) async {
        // 모바일 웹 기준 viewport(04-responsive §1). iPhone 17 Pro 실측은
        // 402x874 를 쓰는 기존 suite 가 담당한다.
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final errors = <FlutterErrorDetails>[];
        final originalOnError = FlutterError.onError;
        FlutterError.onError = errors.add;
        try {
          await tester.pumpWidget(
            const MaterialApp(home: OnboardingStartPage()),
          );
          await tester.pumpAndSettle();

          await tester.tap(
            find.byKey(const ValueKey('onboarding-quick-language-menu')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(ValueKey('onboarding-quick-language-${entry.key}')),
          );
          await tester.pumpAndSettle();
        } finally {
          FlutterError.onError = originalOnError;
        }

        expect(
          errors.where((e) => e.exceptionAsString().contains('overflowed')),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        // 전체 화면이 선택 언어 하나로 렌더되었다.
        expect(find.text(entry.value), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, nextLabels[entry.key]!),
          findsOneWidget,
        );
        // 헤더 언어 컨트롤은 최소 44dp 터치 타겟을 유지한다.
        expect(
          tester
              .getSize(
                find.byKey(const ValueKey('onboarding-quick-language-menu')),
              )
              .height,
          greaterThanOrEqualTo(44),
        );
      });
    }
  });
}
