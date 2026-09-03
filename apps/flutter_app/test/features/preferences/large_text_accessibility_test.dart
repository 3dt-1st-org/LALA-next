// Round 2 Lane A accessibility gate for the preference surfaces (S-53..S-57)
// and the restaurant communication sheet (S-13): every page must render
// without layout breakage at 200 percent text scale, keep the apply action
// visible, expose section headings, and keep the large-text restaurant
// handoff flow working.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding, SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/preferences/presentation/travel_preferences_page.dart';

/// True when any semantics node in the active tree is marked as a header
/// (Semantics(header: true) sections built by the app).
bool _hasHeaderSemantics(WidgetTester tester) {
  // Why renderViews: in tests the semantics tree hangs off each view's
  // PipelineOwner, not the binding rootPipelineOwner.
  final views = RendererBinding.instance.renderViews;
  var found = false;
  bool visit(SemanticsNode node) {
    if (found) return false;
    if (node.getSemanticsData().flagsCollection.isHeader) {
      found = true;
      return false;
    }
    node.visitChildren(visit);
    return !found;
  }

  for (final view in views) {
    final root = view.owner?.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
    if (found) break;
  }
  return found;
}

const double _viewportWidth = 402;
const double _viewportHeight = 874;
const TextScaler _largeText = TextScaler.linear(2);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpAtScale(
    WidgetTester tester,
    Widget Function() builder,
  ) async {
    tester.view.physicalSize = const Size(_viewportWidth, _viewportHeight);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: _largeText),
        child: MaterialApp(home: Scaffold(body: builder())),
      ),
    );
    await tester.pumpAndSettle();
  }

  final detailPages = <String, Widget Function()>{
    'S-53 style': () =>
        StylePreferencesPage(language: 'ko', initialValue: TravelPreferences()),
    'S-54 food': () =>
        FoodPreferencesPage(language: 'ko', initialValue: TravelPreferences()),
    'S-55 mobility': () => MobilityPreferencesPage(
      language: 'ko',
      initialValue: TravelPreferences(),
    ),
    'S-56 budget': () => BudgetPreferencesPage(
      language: 'ko',
      initialValue: TravelPreferences(),
    ),
    'S-57 docent': () => DocentPreferencesPage(
      language: 'ko',
      initialValue: TravelPreferences(),
    ),
  };

  for (final entry in detailPages.entries) {
    testWidgets('${entry.key} renders whole at 200 percent text', (
      tester,
    ) async {
      await pumpAtScale(tester, entry.value);

      expect(tester.takeException(), isNull);
      // The apply action is pinned in the bottom bar, not the scroll body,
      // so it must stay reachable at any text scale.
      expect(
        find.byKey(const ValueKey('preference-detail-apply')).hitTestable(),
        findsOneWidget,
      );
      final handle = tester.ensureSemantics();
      expect(_hasHeaderSemantics(tester), isTrue);
      handle.dispose();
    });
  }

  testWidgets(
    'S-13 restaurant sheet stays usable at 200 percent text and keeps the '
    'large-text handoff',
    (tester) async {
      tester.view.physicalSize = const Size(_viewportWidth, _viewportHeight);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: _largeText),
          child: MaterialApp(
            home: FoodPreferencesPage(
              language: 'en',
              initialValue: const TravelPreferences(allergens: {Allergen.nuts}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const ValueKey('restaurant-communication-card')),
        find.byType(ListView).first,
        const Offset(0, -120),
      );
      await tester.tap(
        find.byKey(const ValueKey('restaurant-communication-card')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('restaurant-korean-request-card')),
        findsOneWidget,
      );
      // The copy action is pinned to the sheet bottom and must stay tappable.
      expect(
        find.byKey(const ValueKey('copy-korean-restaurant-card')).hitTestable(),
        findsOneWidget,
      );
      // Visitor mirror section is a heading for screen-reader navigation.
      final handle = tester.ensureSemantics();
      expect(_hasHeaderSemantics(tester), isTrue);
      handle.dispose();

      // Large-text staff handoff still opens and stays scrollable. At 200
      // percent text the button starts beyond the lazy cache extent and is
      // only partially on-screen once visible, so mount it with a drag
      // first, then align it fully before tapping.
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('restaurant-large-text-mode')),
        find.byKey(const ValueKey('restaurant-communication-scroll')),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('restaurant-large-text-mode')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('restaurant-large-text-mode')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('restaurant-large-text-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('restaurant-large-text-copy')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('restaurant-large-text-close')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('restaurant-large-text-card')),
        findsNothing,
      );
    },
  );
}
