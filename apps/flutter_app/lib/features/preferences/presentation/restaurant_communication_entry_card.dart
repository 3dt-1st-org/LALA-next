import 'package:flutter/material.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/preferences/presentation/restaurant_communication_sheet.dart';

class RestaurantCommunicationEntryCard extends StatefulWidget {
  const RestaurantCommunicationEntryCard({
    super.key,
    required this.language,
    this.store,
  });

  final String language;
  final TravelPreferencesStore? store;

  @override
  State<RestaurantCommunicationEntryCard> createState() =>
      _RestaurantCommunicationEntryCardState();
}

class _RestaurantCommunicationEntryCardState
    extends State<RestaurantCommunicationEntryCard> {
  late final TravelPreferencesStore _store;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? TravelPreferencesStore.instance;
    _store.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final preferences = _store.value;
        return Semantics(
          container: true,
          button: true,
          excludeSemantics: true,
          label: _copy(
            widget.language,
            ko: '식당 직원에게 보여 줄 요청 카드 열기',
            en: 'Open the request card to show restaurant staff',
            ja: 'お店のスタッフに見せるリクエストカードを開く',
            zhHans: '打开给餐厅工作人员看的需求卡',
            zhHant: '開啟給餐廳工作人員看的需求卡',
          ),
          hint: _summary(widget.language, preferences),
          onTap: () => _showCommunicationSheet(preferences),
          child: InkWell(
            key: const ValueKey('restaurant-detail-show-staff'),
            borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
            onTap: () => _showCommunicationSheet(preferences),
            child: Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E8),
                borderRadius: BorderRadius.circular(
                  LalaVisualTokens.controlRadius,
                ),
                border: Border.all(color: const Color(0xFFF4C96A)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE9B8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.record_voice_over_outlined,
                      color: Color(0xFF9A5A00),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _copy(
                            widget.language,
                            ko: '식당 직원에게 보여주기',
                            en: 'Show restaurant staff',
                            ja: 'お店のスタッフに見せる',
                            zhHans: '给餐厅工作人员看',
                            zhHant: '給餐廳工作人員看',
                          ),
                          style: const TextStyle(
                            color: LalaVisualColors.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _summary(widget.language, preferences),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: LalaVisualColors.muted,
                            fontSize: 12,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: Color(0xFF9A5A00)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showCommunicationSheet(TravelPreferences preferences) {
    showRestaurantCommunicationSheet(
      context: context,
      language: widget.language,
      preferences: preferences,
    );
  }
}

String _summary(String language, TravelPreferences preferences) {
  final safetyCount =
      preferences.dietaryModes.length +
      preferences.allergens.length +
      (preferences.avoidIngredients.trim().isEmpty ? 0 : 1);
  final hasSoftContent =
      preferences.spiceLevel != null || preferences.orderRequests.isNotEmpty;
  if (safetyCount == 0 && hasSoftContent) {
    return _copy(
      language,
      ko: '저장한 맵기·주문 요청을 한국어 요청 카드에 반영해요.',
      en: 'Your saved spice level and order requests are included in the Korean card.',
      ja: '保存した辛さ・注文リクエストを韓国語カードに反映します。',
      zhHans: '韩语需求卡将包含已保存的辣度和点餐请求。',
      zhHant: '韓語需求卡將包含已儲存的辣度和點餐請求。',
    );
  }
  if (safetyCount == 0) {
    return _copy(
      language,
      ko: '로컬 메뉴 추천, 재료와 맵기를 한국어로 물어봐요.',
      en: 'Ask in Korean about local dishes, ingredients, and spice level.',
      ja: '地元の料理、材料、辛さを韓国語で確認できます。',
      zhHans: '可用韩语询问当地菜品、食材和辣度。',
      zhHant: '可用韓語詢問當地菜品、食材和辣度。',
    );
  }
  return _copy(
    language,
    ko: '저장한 식이·알레르기 조건 $safetyCount개를 한국어 요청 카드에 반영해요.',
    en: '$safetyCount saved dietary or allergy needs are included in the Korean card.',
    ja: '保存した食事・アレルギー条件$safetyCount件を韓国語カードに反映します。',
    zhHans: '韩语需求卡将包含 $safetyCount 项已保存的饮食或过敏需求。',
    zhHant: '韓語需求卡將包含 $safetyCount 項已儲存的飲食或過敏需求。',
  );
}

String _copy(
  String language, {
  required String ko,
  required String en,
  required String ja,
  required String zhHans,
  required String zhHant,
}) => switch (language) {
  'en' => en,
  'ja' => ja,
  'zh-Hans' => zhHans,
  'zh-Hant' => zhHant,
  _ => ko,
};
