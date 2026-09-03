import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/features/place/widgets/featured_place_panel.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('restaurant detail opens a Korean staff card with saved needs', (
    tester,
  ) async {
    final store = TravelPreferencesStore();
    await store.ensureLoaded();
    await store.save(
      const TravelPreferences(
        dietaryModes: {DietaryMode.halal},
        allergens: {Allergen.nuts},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _panel(category: 'restaurant', store: store),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('식당 직원에게 보여주기'), findsOneWidget);
    expect(find.textContaining('2개'), findsOneWidget);
    final staffCardSemantics = find.bySemanticsLabel('식당 직원에게 보여 줄 요청 카드 열기');
    expect(staffCardSemantics, findsOneWidget);
    expect(
      tester.getSemantics(staffCardSemantics),
      matchesSemantics(
        label: '식당 직원에게 보여 줄 요청 카드 열기',
        hint: '저장한 식이·알레르기 조건 2개를 한국어 요청 카드에 반영해요.',
        isButton: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('restaurant-detail-show-staff')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('restaurant-korean-request-card')),
      findsOneWidget,
    );
    expect(find.textContaining('식이 요청: 할랄'), findsOneWidget);
    expect(find.textContaining('알레르기·민감 식품: 견과류'), findsOneWidget);

    final largeTextButton = find.byKey(
      const ValueKey('restaurant-large-text-mode'),
    );
    await tester.scrollUntilVisible(
      largeTextButton,
      160,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('restaurant-communication-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(largeTextButton);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('restaurant-large-text-card')),
      findsOneWidget,
    );
    final largeText = tester.widget<SelectableText>(
      find.descendant(
        of: find.byKey(const ValueKey('restaurant-large-text-card')),
        matching: find.byType(SelectableText),
      ),
    );
    expect(largeText.style?.fontSize, 26);
    expect(find.text('직원에게 보여 주세요'), findsOneWidget);
  });

  testWidgets('non-restaurant detail omits the staff card', (tester) async {
    final store = TravelPreferencesStore();
    await store.ensureLoaded();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _panel(category: 'attraction', store: store),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('restaurant-detail-show-staff')),
      findsNothing,
    );
  });
}

FeaturedPlacePanel _panel({
  required String category,
  required TravelPreferencesStore store,
}) {
  return FeaturedPlacePanel(
    place: LalaPlace(
      placeId: 'place-1',
      name: '테스트 장소',
      nameKo: '테스트 장소',
      nameEn: 'Test place',
      category: category,
      lat: 0,
      lng: 0,
      address: '주소',
      distanceM: 100,
      source: 'db',
    ),
    language: 'ko',
    weather: null,
    intervention: null,
    dailyPlan: null,
    docentScript: null,
    docentAudio: null,
    audioLoading: false,
    audioError: null,
    liveSpeechEnabled: false,
    source: 'db',
    showEvidence: false,
    savedPlaceIds: const <String>{},
    detailDocentPlayedPlaceIds: const <String>{},
    onToggleEvidence: () {},
    onToggleSavedPlace: (_) {},
    onAddToPlan: () {},
    onFetchAudio: () {},
    preferencesStore: store,
  );
}
