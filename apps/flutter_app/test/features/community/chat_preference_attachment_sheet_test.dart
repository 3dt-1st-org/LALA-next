import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/features/community/presentation/chat_preference_attachment_sheet.dart';
import 'package:lala_next_app/features/community/presentation/pages/chat_room_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    OnboardingState.applySnapshot(
      const OnboardingSnapshot(completed: true, language: 'ko'),
    );
  });

  tearDown(OnboardingState.reset);

  testWidgets('saved travel details are inserted into the draft, not sent', (
    tester,
  ) async {
    final store = TravelPreferencesStore();
    await store.ensureLoaded();
    await store.save(
      const TravelPreferences(
        pace: TravelPace.relaxed,
        interests: <TravelInterest>{
          TravelInterest.localFood,
          TravelInterest.history,
        },
        allergens: <Allergen>{Allergen.shellfish},
        companions: <TravelCompanion>{TravelCompanion.friends},
        transportModes: <TransportMode>{TransportMode.walk},
        avoidStairs: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatRoomPage(
          roomId: 'room-1',
          initialConfig: const LalaAppConfig(
            baseUri: 'https://example.invalid',
          ),
          preferencesStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chat-attach-preferences')));
    await tester.pumpAndSettle();
    expect(find.text('채팅에 정보 첨부'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-attach-travel-summary')));
    await tester.pumpAndSettle();

    final composer = tester.widget<TextField>(find.byType(TextField));
    expect(composer.controller!.text, contains('[여행 취향 요약]'));
    expect(composer.controller!.text, contains('로컬 음식'));
    expect(composer.controller!.text, contains('계단 최소화'));
    expect(find.byKey(const ValueKey('chat-failed-message')), findsNothing);
    expect(find.textContaining('확인한 뒤 보내 주세요'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-attach-preferences')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-attach-dietary-request')));
    await tester.pumpAndSettle();

    expect(composer.controller!.text, contains('알레르기·민감 식품: 갑각류'));
    expect(composer.controller!.text, isNot(contains('생명')));
    expect(composer.controller!.text, isNot(contains('severe')));
  });

  testWidgets('attachment choices stay unavailable without a saved profile', (
    tester,
  ) async {
    final store = TravelPreferencesStore();
    await store.ensureLoaded();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatPreferenceAttachmentSheet(language: 'ko', store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('먼저 음식 설정'), findsOneWidget);
    expect(find.textContaining('먼저 내 정보'), findsOneWidget);
    final dietary = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('chat-attach-dietary-request')),
        matching: find.byType(InkWell),
      ),
    );
    final travel = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('chat-attach-travel-summary')),
        matching: find.byType(InkWell),
      ),
    );
    expect(dietary.onTap, isNull);
    expect(travel.onTap, isNull);
  });

  test(
    'English dietary draft contains a review copy and Korean staff copy',
    () {
      const preferences = TravelPreferences(
        dietaryModes: <DietaryMode>{DietaryMode.halal},
        avoidIngredients: 'sesame',
      );

      final draft = buildDietaryChatDraft('en', preferences);
      expect(draft, contains('Dietary requests: Halal'));
      expect(draft, contains('Korean for restaurant staff'));
      expect(draft, contains('식이 요청: 할랄'));
      expect(draft, isNot(contains('life-threatening')));
    },
  );

  test(
    'dietary draft reuses the exact current restaurant card content',
    () {
      // CP2: the chat attachment and the sheet share the same builders, so
      // spice/order requests land in the draft in both languages.
      const preferences = TravelPreferences(
        spiceLevel: SpicePreference.spicy,
        orderRequests: <RestaurantOrderRequest>{
          RestaurantOrderRequest.takeout,
        },
      );

      final draft = buildDietaryChatDraft('en', preferences);

      expect(draft, contains('Spice level: I enjoy spicy food.'));
      expect(draft, contains('Please pack the leftovers'));
      expect(draft, contains('맵기: 매운 음식을 잘 먹습니다.'));
      expect(draft, contains('남은 음식을 포장해 주시면 감사하겠습니다'));
      expect(draft, contains('Korean for restaurant staff'));
      expect(draft, isNot(contains('Allergens or sensitivities')));
      expect(draft, isNot(contains('알레르기')));
    },
  );

  testWidgets('soft-only saved content enables the dietary attachment', (
    tester,
  ) async {
    final store = TravelPreferencesStore();
    await store.ensureLoaded();
    await store.save(
      const TravelPreferences(
        spiceLevel: SpicePreference.medium,
        orderRequests: <RestaurantOrderRequest>{
          RestaurantOrderRequest.smallPortion,
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatPreferenceAttachmentSheet(language: 'ko', store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dietary = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('chat-attach-dietary-request')),
        matching: find.byType(InkWell),
      ),
    );
    expect(dietary.onTap, isNotNull);
    expect(find.textContaining('맵기·주문 요청'), findsOneWidget);
  });
}
