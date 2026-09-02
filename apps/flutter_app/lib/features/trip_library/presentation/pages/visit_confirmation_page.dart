import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/planner/planner_helpers.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_store.dart';
import 'package:lala_next_app/features/trip_library/domain/trip_library_models.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';
import 'package:lala_next_app/shared/l10n/place_labels.dart';

/// S-25: explicit, bounded visit outcome with opt-in recommendation use.
class VisitConfirmationPage extends StatefulWidget {
  const VisitConfirmationPage({
    super.key,
    required this.planDate,
    required this.slotPeriod,
    this.slot,
    this.tripStore,
  });

  final String planDate;
  final String slotPeriod;
  final LalaPlanSlot? slot;
  final TripLibraryStore? tripStore;

  @override
  State<VisitConfirmationPage> createState() => _VisitConfirmationPageState();
}

class _VisitConfirmationPageState extends State<VisitConfirmationPage> {
  late final TripLibraryStore _store;
  TripVisitStatus _status = TripVisitStatus.planned;
  TripVisitReason? _reason;
  bool _useForRecommendations = false;
  bool _ready = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _store = widget.tripStore ?? TripLibraryStore.instance;
    unawaited(_load());
  }

  Future<void> _load() async {
    await _store.ensureLoaded();
    final feedback = _store.visitFor(widget.planDate, widget.slotPeriod);
    if (!mounted) return;
    setState(() {
      _status = feedback.status;
      _reason = feedback.reason;
      _useForRecommendations = feedback.useForRecommendations;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: OnboardingState.languageListenable,
      builder: (context, language, _) => AnimatedBuilder(
        animation: _store,
        builder: (context, _) => Scaffold(
          key: const ValueKey('visit-confirmation-page'),
          backgroundColor: LalaVisualColors.surface,
          appBar: AppBar(
            backgroundColor: LalaVisualColors.surface,
            surfaceTintColor: Colors.transparent,
            title: Text(
              _copy(
                language,
                '방문 확인',
                'Visit confirmation',
                '訪問の確認',
                '到访确认',
                '到訪確認',
              ),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          body: _ready
              ? _body(context, language)
              : const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, String language) {
    final slot = widget.slot;
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: <Widget>[
              _VisitSubjectCard(
                planDate: widget.planDate,
                period: widget.slotPeriod,
                title: slot?.place != null
                    ? placeDisplayName(slot!.place!, language)
                    : slot == null
                    ? periodLabel(widget.slotPeriod, language: language)
                    : planSlotTitle(slot, language),
                language: language,
              ),
              const SizedBox(height: 20),
              Text(
                _copy(
                  language,
                  '이 장소를 방문했나요?',
                  'Did you visit this place?',
                  'この場所を訪れましたか？',
                  '您到访了这个地点吗？',
                  '您到訪了這個地點嗎？',
                ),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              for (final value in TripVisitStatus.values) ...<Widget>[
                _VisitStatusTile(
                  value: value,
                  selected: _status == value,
                  language: language,
                  onTap: _saving ? null : () => _selectStatus(value),
                ),
                const SizedBox(height: 8),
              ],
              if (_status == TripVisitStatus.notVisited) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _copy(
                    language,
                    '선택 사항: 방문하지 않은 이유',
                    'Optional: why you did not visit',
                    '任意：訪問しなかった理由',
                    '选填：未到访原因',
                    '選填：未到訪原因',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final reason in TripVisitReason.values)
                      ChoiceChip(
                        label: Text(_reasonLabel(reason, language)),
                        selected: _reason == reason,
                        showCheckmark: true,
                        onSelected: _saving
                            ? null
                            : (selected) => setState(
                                () => _reason = selected ? reason : null,
                              ),
                      ),
                  ],
                ),
              ],
              if (_status != TripVisitStatus.planned) ...<Widget>[
                const SizedBox(height: 18),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  child: SwitchListTile(
                    key: const ValueKey('visit-recommendation-consent'),
                    value: _useForRecommendations,
                    onChanged: _saving
                        ? null
                        : (value) =>
                              setState(() => _useForRecommendations = value),
                    title: Text(
                      _copy(
                        language,
                        '비슷한 추천에 반영',
                        'Use for similar recommendations',
                        '似たおすすめに反映',
                        '用于类似推荐',
                        '用於類似推薦',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      _copy(
                        language,
                        '기본값은 꺼짐이며 언제든 바꿀 수 있어요.',
                        'Off by default. You can change it later.',
                        '初期設定はオフで、後から変更できます。',
                        '默认关闭，之后可随时更改。',
                        '預設關閉，之後可隨時變更。',
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _PrivacyNotice(language: language),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: LalaVisualColors.line)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                key: const ValueKey('save-visit-outcome'),
                onPressed: _saving ? null : () => _save(context, language),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  _copy(language, '저장', 'Save', '保存', '保存', '儲存'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _selectStatus(TripVisitStatus value) {
    setState(() {
      _status = value;
      if (value != TripVisitStatus.notVisited) _reason = null;
      if (value == TripVisitStatus.planned) {
        _useForRecommendations = false;
      }
    });
  }

  Future<void> _save(BuildContext context, String language) async {
    setState(() => _saving = true);
    final feedback = TripVisitFeedback(
      status: _status,
      reason: _status == TripVisitStatus.notVisited ? _reason : null,
      useForRecommendations: _status == TripVisitStatus.planned
          ? false
          : _useForRecommendations,
      confirmedAt: _status == TripVisitStatus.planned
          ? null
          : DateTime.now().toUtc().toIso8601String(),
    );
    await _store.saveVisit(
      widget.planDate,
      widget.slotPeriod,
      placeId: widget.slot?.place?.placeId,
      feedback: feedback,
    );
    if (!context.mounted) return;
    final localOnly = _store.syncStatus == TripLibrarySyncStatus.localOnly;
    final syncFailed = _store.syncStatus == TripLibrarySyncStatus.error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          syncFailed
              ? _copy(
                  language,
                  '기기에 저장했어요. 계정 동기화는 나중에 다시 시도합니다.',
                  'Saved on this device. Account sync can be retried later.',
                  '端末に保存しました。アカウント同期は後で再試行できます。',
                  '已保存到设备，可稍后重试账号同步。',
                  '已儲存至裝置，可稍後重試帳號同步。',
                )
              : localOnly
              ? _copy(
                  language,
                  '이 기기에 저장했어요.',
                  'Saved on this device.',
                  'この端末に保存しました。',
                  '已保存到此设备。',
                  '已儲存至此裝置。',
                )
              : _copy(
                  language,
                  '방문 기록을 저장했어요.',
                  'Visit outcome saved.',
                  '訪問記録を保存しました。',
                  '到访记录已保存。',
                  '到訪記錄已儲存。',
                ),
        ),
      ),
    );
    Navigator.of(context).pop(true);
  }
}

class _VisitSubjectCard extends StatelessWidget {
  const _VisitSubjectCard({
    required this.planDate,
    required this.period,
    required this.title,
    required this.language,
  });

  final String planDate;
  final String period;
  final String title;
  final String language;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF062552),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: <Widget>[
        const Icon(Icons.place_outlined, color: Colors.white, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$planDate · ${periodLabel(period, language: language)}',
                style: const TextStyle(
                  color: Color(0xFFDCE9FF),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _VisitStatusTile extends StatelessWidget {
  const _VisitStatusTile({
    required this.value,
    required this.selected,
    required this.language,
    required this.onTap,
  });

  final TripVisitStatus value;
  final bool selected;
  final String language;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, label, detail) = switch (value) {
      TripVisitStatus.visited => (
        Icons.check_circle_outline_rounded,
        _copy(language, '방문했어요', 'I visited', '訪問しました', '已到访', '已到訪'),
        _copy(
          language,
          '방문 완료로 기록합니다.',
          'Record this stop as visited.',
          '訪問済みとして記録します。',
          '将此站记录为已到访。',
          '將此站記錄為已到訪。',
        ),
      ),
      TripVisitStatus.notVisited => (
        Icons.do_not_disturb_alt_outlined,
        _copy(
          language,
          '방문하지 않았어요',
          'I did not visit',
          '訪問しませんでした',
          '未到访',
          '未到訪',
        ),
        _copy(
          language,
          '선택적으로 이유를 남길 수 있어요.',
          'You can optionally select a reason.',
          '任意で理由を選択できます。',
          '可选择性填写原因。',
          '可選擇性填寫原因。',
        ),
      ),
      TripVisitStatus.planned => (
        Icons.schedule_outlined,
        _copy(language, '아직 미정', 'Not decided', '未定', '尚未决定', '尚未決定'),
        _copy(
          language,
          '방문 결과와 추천 활용 동의를 지웁니다.',
          'Clear the outcome and recommendation consent.',
          '結果とおすすめ利用の同意を消去します。',
          '清除到访结果和推荐使用同意。',
          '清除到訪結果與推薦使用同意。',
        ),
      ),
    };
    return Semantics(
      selected: selected,
      button: true,
      label: '$label. $detail',
      child: Material(
        color: selected ? LalaVisualColors.primarySoft : Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected
                    ? LalaVisualColors.primaryBlue
                    : LalaVisualColors.line,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, color: LalaVisualColors.primaryBlue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: const TextStyle(
                          color: LalaVisualColors.muted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected
                      ? LalaVisualColors.primaryBlue
                      : LalaVisualColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFEEF5FF),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFC9DCFA)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.shield_outlined, color: LalaVisualColors.primaryBlue),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _copy(
              language,
              '정확한 이동 경로나 자유서술 후기는 저장하지 않아요. 추천 반영 여부는 직접 선택합니다.',
              'Precise routes and free-text reviews are not stored. You control whether this affects recommendations.',
              '正確な移動経路や自由記述の口コミは保存しません。おすすめへの反映は自分で選べます。',
              '不会保存精确路线或自由文本评论，是否用于推荐由您决定。',
              '不會儲存精確路線或自由文字評論，是否用於推薦由您決定。',
            ),
            style: const TextStyle(
              color: Color(0xFF244A7C),
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

String _reasonLabel(
  TripVisitReason reason,
  String language,
) => switch (reason) {
  TripVisitReason.closed => _copy(
    language,
    '휴무·영업 종료',
    'Closed',
    '休業・閉店',
    '闭店',
    '休息／已打烊',
  ),
  TripVisitReason.weather => _copy(language, '날씨', 'Weather', '天気', '天气', '天氣'),
  TripVisitReason.crowded => _copy(language, '혼잡', 'Crowded', '混雑', '拥挤', '擁擠'),
  TripVisitReason.time => _copy(
    language,
    '시간 부족',
    'Not enough time',
    '時間不足',
    '时间不足',
    '時間不足',
  ),
  TripVisitReason.transport => _copy(
    language,
    '이동 문제',
    'Transport',
    '移動の問題',
    '交通问题',
    '交通問題',
  ),
  TripVisitReason.changedMind => _copy(
    language,
    '마음이 바뀜',
    'Changed my mind',
    '予定変更',
    '改变主意',
    '改變主意',
  ),
  TripVisitReason.other => _copy(language, '기타', 'Other', 'その他', '其他', '其他'),
};

String _copy(
  String language,
  String ko,
  String en,
  String ja,
  String zhHans,
  String zhHant,
) => lalaCopyMulti(
  language,
  ko: ko,
  en: en,
  ja: ja,
  zhHans: zhHans,
  zhHant: zhHant,
);
