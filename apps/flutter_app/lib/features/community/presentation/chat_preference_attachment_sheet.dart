import 'package:flutter/material.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/preferences/presentation/restaurant_communication_sheet.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

enum ChatPreferenceAttachment { dietaryRequest, travelSummary }

Future<String?> showChatPreferenceAttachmentSheet({
  required BuildContext context,
  required String language,
  required TravelPreferencesStore store,
}) async {
  await store.ensureLoaded();
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (context) =>
        ChatPreferenceAttachmentSheet(language: language, store: store),
  );
}

/// Lets a traveler insert saved preferences into a chat draft.
///
/// Selecting an item only returns text to the composer. It does not send a
/// message, so the traveler can review or remove safety information first.
class ChatPreferenceAttachmentSheet extends StatelessWidget {
  const ChatPreferenceAttachmentSheet({
    super.key,
    required this.language,
    required this.store,
  });

  final String language;
  final TravelPreferencesStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final preferences = store.value;
        final hasSavedPreferences = store.hasLocalDocument;
        final hasDietaryNeeds =
            hasSavedPreferences && hasRestaurantSafetyRequests(preferences);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Align(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7DDE5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                lalaCopyMulti(
                  language,
                  ko: '채팅에 정보 첨부',
                  en: 'Add details to chat',
                  ja: 'チャットに情報を追加',
                  zhHans: '添加信息到聊天',
                  zhHant: '新增資訊到聊天',
                ),
                style: const TextStyle(
                  color: LalaVisualColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                lalaCopyMulti(
                  language,
                  ko: '저장된 내용을 메시지 초안에만 넣어요. 확인한 뒤 직접 보내 주세요.',
                  en: 'Saved details are added to your draft only. Review them before sending.',
                  ja: '保存内容は下書きにのみ追加されます。確認してから送信してください。',
                  zhHans: '已保存的信息只会加入草稿，请确认后再发送。',
                  zhHant: '已儲存的資訊只會加入草稿，請確認後再傳送。',
                ),
                style: const TextStyle(
                  color: LalaVisualColors.muted,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              _AttachmentOption(
                key: const ValueKey('chat-attach-dietary-request'),
                icon: Icons.restaurant_menu_outlined,
                color: const Color(0xFFE24A3B),
                title: lalaCopyMulti(
                  language,
                  ko: '식이 요청 카드',
                  en: 'Dietary request card',
                  ja: '食事リクエストカード',
                  zhHans: '饮食需求卡',
                  zhHant: '飲食需求卡',
                ),
                description: hasDietaryNeeds
                    ? lalaCopyMulti(
                        language,
                        ko: '저장한 식이·알레르기 조건을 방문자 언어와 한국어로 첨부해요.',
                        en: 'Adds your saved dietary needs in your language and Korean.',
                        ja: '保存した食事条件を自分の言語と韓国語で追加します。',
                        zhHans: '用您的语言和韩语添加已保存的饮食需求。',
                        zhHant: '用您的語言和韓語新增已儲存的飲食需求。',
                      )
                    : lalaCopyMulti(
                        language,
                        ko: '먼저 음식 설정에서 식이·알레르기 조건을 저장해 주세요.',
                        en: 'Save dietary or allergy needs in Food settings first.',
                        ja: '先に食事設定で食事・アレルギー条件を保存してください。',
                        zhHans: '请先在饮食设置中保存饮食或过敏需求。',
                        zhHant: '請先在飲食設定中儲存飲食或過敏需求。',
                      ),
                enabled: hasDietaryNeeds,
                onTap: () => Navigator.of(
                  context,
                ).pop(buildDietaryChatDraft(language, preferences)),
              ),
              const SizedBox(height: 10),
              _AttachmentOption(
                key: const ValueKey('chat-attach-travel-summary'),
                icon: Icons.tune_rounded,
                color: const Color(0xFF0B67D8),
                title: lalaCopyMulti(
                  language,
                  ko: '여행 취향 요약',
                  en: 'Travel preference summary',
                  ja: '旅行の好みの要約',
                  zhHans: '旅行偏好摘要',
                  zhHant: '旅行偏好摘要',
                ),
                description: hasSavedPreferences
                    ? lalaCopyMulti(
                        language,
                        ko: '속도, 관심사, 동행, 이동·접근성 조건을 간단히 첨부해요.',
                        en: 'Adds a concise summary of pace, interests, companions, and mobility.',
                        ja: 'ペース、関心、同行者、移動条件を簡潔に追加します。',
                        zhHans: '简要添加节奏、兴趣、同行者和出行条件。',
                        zhHant: '簡要新增節奏、興趣、同行者和移動條件。',
                      )
                    : lalaCopyMulti(
                        language,
                        ko: '먼저 내 정보에서 여행 취향을 저장해 주세요.',
                        en: 'Save travel preferences in My Info first.',
                        ja: '先にマイページで旅行の好みを保存してください。',
                        zhHans: '请先在“我的”中保存旅行偏好。',
                        zhHant: '請先在「我的」中儲存旅行偏好。',
                      ),
                enabled: hasSavedPreferences,
                onTap: () => Navigator.of(
                  context,
                ).pop(buildTravelPreferencesChatDraft(language, preferences)),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  MaterialLocalizations.of(context).cancelButtonLabel,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  const _AttachmentOption({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? LalaVisualColors.ink : const Color(0xFF94A3B8);
    return Semantics(
      button: true,
      enabled: enabled,
      label: title,
      hint: description,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: enabled
                  ? color.withValues(alpha: 0.07)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(
                LalaVisualTokens.controlRadius,
              ),
              border: Border.all(
                color: enabled
                    ? color.withValues(alpha: 0.42)
                    : LalaVisualColors.line,
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: enabled
                        ? color.withValues(alpha: 0.12)
                        : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: enabled ? color : const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          color: enabled
                              ? LalaVisualColors.muted
                              : const Color(0xFF94A3B8),
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String buildDietaryChatDraft(String language, TravelPreferences preferences) {
  final korean = buildKoreanRestaurantRequestCard(preferences);
  if (language == 'ko') return korean;
  final visitor = buildVisitorRestaurantRequestCard(language, preferences);
  final koreanHeading = lalaCopyMulti(
    language,
    ko: '한국어',
    en: 'Korean for restaurant staff',
    ja: '店員に見せる韓国語',
    zhHans: '给餐厅工作人员看的韩语',
    zhHant: '給餐廳工作人員看的韓語',
  );
  return '$visitor\n\n--- $koreanHeading ---\n\n$korean';
}

String buildTravelPreferencesChatDraft(
  String language,
  TravelPreferences preferences,
) {
  final lines = <String>[
    lalaCopyMulti(
      language,
      ko: '[여행 취향 요약]',
      en: '[Travel preference summary]',
      ja: '[旅行の好みの要約]',
      zhHans: '[旅行偏好摘要]',
      zhHant: '[旅行偏好摘要]',
    ),
    '${_label(language, 'pace')}: ${_paceLabel(language, preferences.pace)}',
  ];
  if (preferences.interests.isNotEmpty) {
    final values =
        preferences.interests
            .map((value) => _interestLabel(language, value))
            .toList()
          ..sort();
    lines.add('${_label(language, 'interests')}: ${values.join(', ')}');
  }
  final companions =
      preferences.companions
          .map((value) => _companionLabel(language, value))
          .toList()
        ..sort();
  lines.add('${_label(language, 'companions')}: ${companions.join(', ')}');
  final transport =
      preferences.transportModes
          .map((value) => _transportLabel(language, value))
          .toList()
        ..sort();
  lines.add(
    '${_label(language, 'mobility')}: ${transport.join(', ')} · ${preferences.maxOneWayMinutes}${_minutes(language)}',
  );
  final accessibility = <String>[
    if (preferences.avoidStairs) _label(language, 'avoidStairs'),
    if (preferences.wheelchairAccess) _label(language, 'wheelchair'),
    if (preferences.strollerAccess) _label(language, 'stroller'),
    if (preferences.verifiedAccessibilityOnly)
      _label(language, 'verifiedAccessibility'),
  ];
  if (accessibility.isNotEmpty) {
    lines.add(
      '${_label(language, 'accessibility')}: ${accessibility.join(', ')}',
    );
  }
  lines.add(
    '${_label(language, 'wait')}: ${preferences.maxWaitMinutes}${_minutes(language)}',
  );
  return lines.join('\n');
}

String _label(String language, String key) {
  final labels = <String, List<String>>{
    'pace': ['여행 속도', 'Pace', '旅行ペース', '旅行节奏', '旅行節奏'],
    'interests': ['관심사', 'Interests', '関心', '兴趣', '興趣'],
    'companions': ['동행', 'Companions', '同行者', '同行者', '同行者'],
    'mobility': ['이동', 'Mobility', '移動', '出行', '移動'],
    'accessibility': ['접근성', 'Accessibility', 'アクセシビリティ', '无障碍', '無障礙'],
    'avoidStairs': ['계단 최소화', 'Minimize stairs', '階段を最小限に', '尽量少走楼梯', '盡量少走樓梯'],
    'wheelchair': ['휠체어 우선', 'Wheelchair access', '車いす対応', '轮椅通行', '輪椅通行'],
    'stroller': ['유아차 우선', 'Stroller access', 'ベビーカー対応', '婴儿车通行', '嬰兒車通行'],
    'verifiedAccessibility': [
      '검증된 정보만',
      'Verified access only',
      '確認済み情報のみ',
      '仅限已验证信息',
      '僅限已驗證資訊',
    ],
    'wait': ['최대 대기', 'Maximum wait', '最大待ち時間', '最长等候', '最長等候'],
  };
  return _localized(language, labels[key]!);
}

String _paceLabel(String language, TravelPace value) =>
    _localized(language, switch (value) {
      TravelPace.relaxed => ['여유롭게', 'Relaxed', 'ゆったり', '悠闲', '悠閒'],
      TravelPace.balanced => ['균형 있게', 'Balanced', 'バランス', '均衡', '均衡'],
      TravelPace.packed => ['알차게', 'Packed', '充実', '充实', '充實'],
    });

String _interestLabel(String language, TravelInterest value) =>
    _localized(language, switch (value) {
      TravelInterest.localFood => [
        '로컬 음식',
        'Local food',
        'ローカル料理',
        '本地美食',
        '在地美食',
      ],
      TravelInterest.cafe => ['카페', 'Cafes', 'カフェ', '咖啡馆', '咖啡館'],
      TravelInterest.history => ['전통·역사', 'History', '伝統・歴史', '传统历史', '傳統歷史'],
      TravelInterest.arts => ['미술·공연', 'Arts', '芸術・公演', '艺术演出', '藝術表演'],
      TravelInterest.nature => ['자연', 'Nature', '自然', '自然', '自然'],
      TravelInterest.walk => ['산책', 'Walks', '散歩', '散步', '散步'],
      TravelInterest.night => ['야경', 'Night views', '夜景', '夜景', '夜景'],
      TravelInterest.shopping => ['쇼핑', 'Shopping', '買い物', '购物', '購物'],
      TravelInterest.market => ['시장', 'Markets', '市場', '市场', '市場'],
      TravelInterest.festival => ['축제', 'Festivals', '祭り', '节庆', '節慶'],
      TravelInterest.handsOn => ['체험', 'Hands-on', '体験', '体验', '體驗'],
      TravelInterest.photography => ['사진', 'Photography', '写真', '摄影', '攝影'],
    });

String _companionLabel(String language, TravelCompanion value) =>
    _localized(language, switch (value) {
      TravelCompanion.solo => ['혼자', 'Solo', 'ひとり', '独自', '獨自'],
      TravelCompanion.partner => ['연인', 'Partner', 'パートナー', '伴侣', '伴侶'],
      TravelCompanion.friends => ['친구', 'Friends', '友人', '朋友', '朋友'],
      TravelCompanion.family => ['가족', 'Family', '家族', '家人', '家人'],
      TravelCompanion.children => [
        '아이 동반',
        'With children',
        '子ども連れ',
        '带孩子',
        '帶孩子',
      ],
      TravelCompanion.senior => [
        '어르신 동반',
        'With seniors',
        'シニア同行',
        '与长者同行',
        '與長者同行',
      ],
      TravelCompanion.pet => ['반려동물', 'With a pet', 'ペット同伴', '带宠物', '帶寵物'],
    });

String _transportLabel(String language, TransportMode value) =>
    _localized(language, switch (value) {
      TransportMode.walk => ['도보', 'Walk', '徒歩', '步行', '步行'],
      TransportMode.transit => ['대중교통', 'Transit', '公共交通', '公共交通', '大眾運輸'],
      TransportMode.taxi => ['택시', 'Taxi', 'タクシー', '出租车', '計程車'],
      TransportMode.car => ['자동차', 'Car', '車', '驾车', '開車'],
      TransportMode.bicycle => ['자전거', 'Bicycle', '自転車', '自行车', '自行車'],
    });

String _minutes(String language) =>
    _localized(language, const <String>['분', ' min', '分', '分钟', '分鐘']);

String _localized(String language, List<String> values) => switch (language) {
  'en' => values[1],
  'ja' => values[2],
  'zh-Hans' => values[3],
  'zh-Hant' => values[4],
  _ => values[0],
};
