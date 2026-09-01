import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';

Future<void> showRestaurantCommunicationSheet({
  required BuildContext context,
  required String language,
  required TravelPreferences preferences,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.92,
      child: RestaurantCommunicationSheet(
        language: language,
        preferences: preferences,
      ),
    ),
  );
}

class RestaurantCommunicationSheet extends StatelessWidget {
  const RestaurantCommunicationSheet({
    super.key,
    required this.language,
    required this.preferences,
  });

  final String language;
  final TravelPreferences preferences;

  bool get _hasSafetyRequests =>
      preferences.dietaryModes.isNotEmpty ||
      preferences.allergens.isNotEmpty ||
      preferences.avoidIngredients.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final koreanCard = _koreanCardText(preferences);
    final visitorCard = _visitorCardText(language, preferences);

    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFD7DDE5),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _copy(
                        language,
                        ko: '식당에서 보여주기',
                        en: 'Show at the restaurant',
                        ja: 'お店で見せる',
                        zhHans: '给餐厅工作人员看',
                        zhHant: '給餐廳工作人員看',
                      ),
                      style: const TextStyle(
                        color: LalaVisualColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _copy(
                        language,
                        ko: '직원에게 한국어 요청 카드를 보여 주세요.',
                        en: 'Show the Korean request card to staff.',
                        ja: '韓国語のリクエストカードを店員に見せてください。',
                        zhHans: '请向工作人员出示韩语需求卡。',
                        zhHant: '請向工作人員出示韓語需求卡。',
                      ),
                      style: const TextStyle(
                        color: LalaVisualColors.muted,
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            key: const ValueKey('restaurant-communication-scroll'),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            children: [
              _LanguageLabel(
                icon: Icons.storefront_outlined,
                text: _copy(
                  language,
                  ko: '직원에게 보여 줄 한국어',
                  en: 'Korean to show staff',
                  ja: '店員に見せる韓国語',
                  zhHans: '向工作人员出示的韩语',
                  zhHant: '向工作人員出示的韓語',
                ),
              ),
              const SizedBox(height: 8),
              _RequestCard(
                key: const ValueKey('restaurant-korean-request-card'),
                text: koreanCard,
                accent: const Color(0xFFE24A3B),
              ),
              if (language != 'ko') ...[
                const SizedBox(height: 18),
                _LanguageLabel(
                  icon: Icons.translate,
                  text: _copy(
                    language,
                    ko: '내 언어로 확인',
                    en: 'Check in my language',
                    ja: '自分の言語で確認',
                    zhHans: '用我的语言确认',
                    zhHant: '用我的語言確認',
                  ),
                ),
                const SizedBox(height: 8),
                _RequestCard(
                  key: const ValueKey('restaurant-visitor-request-card'),
                  text: visitorCard,
                  accent: const Color(0xFF0B67D8),
                ),
              ],
              if (!_hasSafetyRequests) ...[
                const SizedBox(height: 14),
                _Notice(
                  icon: Icons.info_outline,
                  text: _copy(
                    language,
                    ko: '저장된 식이 요청이 없어요. 필요한 조건이 있다면 음식 설정에서 먼저 선택해 주세요.',
                    en: 'No dietary requests are saved. Add any needs in Food settings first.',
                    ja: '保存された食事条件はありません。必要な条件を食事設定で追加してください。',
                    zhHans: '尚未保存饮食需求。如有需要，请先在饮食设置中添加。',
                    zhHant: '尚未儲存飲食需求。如有需要，請先在飲食設定中新增。',
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Text(
                _copy(
                  language,
                  ko: '현지에서 물어보기',
                  en: 'Ask a local',
                  ja: '地元の人に聞く',
                  zhHans: '向当地人询问',
                  zhHant: '向當地人詢問',
                ),
                style: const TextStyle(
                  color: LalaVisualColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              for (final phrase in _localPhrases(language))
                _PhraseRow(
                  korean: phrase.korean,
                  translated: phrase.translated,
                  copyLabel: _copy(
                    language,
                    ko: '문구 복사',
                    en: 'Copy phrase',
                    ja: 'フレーズをコピー',
                    zhHans: '复制短语',
                    zhHant: '複製短語',
                  ),
                  onCopy: () =>
                      _copyToClipboard(context, phrase.korean, language),
                ),
              const SizedBox(height: 14),
              _Notice(
                icon: Icons.health_and_safety_outlined,
                text: _copy(
                  language,
                  ko: '이 카드는 의사소통을 돕는 도구이며 안전을 보장하지 않아요. 심한 알레르기가 있다면 주문 전에 직원에게 재료와 교차 접촉 가능성을 직접 확인해 주세요.',
                  en: 'This card supports communication; it does not guarantee safety. For severe allergies, confirm ingredients and possible cross-contact directly with staff before ordering.',
                  ja: 'このカードは意思疎通を助けるもので、安全を保証するものではありません。重いアレルギーがある場合は、注文前に原材料と交差接触の可能性を店員に直接確認してください。',
                  zhHans: '此卡仅用于辅助沟通，并不保证安全。若有严重过敏，请在点餐前直接向工作人员确认食材及交叉接触的可能性。',
                  zhHant: '此卡僅用於輔助溝通，並不保證安全。若有嚴重過敏，請在點餐前直接向工作人員確認食材及交叉接觸的可能性。',
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: LalaVisualColors.line)),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              key: const ValueKey('copy-korean-restaurant-card'),
              onPressed: () => _copyToClipboard(context, koreanCard, language),
              icon: const Icon(Icons.copy_outlined),
              label: Text(
                _copy(
                  language,
                  ko: '한국어 요청 카드 복사',
                  en: 'Copy Korean request card',
                  ja: '韓国語カードをコピー',
                  zhHans: '复制韩语需求卡',
                  zhHant: '複製韓語需求卡',
                ),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0B67D8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LanguageLabel extends StatelessWidget {
  const _LanguageLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF0B67D8)),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: LalaVisualColors.ink,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({super.key, required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          text,
          style: const TextStyle(
            color: LalaVisualColors.ink,
            fontSize: 16,
            height: 1.55,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PhraseRow extends StatelessWidget {
  const _PhraseRow({
    required this.korean,
    required this.translated,
    required this.copyLabel,
    required this.onCopy,
  });

  final String korean;
  final String translated;
  final String copyLabel;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LalaVisualColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  korean,
                  style: const TextStyle(
                    color: LalaVisualColors.ink,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (translated != korean) ...[
                  const SizedBox(height: 4),
                  Text(
                    translated,
                    style: const TextStyle(
                      color: LalaVisualColors.muted,
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: copyLabel,
            onPressed: onCopy,
            icon: const Icon(Icons.copy_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF0B67D8)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF35526F),
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalPhrase {
  const _LocalPhrase(this.korean, this.translated);

  final String korean;
  final String translated;
}

List<_LocalPhrase> _localPhrases(String language) => [
  _LocalPhrase(
    '이 지역에서 주민들이 자주 먹는 메뉴를 추천해 주세요.',
    _copy(
      language,
      ko: '이 지역에서 주민들이 자주 먹는 메뉴를 추천해 주세요.',
      en: 'Please recommend a dish that local residents often eat.',
      ja: 'この地域で地元の人がよく食べるメニューをおすすめしてください。',
      zhHans: '请推荐当地居民经常吃的菜。',
      zhHant: '請推薦當地居民經常吃的菜。',
    ),
  ),
  _LocalPhrase(
    '처음 방문한 사람이 먹기 좋은 대표 메뉴가 무엇인가요?',
    _copy(
      language,
      ko: '처음 방문한 사람이 먹기 좋은 대표 메뉴가 무엇인가요?',
      en: 'Which signature dish is good for a first-time visitor?',
      ja: '初めて来た人におすすめの看板メニューは何ですか？',
      zhHans: '第一次来的人适合吃哪道招牌菜？',
      zhHant: '第一次來的人適合吃哪道招牌菜？',
    ),
  ),
  _LocalPhrase(
    '이 메뉴의 주요 재료와 맵기, 양을 알려 주세요.',
    _copy(
      language,
      ko: '이 메뉴의 주요 재료와 맵기, 양을 알려 주세요.',
      en: 'Please tell me the main ingredients, spice level, and portion size.',
      ja: 'この料理の主な材料、辛さ、量を教えてください。',
      zhHans: '请告诉我这道菜的主要食材、辣度和分量。',
      zhHant: '請告訴我這道菜的主要食材、辣度和份量。',
    ),
  ),
];

String _koreanCardText(TravelPreferences preferences) {
  final sections = <String>['안녕하세요. 주문 전에 확인을 부탁드립니다.'];

  if (preferences.dietaryModes.isNotEmpty) {
    final labels = preferences.dietaryModes.map(_dietaryKoreanLabel).toList()
      ..sort();
    sections.add('식이 요청: ${labels.join(', ')}');
  }
  if (preferences.allergens.isNotEmpty) {
    final labels = preferences.allergens.map(_allergenKoreanLabel).toList()
      ..sort();
    sections.add('알레르기·민감 식품: ${labels.join(', ')}');
  }
  final avoidIngredients = preferences.avoidIngredients.trim();
  if (avoidIngredients.isNotEmpty) {
    sections.add('추가로 피해야 하는 재료: $avoidIngredients');
  }

  if (sections.length > 1) {
    sections.addAll([
      '위 재료가 메뉴, 소스, 육수 또는 고명에 들어가는지 확인해 주세요.',
      '가능하다면 해당 재료를 빼고 조리해 주세요.',
      '같은 기름이나 조리도구를 사용하는지도 알려 주세요.',
    ]);
  }
  sections.add('이 지역에서 주민들이 자주 먹는 메뉴도 추천해 주세요. 감사합니다.');

  return sections.join('\n\n');
}

String _visitorCardText(String language, TravelPreferences preferences) {
  if (language == 'ko') {
    return _koreanCardText(preferences);
  }

  final sections = <String>[
    _copy(
      language,
      ko: '안녕하세요. 주문 전에 확인을 부탁드립니다.',
      en: 'Hello. Please help me check before I order.',
      ja: 'こんにちは。注文前に確認をお願いします。',
      zhHans: '您好。点餐前想请您帮忙确认。',
      zhHant: '您好。點餐前想請您幫忙確認。',
    ),
  ];

  if (preferences.dietaryModes.isNotEmpty) {
    final labels =
        preferences.dietaryModes
            .map((value) => _dietaryLabel(language, value))
            .toList()
          ..sort();
    sections.add(
      '${_copy(language, ko: '식이 요청', en: 'Dietary requests', ja: '食事上の要望', zhHans: '饮食需求', zhHant: '飲食需求')}: ${labels.join(', ')}',
    );
  }
  if (preferences.allergens.isNotEmpty) {
    final labels =
        preferences.allergens
            .map((value) => _allergenLabel(language, value))
            .toList()
          ..sort();
    sections.add(
      '${_copy(language, ko: '알레르기·민감 식품', en: 'Allergens or sensitivities', ja: 'アレルギー・過敏な食品', zhHans: '过敏或敏感食物', zhHant: '過敏或敏感食物')}: ${labels.join(', ')}',
    );
  }
  final avoidIngredients = preferences.avoidIngredients.trim();
  if (avoidIngredients.isNotEmpty) {
    sections.add(
      '${_copy(language, ko: '추가로 피해야 하는 재료', en: 'Other ingredients to avoid', ja: 'その他避ける食材', zhHans: '其他需避免的食材', zhHant: '其他需避免的食材')}: $avoidIngredients',
    );
  }

  if (sections.length > 1) {
    sections.addAll([
      _copy(
        language,
        ko: '위 재료가 메뉴, 소스, 육수 또는 고명에 들어가는지 확인해 주세요.',
        en: 'Please check whether these are in the dish, sauce, broth, or garnish.',
        ja: '上記の食材が料理、ソース、だし、トッピングに含まれるか確認してください。',
        zhHans: '请确认以上食材是否出现在菜品、酱汁、汤底或配料中。',
        zhHant: '請確認以上食材是否出現在菜品、醬汁、湯底或配料中。',
      ),
      _copy(
        language,
        ko: '가능하다면 해당 재료를 빼고 조리해 주세요.',
        en: 'If possible, please prepare it without those ingredients.',
        ja: '可能であれば、その食材を抜いて調理してください。',
        zhHans: '如果可以，请不要加入这些食材。',
        zhHant: '如果可以，請不要加入這些食材。',
      ),
      _copy(
        language,
        ko: '같은 기름이나 조리도구를 사용하는지도 알려 주세요.',
        en: 'Please also tell me if the same oil or utensils are used.',
        ja: '同じ油や調理器具を使うかどうかも教えてください。',
        zhHans: '也请告知是否共用油或厨具。',
        zhHant: '也請告知是否共用油或廚具。',
      ),
    ]);
  }
  sections.add(
    _copy(
      language,
      ko: '이 지역에서 주민들이 자주 먹는 메뉴도 추천해 주세요. 감사합니다.',
      en: 'Please also recommend a dish that local residents often eat. Thank you.',
      ja: 'この地域で地元の人がよく食べる料理もおすすめしてください。ありがとうございます。',
      zhHans: '也请推荐当地居民经常吃的菜。谢谢。',
      zhHant: '也請推薦當地居民經常吃的菜。謝謝。',
    ),
  );

  return sections.join('\n\n');
}

Future<void> _copyToClipboard(
  BuildContext context,
  String value,
  String language,
) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  final message = _copy(
    language,
    ko: '한국어 문구를 복사했어요.',
    en: 'Korean text copied.',
    ja: '韓国語の文をコピーしました。',
    zhHans: '已复制韩语内容。',
    zhHant: '已複製韓語內容。',
  );
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.paddingOf(context).bottom + 84,
      child: IgnorePointer(
        child: Center(
          child: Semantics(
            container: true,
            liveRegion: true,
            label: message,
            child: Material(
              color: const Color(0xFF172237),
              elevation: 6,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  await Future<void>.delayed(const Duration(milliseconds: 1600));
  if (entry.mounted) entry.remove();
}

String _dietaryKoreanLabel(DietaryMode value) => switch (value) {
  DietaryMode.vegetarian => '채식',
  DietaryMode.vegan => '비건',
  DietaryMode.halal => '할랄',
  DietaryMode.kosher => '코셔',
};

String _allergenKoreanLabel(Allergen value) => switch (value) {
  Allergen.nuts => '견과류',
  Allergen.shellfish => '갑각류',
  Allergen.dairy => '유제품',
  Allergen.eggs => '달걀',
  Allergen.gluten => '글루텐',
  Allergen.soy => '콩',
};

String _dietaryLabel(String language, DietaryMode value) {
  final labels = switch (value) {
    DietaryMode.vegetarian => ['채식', 'Vegetarian', 'ベジタリアン', '素食', '素食'],
    DietaryMode.vegan => ['비건', 'Vegan', 'ヴィーガン', '纯素', '全素'],
    DietaryMode.halal => ['할랄', 'Halal', 'ハラール', '清真', '清真'],
    DietaryMode.kosher => ['코셔', 'Kosher', 'コーシャ', '犹太洁食', '猶太潔食'],
  };
  return _localizedList(language, labels);
}

String _allergenLabel(String language, Allergen value) {
  final labels = switch (value) {
    Allergen.nuts => ['견과류', 'Nuts', 'ナッツ', '坚果', '堅果'],
    Allergen.shellfish => ['갑각류', 'Shellfish', '甲殻類', '甲壳类', '甲殼類'],
    Allergen.dairy => ['유제품', 'Dairy', '乳製品', '乳制品', '乳製品'],
    Allergen.eggs => ['달걀', 'Eggs', '卵', '鸡蛋', '雞蛋'],
    Allergen.gluten => ['글루텐', 'Gluten', 'グルテン', '麸质', '麩質'],
    Allergen.soy => ['콩', 'Soy', '大豆', '大豆', '大豆'],
  };
  return _localizedList(language, labels);
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

String _localizedList(String language, List<String> labels) =>
    switch (language) {
      'en' => labels[1],
      'ja' => labels[2],
      'zh-Hans' => labels[3],
      'zh-Hant' => labels[4],
      _ => labels[0],
    };
