import 'dart:async';

import 'package:flutter/material.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_store.dart';
import 'package:lala_next_app/features/trip_library/domain/trip_library_models.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

/// S-22: soft preferences that apply to one UTC trip date only.
class TripSettingsPage extends StatefulWidget {
  const TripSettingsPage({
    super.key,
    required this.planDate,
    this.tripStore,
    this.preferencesStore,
  });

  final String planDate;
  final TripLibraryStore? tripStore;
  final TravelPreferencesStore? preferencesStore;

  @override
  State<TripSettingsPage> createState() => _TripSettingsPageState();
}

class _TripSettingsPageState extends State<TripSettingsPage> {
  late final TripLibraryStore _tripStore;
  late final TravelPreferencesStore _preferencesStore;
  TripPreferenceOverride _draft = const TripPreferenceOverride();
  bool _ready = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tripStore = widget.tripStore ?? TripLibraryStore.instance;
    _preferencesStore =
        widget.preferencesStore ?? TravelPreferencesStore.instance;
    unawaited(_load());
  }

  Future<void> _load() async {
    await Future.wait(<Future<void>>[
      _tripStore.ensureLoaded(),
      _preferencesStore.ensureLoaded(),
    ]);
    if (!mounted) return;
    setState(() {
      _draft = _tripStore.overrideFor(widget.planDate);
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: OnboardingState.languageListenable,
      builder: (context, language, _) => AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          _tripStore,
          _preferencesStore,
        ]),
        builder: (context, _) => Scaffold(
          key: const ValueKey('trip-settings-page'),
          backgroundColor: LalaVisualColors.surface,
          appBar: AppBar(
            backgroundColor: LalaVisualColors.surface,
            surfaceTintColor: Colors.transparent,
            title: Text(
              _copy(
                language,
                '이번 여행 설정',
                'This trip settings',
                '今回の旅行設定',
                '本次旅行设置',
                '本次旅行設定',
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
    final defaults = _preferencesStore.value;
    final effective = _draft.applyTo(defaults);
    final sync = _tripStore.syncStatus;
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: <Widget>[
              _SyncBanner(
                language: language,
                planDate: widget.planDate,
                differenceCount: _draft.differenceCount,
                status: sync,
                onReload: sync == TripLibrarySyncStatus.conflict
                    ? () async {
                        await _tripStore.reloadOverrideFromAccount(
                          widget.planDate,
                        );
                        if (mounted) {
                          setState(() {
                            _draft = _tripStore.overrideFor(widget.planDate);
                          });
                        }
                      }
                    : null,
              ),
              const SizedBox(height: 20),
              _SectionTitle(
                icon: Icons.people_alt_outlined,
                text: _copy(
                  language,
                  '동행과 속도',
                  'Company and pace',
                  '同行者とペース',
                  '同行与节奏',
                  '同行與節奏',
                ),
              ),
              const SizedBox(height: 10),
              _EnumWrap<TravelCompanion>(
                values: TravelCompanion.values,
                selected: effective.companions,
                label: (value) => _companionLabel(value, language),
                onChanged: (value) => setState(() {
                  final next = Set<TravelCompanion>.of(effective.companions);
                  if (!next.remove(value)) next.add(value);
                  if (next.isEmpty) next.add(TravelCompanion.solo);
                  _draft = _draft.copyWith(companions: next);
                }),
              ),
              const SizedBox(height: 12),
              _SegmentedField<TravelPace>(
                label: _copy(
                  language,
                  '여행 속도',
                  'Pace',
                  '旅行ペース',
                  '旅行节奏',
                  '旅行節奏',
                ),
                values: TravelPace.values,
                selected: effective.pace,
                text: (value) => _paceLabel(value, language),
                onChanged: (value) =>
                    setState(() => _draft = _draft.copyWith(pace: value)),
              ),
              const SizedBox(height: 22),
              _SectionTitle(
                icon: Icons.cloud_outlined,
                text: _copy(
                  language,
                  '날씨와 이동',
                  'Weather and movement',
                  '天気と移動',
                  '天气与移动',
                  '天氣與移動',
                ),
              ),
              const SizedBox(height: 10),
              _SegmentedField<IndoorOutdoorPreference>(
                label: _copy(
                  language,
                  '실내·야외 선호',
                  'Indoor / outdoor',
                  '屋内・屋外',
                  '室内／室外',
                  '室內／室外',
                ),
                values: IndoorOutdoorPreference.values,
                selected: effective.indoorOutdoorPreference,
                text: (value) => _indoorLabel(value, language),
                onChanged: (value) => setState(
                  () =>
                      _draft = _draft.copyWith(indoorOutdoorPreference: value),
                ),
              ),
              const SizedBox(height: 12),
              _SegmentedField<WalkingBand>(
                label: _copy(
                  language,
                  '도보 범위',
                  'Walking range',
                  '徒歩範囲',
                  '步行范围',
                  '步行範圍',
                ),
                values: WalkingBand.values,
                selected: effective.walkingBand,
                text: (value) => _walkingLabel(value, language),
                onChanged: (value) => setState(
                  () => _draft = _draft.copyWith(walkingBand: value),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _copy(language, '이동 수단', 'Transport', '移動手段', '交通方式', '交通方式'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              _EnumWrap<TransportMode>(
                values: TransportMode.values,
                selected: effective.transportModes,
                label: (value) => _transportLabel(value, language),
                onChanged: (value) => setState(() {
                  final next = Set<TransportMode>.of(effective.transportModes);
                  if (!next.remove(value)) next.add(value);
                  if (next.isEmpty) next.add(TransportMode.walk);
                  _draft = _draft.copyWith(transportModes: next);
                }),
              ),
              const SizedBox(height: 22),
              _SectionTitle(
                icon: Icons.tune_rounded,
                text: _copy(
                  language,
                  '혼잡·예산·운영',
                  'Crowds, budget and hours',
                  '混雑・予算・営業時間',
                  '拥挤、预算与营业',
                  '擁擠、預算與營業',
                ),
              ),
              const SizedBox(height: 10),
              _SegmentedField<CrowdTolerance>(
                label: _copy(
                  language,
                  '혼잡 허용',
                  'Crowd tolerance',
                  '混雑の許容度',
                  '拥挤接受度',
                  '擁擠接受度',
                ),
                values: CrowdTolerance.values,
                selected: effective.crowdTolerance,
                text: (value) => _crowdLabel(value, language),
                onChanged: (value) => setState(
                  () => _draft = _draft.copyWith(crowdTolerance: value),
                ),
              ),
              const SizedBox(height: 12),
              _DropdownField<int>(
                label: _copy(
                  language,
                  '최대 대기 시간',
                  'Maximum wait',
                  '最大待ち時間',
                  '最长等待',
                  '最長等候',
                ),
                value: effective.maxWaitMinutes,
                values: const <int>[10, 20, 40, 60],
                text: (value) => _copy(
                  language,
                  '$value분',
                  '$value min',
                  '$value分',
                  '$value分钟',
                  '$value分鐘',
                ),
                onChanged: (value) => setState(
                  () => _draft = _draft.copyWith(maxWaitMinutes: value),
                ),
              ),
              const SizedBox(height: 12),
              _SegmentedField<BudgetBand>(
                label: _copy(language, '예산', 'Budget', '予算', '预算', '預算'),
                values: BudgetBand.values,
                selected: effective.budgetBand,
                text: (value) => _budgetLabel(value, language),
                onChanged: (value) =>
                    setState(() => _draft = _draft.copyWith(budgetBand: value)),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _copy(
                    language,
                    '마감 임박 장소 제외',
                    'Exclude places closing soon',
                    '閉店間近の場所を除外',
                    '排除即将关门的地点',
                    '排除即將關門的地點',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                value: effective.excludeClosingSoon,
                onChanged: (value) => setState(
                  () => _draft = _draft.copyWith(excludeClosingSoon: value),
                ),
              ),
              const SizedBox(height: 18),
              _SafetyPanel(defaults: defaults, language: language),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            12 + MediaQuery.paddingOf(context).bottom,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: LalaVisualColors.line)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving || _draft.isEmpty
                      ? null
                      : () => _confirmReset(context, language),
                  child: Text(
                    _copy(
                      language,
                      '기본값으로',
                      'Use defaults',
                      '基本設定に戻す',
                      '恢复默认',
                      '恢復預設',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  key: const ValueKey('trip-settings-save'),
                  onPressed: _saving ? null : () => _save(language),
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(
                    _copy(
                      language,
                      '이번 여행에 적용',
                      'Apply to this trip',
                      'この旅行に適用',
                      '应用到本次旅行',
                      '套用到本次旅行',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _save(String language) async {
    setState(() => _saving = true);
    await _tripStore.saveOverride(widget.planDate, _draft);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tripStore.syncStatus == TripLibrarySyncStatus.error
              ? _copy(
                  language,
                  '기기에는 저장했지만 계정 동기화가 필요해요.',
                  'Saved on this device; account sync needs attention.',
                  '端末に保存しました。アカウント同期をご確認ください。',
                  '已保存到设备，请检查账号同步。',
                  '已儲存到裝置，請檢查帳號同步。',
                )
              : _copy(
                  language,
                  '이번 여행 설정을 저장했어요.',
                  'Trip settings saved.',
                  '今回の旅行設定を保存しました。',
                  '本次旅行设置已保存。',
                  '本次旅行設定已儲存。',
                ),
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, String language) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _copy(
            language,
            '기본 취향으로 돌아갈까요?',
            'Use your defaults?',
            '基本設定に戻しますか？',
            '恢复默认偏好吗？',
            '恢復預設偏好嗎？',
          ),
        ),
        content: Text(
          _copy(
            language,
            '이번 여행에만 적용한 값이 삭제됩니다. 기본 알레르기와 접근성 설정은 바뀌지 않아요.',
            'Only this trip override is removed. Allergy and accessibility defaults stay unchanged.',
            '今回だけの設定を削除します。アレルギーとアクセシビリティの基本設定は変わりません。',
            '仅删除本次旅行设置，过敏与无障碍默认值不会改变。',
            '只會刪除本次旅行設定，過敏與無障礙預設值不會變更。',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_copy(language, '초기화', 'Reset', 'リセット', '重置', '重設')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _tripStore.resetOverride(widget.planDate);
    if (mounted) setState(() => _draft = const TripPreferenceOverride());
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({
    required this.language,
    required this.planDate,
    required this.differenceCount,
    required this.status,
    this.onReload,
  });

  final String language;
  final String planDate;
  final int differenceCount;
  final TripLibrarySyncStatus status;
  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    final conflict = status == TripLibrarySyncStatus.conflict;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: conflict
            ? const Color(0xFFFFF7ED)
            : LalaVisualColors.primarySoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: conflict ? const Color(0xFFF59E0B) : const Color(0xFFBDD8FA),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            conflict ? Icons.sync_problem_rounded : Icons.tune_rounded,
            color: conflict
                ? const Color(0xFFB45309)
                : LalaVisualColors.primaryBlue,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              conflict
                  ? _copy(
                      language,
                      '다른 기기의 설정과 달라요.',
                      'Settings differ on another device.',
                      '別の端末の設定と異なります。',
                      '与其他设备上的设置不同。',
                      '與其他裝置上的設定不同。',
                    )
                  : _copy(
                      language,
                      '$planDate · 변경 $differenceCount개',
                      '$planDate · $differenceCount changes',
                      '$planDate・変更$differenceCount件',
                      '$planDate · $differenceCount 项更改',
                      '$planDate · $differenceCount 項變更',
                    ),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          if (onReload != null)
            TextButton(
              onPressed: onReload,
              child: Text(
                _copy(
                  language,
                  '계정 값 불러오기',
                  'Load account copy',
                  'アカウント設定を読込',
                  '加载账号设置',
                  '載入帳號設定',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(icon, color: LalaVisualColors.primaryBlue),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ),
    ],
  );
}

class _SegmentedField<T> extends StatelessWidget {
  const _SegmentedField({
    required this.label,
    required this.values,
    required this.selected,
    required this.text,
    required this.onChanged,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T) text;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<T>(
          segments: <ButtonSegment<T>>[
            for (final value in values)
              ButtonSegment<T>(value: value, label: Text(text(value))),
          ],
          selected: <T>{selected},
          onSelectionChanged: (values) => onChanged(values.first),
        ),
      ),
    ],
  );
}

class _EnumWrap<T> extends StatelessWidget {
  const _EnumWrap({
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<T> values;
  final Set<T> selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      for (final value in values)
        FilterChip(
          label: Text(label(value)),
          selected: selected.contains(value),
          onSelected: (_) => onChanged(value),
        ),
    ],
  );
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.values,
    required this.text,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T) text;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
    initialValue: value,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: <DropdownMenuItem<T>>[
      for (final item in values)
        DropdownMenuItem<T>(value: item, child: Text(text(item))),
    ],
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}

class _SafetyPanel extends StatelessWidget {
  const _SafetyPanel({required this.defaults, required this.language});

  final TravelPreferences defaults;
  final String language;

  @override
  Widget build(BuildContext context) {
    final count =
        defaults.allergens.length +
        defaults.dietaryModes.length +
        (defaults.avoidStairs ? 1 : 0) +
        (defaults.wheelchairAccess ? 1 : 0) +
        (defaults.strollerAccess ? 1 : 0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF4B740)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.health_and_safety_outlined,
            color: Color(0xFF8A5700),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _copy(
                language,
                '알레르기·식이·접근성 조건 $count개는 기본 취향에서 상속되며 이번 여행 설정으로 약화할 수 없어요.',
                '$count allergy, dietary and accessibility rules are inherited and cannot be weakened here.',
                'アレルギー・食事・アクセシビリティ条件$count件は継承され、ここでは弱められません。',
                '$count 项过敏、饮食与无障碍条件会继承，无法在此放宽。',
                '$count 項過敏、飲食與無障礙條件會繼承，無法在此放寬。',
              ),
              style: const TextStyle(height: 1.4, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

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

String _paceLabel(TravelPace value, String language) => switch (value) {
  TravelPace.relaxed => _copy(language, '여유', 'Relaxed', 'ゆったり', '悠闲', '悠閒'),
  TravelPace.balanced => _copy(language, '균형', 'Balanced', 'バランス', '均衡', '均衡'),
  TravelPace.packed => _copy(language, '알차게', 'Packed', '充実', '充实', '充實'),
};

String _walkingLabel(WalkingBand value, String language) => switch (value) {
  WalkingBand.short => _copy(language, '짧게', 'Short', '短め', '较短', '較短'),
  WalkingBand.medium => _copy(language, '보통', 'Medium', '普通', '适中', '適中'),
  WalkingBand.long => _copy(language, '길게', 'Long', '長め', '较长', '較長'),
};

String _indoorLabel(IndoorOutdoorPreference value, String language) =>
    switch (value) {
      IndoorOutdoorPreference.indoor => _copy(
        language,
        '실내',
        'Indoor',
        '屋内',
        '室内',
        '室內',
      ),
      IndoorOutdoorPreference.balanced => _copy(
        language,
        '균형',
        'Balanced',
        'バランス',
        '均衡',
        '均衡',
      ),
      IndoorOutdoorPreference.outdoor => _copy(
        language,
        '야외',
        'Outdoor',
        '屋外',
        '室外',
        '室外',
      ),
    };

String _crowdLabel(CrowdTolerance value, String language) => switch (value) {
  CrowdTolerance.quiet => _copy(language, '한적', 'Quiet', '静か', '安静', '清靜'),
  CrowdTolerance.balanced => _copy(
    language,
    '보통',
    'Balanced',
    '普通',
    '适中',
    '適中',
  ),
  CrowdTolerance.popular => _copy(language, '인기', 'Popular', '人気', '热门', '熱門'),
};

String _budgetLabel(BudgetBand value, String language) => switch (value) {
  BudgetBand.value => _copy(language, '실속', 'Value', 'お得', '实惠', '實惠'),
  BudgetBand.balanced => _copy(language, '균형', 'Balanced', '標準', '均衡', '均衡'),
  BudgetBand.special => _copy(language, '특별', 'Special', '特別', '特别', '特別'),
};

String _companionLabel(TravelCompanion value, String language) {
  final labels = <TravelCompanion, List<String>>{
    TravelCompanion.solo: <String>['혼자', 'Solo', '一人', '独自', '獨自'],
    TravelCompanion.partner: <String>['연인', 'Partner', 'パートナー', '伴侣', '伴侶'],
    TravelCompanion.friends: <String>['친구', 'Friends', '友人', '朋友', '朋友'],
    TravelCompanion.family: <String>['가족', 'Family', '家族', '家人', '家人'],
    TravelCompanion.children: <String>['아이', 'Children', '子ども', '儿童', '兒童'],
    TravelCompanion.senior: <String>['어르신', 'Senior', 'シニア', '长者', '長者'],
    TravelCompanion.pet: <String>['반려동물', 'Pet', 'ペット', '宠物', '寵物'],
  };
  final item = labels[value]!;
  return _copy(language, item[0], item[1], item[2], item[3], item[4]);
}

String _transportLabel(TransportMode value, String language) => switch (value) {
  TransportMode.walk => _copy(language, '도보', 'Walk', '徒歩', '步行', '步行'),
  TransportMode.transit => _copy(
    language,
    '대중교통',
    'Transit',
    '公共交通',
    '公共交通',
    '大眾運輸',
  ),
  TransportMode.taxi => _copy(language, '택시', 'Taxi', 'タクシー', '出租车', '計程車'),
  TransportMode.car => _copy(language, '자동차', 'Car', '車', '汽车', '汽車'),
  TransportMode.bicycle => _copy(
    language,
    '자전거',
    'Bicycle',
    '自転車',
    '自行车',
    '自行車',
  ),
};
