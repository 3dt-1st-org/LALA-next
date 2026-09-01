import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/preferences/presentation/travel_preferences_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('edits an interest and saves it on this device', (tester) async {
    final store = TravelPreferencesStore();
    await tester.pumpWidget(
      MaterialApp(
        home: TravelPreferencesPage(language: 'ko', store: store),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('여행 취향'), findsOneWidget);
    expect(find.text('나에게 맞는 여행을 추천해요'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('travel-preferences-save')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('interest-localFood')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('interest-localFood')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('travel-preferences-save')));
    await tester.pumpAndSettle();

    expect(store.value.interests, contains(TravelInterest.localFood));
    expect(find.text('이 기기에 여행 취향을 저장했어요.'), findsOneWidget);
  });

  testWidgets('returns food constraints to the summary before final save', (
    tester,
  ) async {
    final store = TravelPreferencesStore();
    await tester.pumpWidget(
      MaterialApp(
        home: TravelPreferencesPage(language: 'ko', store: store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('travel-preferences-scroll')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('food-preferences-entry')),
    );
    await tester.tap(find.byKey(const ValueKey('food-preferences-entry')));
    await tester.pumpAndSettle();
    expect(find.text('반드시 지켜야 해요'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('food-cuisine-korean')),
    );
    await tester.tap(find.byKey(const ValueKey('food-cuisine-korean')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('enum-DietaryMode.halal')),
    );
    await tester.tap(find.byKey(const ValueKey('enum-DietaryMode.halal')));
    await tester.enterText(
      find.byKey(const ValueKey('avoid-ingredients-field')),
      '돼지고기',
    );
    await tester.tap(find.byKey(const ValueKey('preference-detail-apply')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('travel-preferences-save')));
    await tester.pumpAndSettle();

    expect(store.value.cuisines, contains(FoodCuisine.korean));
    expect(store.value.dietaryModes, contains(DietaryMode.halal));
    expect(store.value.avoidIngredients, '돼지고기');
  });

  testWidgets('settings entry opens the preferences page', (tester) async {
    final store = TravelPreferencesStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TravelPreferencesSettingsSection(language: 'en', store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Travel experience'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('travel-preferences-entry')));
    await tester.pumpAndSettle();

    expect(find.text('Travel preferences'), findsOneWidget);
    expect(find.text('Shape recommendations around you'), findsOneWidget);
  });
}
