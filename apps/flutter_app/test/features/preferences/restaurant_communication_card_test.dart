// CP2: 식당 커뮤니케이션 카드 계약 — 저장된 값만 표시(맵기·주문 요청 포함),
// 안전 언어는 신중하게(알레르기 표기, 안전 보장 부인), 심각도를 발명하지 않는다.
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/preferences/presentation/restaurant_communication_sheet.dart';

void main() {
  group('buildKoreanRestaurantRequestCard', () {
    test('includes only explicitly saved spice and order requests', () {
      const preferences = TravelPreferences(
        spiceLevel: SpicePreference.mild,
        orderRequests: {RestaurantOrderRequest.quietTable},
      );

      final card = buildKoreanRestaurantRequestCard(preferences);

      expect(card, contains('맵기: 안 매운 음식으로 부탁드립니다.'));
      expect(card, contains('요청 사항: 가능하다면 조용한 자리를 부탁드립니다'));
      // Nothing else was saved, so no other request section appears.
      expect(card, isNot(contains('식이 요청:')));
      expect(card, isNot(contains('알레르기')));
      expect(card, isNot(contains('추천 메뉴를 부탁드립니다')));
      expect(card, isNot(contains('양을 조금 적게')));
    });

    test('omits spice and order sections when nothing is saved', () {
      const preferences = TravelPreferences(
        allergens: {Allergen.dairy},
      );

      final card = buildKoreanRestaurantRequestCard(preferences);

      expect(card, contains('알레르기·민감 식품: 유제품'));
      expect(card, isNot(contains('맵기:')));
      expect(card, isNot(contains('요청 사항:')));
    });

    test('keeps cautious cross-contact language only for saved safety needs', () {
      const softOnly = TravelPreferences(
        spiceLevel: SpicePreference.spicy,
        orderRequests: {RestaurantOrderRequest.takeout},
      );
      // Soft preferences are not safety claims: the cross-contact block
      // references ingredients ("위 재료") and must not appear for them.
      expect(buildKoreanRestaurantRequestCard(softOnly), isNot(contains('위 재료가')));

      const withAllergen = TravelPreferences(
        spiceLevel: SpicePreference.spicy,
        allergens: {Allergen.nuts},
      );
      final card = buildKoreanRestaurantRequestCard(withAllergen);
      expect(card, contains('알레르기·민감 식품: 견과류'));
      expect(card, contains('위 재료가 메뉴, 소스, 육수 또는 고명에 들어가는지'));
      // 맵기 still renders alongside the safety content.
      expect(card, contains('맵기: 매운 음식을 잘 먹습니다.'));
    });

    test('uses the correct Korean allergy spelling and invents no severity', () {
      const preferences = TravelPreferences(
        dietaryModes: {DietaryMode.vegan},
        allergens: {Allergen.shellfish, Allergen.eggs},
      );

      final card = buildKoreanRestaurantRequestCard(preferences);

      expect(card, contains('알레르기'));
      expect(card, isNot(contains('알러지')));
      // Never invents a severity the user did not declare.
      expect(card, isNot(contains('응급')));
      expect(card, isNot(contains('위독')));
      expect(card, isNot(contains('아나필락시')));
    });
  });

  group('buildVisitorRestaurantRequestCard', () {
    test('mirrors saved spice and requests in every supported locale', () {
      const preferences = TravelPreferences(
        spiceLevel: SpicePreference.medium,
        orderRequests: {
          RestaurantOrderRequest.staffRecommendation,
          RestaurantOrderRequest.smallPortion,
        },
      );

      final expectations = <String, List<String>>{
        'ko': ['맵기: 보통 맵기로 부탁드립니다.', '추천 메뉴를 부탁드립니다', '양을 조금 적게 부탁드립니다'],
        'en': ['Spice level: medium spice, please.', 'Please recommend a dish', 'A smaller portion, please'],
        'ja': ['辛さ：普通の辛さでお願いします。', 'おすすめの料理をお願いします', '少なめでお願いします'],
        'zh-Hans': ['辣度：请做适中辣度。', '请推荐菜品', '请给小份一些'],
        'zh-Hant': ['辣度：請做適中辣度。', '請推薦菜品', '請給小份一些'],
      };
      for (final entry in expectations.entries) {
        final card = buildVisitorRestaurantRequestCard(entry.key, preferences);
        for (final fragment in entry.value) {
          expect(card, contains(fragment), reason: '${entry.key}: $card');
        }
        // No unsaved content leaks into any locale's mirror.
        expect(card, isNot(contains('조용한 자리')));
        expect(card, isNot(contains('Quiet table')));
      }
    });

    test('shows nothing extra when no restaurant content is saved', () {
      const preferences = TravelPreferences();

      for (final language in ['ko', 'en', 'ja', 'zh-Hans', 'zh-Hant']) {
        final card = buildVisitorRestaurantRequestCard(language, preferences);
        expect(card, isNot(contains('맵기')));
        expect(card, isNot(contains('Spice level')));
        expect(card, isNot(contains('Requests:')));
      }
    });
  });

  group('hasRestaurantCommunicationContent', () {
    test('safety requests, spice, and order requests each count as content', () {
      expect(
        hasRestaurantCommunicationContent(
          const TravelPreferences(dietaryModes: {DietaryMode.halal}),
        ),
        isTrue,
      );
      expect(
        hasRestaurantCommunicationContent(
          const TravelPreferences(allergens: {Allergen.nuts}),
        ),
        isTrue,
      );
      expect(
        hasRestaurantCommunicationContent(
          const TravelPreferences(avoidIngredients: '고수'),
        ),
        isTrue,
      );
      expect(
        hasRestaurantCommunicationContent(
          const TravelPreferences(spiceLevel: SpicePreference.mild),
        ),
        isTrue,
      );
      expect(
        hasRestaurantCommunicationContent(
          const TravelPreferences(orderRequests: {RestaurantOrderRequest.takeout}),
        ),
        isTrue,
      );
      // Cuisines/adventure are plan tastes, not restaurant-card content.
      expect(
        hasRestaurantCommunicationContent(
          const TravelPreferences(cuisines: {FoodCuisine.korean}),
        ),
        isFalse,
      );
      expect(
        hasRestaurantCommunicationContent(const TravelPreferences()),
        isFalse,
      );
    });
  });
}
