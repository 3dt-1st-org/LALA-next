import 'package:flutter/material.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/settings/widgets/settings_section.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

class TravelPreferencesSettingsSection extends StatefulWidget {
  const TravelPreferencesSettingsSection({
    super.key,
    required this.language,
    this.store,
  });

  final String language;
  final TravelPreferencesStore? store;

  @override
  State<TravelPreferencesSettingsSection> createState() =>
      _TravelPreferencesSettingsSectionState();
}

class _TravelPreferencesSettingsSectionState
    extends State<TravelPreferencesSettingsSection> {
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
        final value = _store.value;
        return SettingsSection(
          title: _text(
            widget.language,
            ko: '여행 경험',
            en: 'Travel experience',
            ja: '旅行体験',
            zhHans: '旅行体验',
            zhHant: '旅行體驗',
          ),
          child: InkWell(
            key: const ValueKey('travel-preferences-entry'),
            borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => TravelPreferencesPage(
                  language: widget.language,
                  store: _store,
                ),
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Row(
                children: [
                  const _LeadingIcon(
                    icon: Icons.favorite_outline,
                    color: Color(0xFF0B67D8),
                    background: Color(0xFFEAF3FF),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _text(
                            widget.language,
                            ko: '여행 취향',
                            en: 'Travel preferences',
                            ja: '旅行の好み',
                            zhHans: '旅行偏好',
                            zhHant: '旅行偏好',
                          ),
                          style: const TextStyle(
                            color: LalaVisualColors.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _preferenceSummary(widget.language, value),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: LalaVisualColors.muted,
                            fontSize: 12,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right,
                    color: LalaVisualColors.muted,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class TravelPreferencesPage extends StatefulWidget {
  const TravelPreferencesPage({super.key, required this.language, this.store});

  final String language;
  final TravelPreferencesStore? store;

  @override
  State<TravelPreferencesPage> createState() => _TravelPreferencesPageState();
}

class _TravelPreferencesPageState extends State<TravelPreferencesPage> {
  late final TravelPreferencesStore _store;
  TravelPreferences _draft = const TravelPreferences();
  TravelPreferences _saved = const TravelPreferences();
  bool _loading = true;
  bool _saving = false;
  bool _allowPop = false;

  bool get _dirty => _draft != _saved;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? TravelPreferencesStore.instance;
    _load();
  }

  Future<void> _load() async {
    await _store.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _draft = _store.value;
      _saved = _store.value;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _store.save(_draft);
      if (!mounted) return;
      setState(() => _saved = _draft);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              widget.language,
              ko: '이 기기에 여행 취향을 저장했어요.',
              en: 'Travel preferences saved on this device.',
              ja: '旅行の好みをこの端末に保存しました。',
              zhHans: '旅行偏好已保存在此设备上。',
              zhHant: '旅行偏好已儲存在此裝置上。',
            ),
          ),
        ),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              widget.language,
              ko: '저장하지 못했어요. 다시 시도해 주세요.',
              en: 'Could not save. Please try again.',
              ja: '保存できませんでした。もう一度お試しください。',
              zhHans: '无法保存，请重试。',
              zhHant: '無法儲存，請再試一次。',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestPop() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _text(
            widget.language,
            ko: '변경사항을 버릴까요?',
            en: 'Discard changes?',
            ja: '変更を破棄しますか？',
            zhHans: '放弃更改吗？',
            zhHant: '放棄變更嗎？',
          ),
        ),
        content: Text(
          _text(
            widget.language,
            ko: '저장하지 않은 여행 취향은 사라져요.',
            en: 'Unsaved travel preferences will be lost.',
            ja: '保存していない旅行の好みは失われます。',
            zhHans: '未保存的旅行偏好将丢失。',
            zhHant: '未儲存的旅行偏好將遺失。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              _text(
                widget.language,
                ko: '계속 편집',
                en: 'Keep editing',
                ja: '編集を続ける',
                zhHans: '继续编辑',
                zhHant: '繼續編輯',
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              _text(
                widget.language,
                ko: '버리기',
                en: 'Discard',
                ja: '破棄',
                zhHans: '放弃',
                zhHant: '放棄',
              ),
            ),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    }
  }

  Future<void> _openDetail(
    Widget Function(TravelPreferences value) builder,
  ) async {
    final next = await Navigator.of(context).push<TravelPreferences>(
      MaterialPageRoute<TravelPreferences>(builder: (_) => builder(_draft)),
    );
    if (next != null && mounted) setState(() => _draft = next);
  }

  void _toggleInterest(TravelInterest value) {
    final next = <TravelInterest>{..._draft.interests};
    if (!next.remove(value)) {
      if (next.length == TravelPreferences.maxInterests) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text(
                widget.language,
                ko: '관심사는 최대 5개까지 선택할 수 있어요.',
                en: 'Choose up to five interests.',
                ja: '興味は5つまで選べます。',
                zhHans: '最多可选择 5 个兴趣。',
                zhHant: '最多可選擇 5 個興趣。',
              ),
            ),
          ),
        );
        return;
      }
      next.add(value);
    }
    setState(() => _draft = _draft.copyWith(interests: next));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_dirty || _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestPop();
      },
      child: Scaffold(
        backgroundColor: LalaVisualColors.surface,
        appBar: AppBar(
          backgroundColor: LalaVisualColors.surface,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            key: const ValueKey('travel-preferences-back'),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: _requestPop,
            icon: const Icon(Icons.arrow_back_ios_new),
          ),
          title: Text(
            _text(
              widget.language,
              ko: '여행 취향',
              en: 'Travel preferences',
              ja: '旅行の好み',
              zhHans: '旅行偏好',
              zhHant: '旅行偏好',
            ),
          ),
          centerTitle: true,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                key: const ValueKey('travel-preferences-scroll'),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Text(
                    _text(
                      widget.language,
                      ko: '나에게 맞는 여행을 추천해요',
                      en: 'Shape recommendations around you',
                      ja: 'あなたに合う旅行をおすすめします',
                      zhHans: '为你定制旅行推荐',
                      zhHant: '為你客製旅行推薦',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: LalaVisualColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SectionTitle(
                    title: _text(
                      widget.language,
                      ko: '빠른 조정',
                      en: 'Quick adjust',
                      ja: 'クイック調整',
                      zhHans: '快速调整',
                      zhHant: '快速調整',
                    ),
                  ),
                  _Panel(
                    child: Column(
                      children: [
                        _LabeledControl(
                          label: _text(
                            widget.language,
                            ko: '여행 속도',
                            en: 'Travel pace',
                            ja: '旅行ペース',
                            zhHans: '旅行节奏',
                            zhHant: '旅行節奏',
                          ),
                          child: _SegmentedChoice<TravelPace>(
                            value: _draft.pace,
                            options: {
                              TravelPace.relaxed: _text(
                                widget.language,
                                ko: '여유',
                                en: 'Relaxed',
                                ja: 'ゆったり',
                                zhHans: '悠闲',
                                zhHant: '悠閒',
                              ),
                              TravelPace.balanced: _text(
                                widget.language,
                                ko: '균형',
                                en: 'Balanced',
                                ja: 'バランス',
                                zhHans: '均衡',
                                zhHant: '均衡',
                              ),
                              TravelPace.packed: _text(
                                widget.language,
                                ko: '알차게',
                                en: 'Full',
                                ja: '充実',
                                zhHans: '充实',
                                zhHant: '充實',
                              ),
                            },
                            onChanged: (value) => setState(
                              () => _draft = _draft.copyWith(pace: value),
                            ),
                          ),
                        ),
                        const _PanelDivider(),
                        _LabeledControl(
                          label: _text(
                            widget.language,
                            ko: '혼잡 선호',
                            en: 'Crowds',
                            ja: '混雑の好み',
                            zhHans: '拥挤偏好',
                            zhHant: '擁擠偏好',
                          ),
                          child: _SegmentedChoice<CrowdTolerance>(
                            value: _draft.crowdTolerance,
                            options: {
                              CrowdTolerance.quiet: _text(
                                widget.language,
                                ko: '한적',
                                en: 'Quiet',
                                ja: '静か',
                                zhHans: '安静',
                                zhHant: '安靜',
                              ),
                              CrowdTolerance.balanced: _text(
                                widget.language,
                                ko: '균형',
                                en: 'Balanced',
                                ja: 'バランス',
                                zhHans: '均衡',
                                zhHant: '均衡',
                              ),
                              CrowdTolerance.popular: _text(
                                widget.language,
                                ko: '인기',
                                en: 'Popular',
                                ja: '人気',
                                zhHans: '热门',
                                zhHant: '熱門',
                              ),
                            },
                            onChanged: (value) => setState(
                              () => _draft = _draft.copyWith(
                                crowdTolerance: value,
                              ),
                            ),
                          ),
                        ),
                        const _PanelDivider(),
                        _LabeledControl(
                          label: _text(
                            widget.language,
                            ko: '걷기 허용 범위',
                            en: 'Walking range',
                            ja: '歩行範囲',
                            zhHans: '步行范围',
                            zhHant: '步行範圍',
                          ),
                          child: _SegmentedChoice<WalkingBand>(
                            value: _draft.walkingBand,
                            options: {
                              WalkingBand.short: _text(
                                widget.language,
                                ko: '짧게',
                                en: 'Short',
                                ja: '短め',
                                zhHans: '较短',
                                zhHant: '較短',
                              ),
                              WalkingBand.medium: _text(
                                widget.language,
                                ko: '보통',
                                en: 'Medium',
                                ja: '普通',
                                zhHans: '适中',
                                zhHant: '適中',
                              ),
                              WalkingBand.long: _text(
                                widget.language,
                                ko: '오래',
                                en: 'Long',
                                ja: '長め',
                                zhHans: '较长',
                                zhHant: '較長',
                              ),
                            },
                            onChanged: (value) => setState(
                              () =>
                                  _draft = _draft.copyWith(walkingBand: value),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SectionTitle(
                    title: _text(
                      widget.language,
                      ko: '관심사',
                      en: 'Interests',
                      ja: '興味',
                      zhHans: '兴趣',
                      zhHant: '興趣',
                    ),
                    caption: _text(
                      widget.language,
                      ko: '최대 5개',
                      en: 'Up to 5',
                      ja: '最大5つ',
                      zhHans: '最多 5 个',
                      zhHant: '最多 5 個',
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final interest in TravelInterest.values)
                        _InterestChip(
                          interest: interest,
                          language: widget.language,
                          selected: _draft.interests.contains(interest),
                          onSelected: (_) => _toggleInterest(interest),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _SectionTitle(
                    title: _text(
                      widget.language,
                      ko: '상세 취향',
                      en: 'Detailed preferences',
                      ja: '詳細設定',
                      zhHans: '详细偏好',
                      zhHant: '詳細偏好',
                    ),
                  ),
                  _Panel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _PreferenceMenuRow(
                          key: const ValueKey('style-preferences-entry'),
                          icon: Icons.explore_outlined,
                          color: const Color(0xFF148467),
                          title: _text(
                            widget.language,
                            ko: '여행 스타일과 동행',
                            en: 'Travel style and companions',
                            ja: '旅行スタイルと同行者',
                            zhHans: '旅行风格与同行者',
                            zhHant: '旅行風格與同行者',
                          ),
                          subtitle: _styleSummary(widget.language, _draft),
                          onTap: () => _openDetail(
                            (value) => StylePreferencesPage(
                              language: widget.language,
                              initialValue: value,
                            ),
                          ),
                        ),
                        const _PanelDivider(indent: 58),
                        _PreferenceMenuRow(
                          key: const ValueKey('food-preferences-entry'),
                          icon: Icons.restaurant_outlined,
                          color: const Color(0xFFE24A3B),
                          title: _text(
                            widget.language,
                            ko: '음식과 식이 제약',
                            en: 'Food and dietary needs',
                            ja: '食事と食事制限',
                            zhHans: '饮食与饮食限制',
                            zhHant: '飲食與飲食限制',
                          ),
                          subtitle: _foodSummary(widget.language, _draft),
                          onTap: () => _openDetail(
                            (value) => FoodPreferencesPage(
                              language: widget.language,
                              initialValue: value,
                            ),
                          ),
                        ),
                        const _PanelDivider(indent: 58),
                        _PreferenceMenuRow(
                          key: const ValueKey('mobility-preferences-entry'),
                          icon: Icons.accessible_forward_outlined,
                          color: const Color(0xFF148467),
                          title: _text(
                            widget.language,
                            ko: '이동·접근성',
                            en: 'Mobility and accessibility',
                            ja: '移動・アクセシビリティ',
                            zhHans: '出行与无障碍',
                            zhHant: '移動與無障礙',
                          ),
                          subtitle: _mobilitySummary(widget.language, _draft),
                          onTap: () => _openDetail(
                            (value) => MobilityPreferencesPage(
                              language: widget.language,
                              initialValue: value,
                            ),
                          ),
                        ),
                        const _PanelDivider(indent: 58),
                        _PreferenceMenuRow(
                          key: const ValueKey('budget-preferences-entry'),
                          icon: Icons.account_balance_wallet_outlined,
                          color: const Color(0xFF7A56C2),
                          title: _text(
                            widget.language,
                            ko: '예산과 운영 조건',
                            en: 'Budget and timing',
                            ja: '予算と時間条件',
                            zhHans: '预算与时间条件',
                            zhHant: '預算與時間條件',
                          ),
                          subtitle: _budgetSummary(widget.language, _draft),
                          onTap: () => _openDetail(
                            (value) => BudgetPreferencesPage(
                              language: widget.language,
                              initialValue: value,
                            ),
                          ),
                        ),
                        const _PanelDivider(indent: 58),
                        _PreferenceMenuRow(
                          key: const ValueKey('docent-preferences-entry'),
                          icon: Icons.headphones_outlined,
                          color: const Color(0xFF0B67D8),
                          title: _text(
                            widget.language,
                            ko: '도슨트와 언어',
                            en: 'Docent and language',
                            ja: 'ガイドと表示',
                            zhHans: '导览与语言',
                            zhHant: '導覽與語言',
                          ),
                          subtitle: _docentSummary(widget.language, _draft),
                          onTap: () => _openDetail(
                            (value) => DocentPreferencesPage(
                              language: widget.language,
                              initialValue: value,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _InfoNotice(
                    icon: Icons.phonelink_lock_outlined,
                    text: _text(
                      widget.language,
                      ko: '지금은 이 기기에만 저장돼요. 계정 동기화는 준비가 끝난 뒤 별도로 안내할게요.',
                      en: 'Saved on this device for now. Account sync will be offered separately when ready.',
                      ja: '現在はこの端末にのみ保存されます。アカウント同期は準備後に別途ご案内します。',
                      zhHans: '目前仅保存在此设备上。账户同步准备好后会另行提示。',
                      zhHant: '目前僅儲存在此裝置上。帳戶同步準備好後會另行提示。',
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: _loading
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  height: LalaVisualTokens.actionHeight,
                  child: FilledButton.icon(
                    key: const ValueKey('travel-preferences-save'),
                    onPressed: _dirty && !_saving ? _save : null,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      _text(
                        widget.language,
                        ko: '저장',
                        en: 'Save',
                        ja: '保存',
                        zhHans: '保存',
                        zhHant: '儲存',
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: LalaVisualColors.primaryBlue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: LalaVisualColors.disabledFill,
                      disabledForegroundColor: LalaVisualColors.disabledInk,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          LalaVisualTokens.controlRadius,
                        ),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class StylePreferencesPage extends StatefulWidget {
  const StylePreferencesPage({
    super.key,
    required this.language,
    required this.initialValue,
  });

  final String language;
  final TravelPreferences initialValue;

  @override
  State<StylePreferencesPage> createState() => _StylePreferencesPageState();
}

class _StylePreferencesPageState extends State<StylePreferencesPage> {
  late TravelPreferences _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialValue;
  }

  void _toggleStyle(TravelStyle value) {
    final next = <TravelStyle>{..._draft.travelStyles};
    if (!next.remove(value)) {
      if (next.length == TravelPreferences.maxTravelStyles) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text(
                widget.language,
                ko: '여행 스타일은 최대 3개까지 선택할 수 있어요.',
                en: 'Choose up to three travel styles.',
                ja: '旅行スタイルは3つまで選べます。',
                zhHans: '最多可选择 3 种旅行风格。',
                zhHant: '最多可選擇 3 種旅行風格。',
              ),
            ),
          ),
        );
        return;
      }
      next.add(value);
    }
    setState(() => _draft = _draft.copyWith(travelStyles: next));
  }

  @override
  Widget build(BuildContext context) {
    return _DetailScaffold(
      title: _text(
        widget.language,
        ko: '여행 스타일과 동행',
        en: 'Style and companions',
        ja: 'スタイルと同行者',
        zhHans: '风格与同行者',
        zhHant: '風格與同行者',
      ),
      saveLabel: _doneLabel(widget.language),
      onSave: () => Navigator.pop(context, _draft),
      children: [
        _SectionTitle(
          title: _text(
            widget.language,
            ko: '끌리는 여행 방식',
            en: 'Travel styles',
            ja: '好きな旅行スタイル',
            zhHans: '喜欢的旅行风格',
            zhHant: '喜歡的旅行風格',
          ),
          caption: _text(
            widget.language,
            ko: '최대 3개',
            en: 'Up to 3',
            ja: '最大3つ',
            zhHans: '最多 3 个',
            zhHant: '最多 3 個',
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in TravelStyle.values)
              FilterChip(
                key: ValueKey('travel-style-${value.name}'),
                label: Text(_travelStyleLabel(widget.language, value)),
                selected: _draft.travelStyles.contains(value),
                onSelected: (_) => _toggleStyle(value),
                selectedColor: const Color(0xFF148467),
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  color: _draft.travelStyles.contains(value)
                      ? Colors.white
                      : LalaVisualColors.ink,
                  fontWeight: FontWeight.w800,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: _draft.travelStyles.contains(value)
                        ? const Color(0xFF148467)
                        : LalaVisualColors.line,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _SectionTitle(
          title: _text(
            widget.language,
            ko: '누구와 가나요?',
            en: 'Who do you travel with?',
            ja: '誰と旅行しますか？',
            zhHans: '和谁一起旅行？',
            zhHant: '和誰一起旅行？',
          ),
        ),
        _EnumChips<TravelCompanion>(
          values: TravelCompanion.values,
          selected: _draft.companions,
          label: (value) => _companionLabel(widget.language, value),
          onChanged: (next) =>
              setState(() => _draft = _draft.copyWith(companions: next)),
        ),
        const SizedBox(height: 24),
        _SectionTitle(
          title: _text(
            widget.language,
            ko: '환경 선호',
            en: 'Environment',
            ja: '環境の好み',
            zhHans: '环境偏好',
            zhHant: '環境偏好',
          ),
        ),
        _Panel(
          child: Column(
            children: [
              _LabeledControl(
                label: _text(
                  widget.language,
                  ko: '실내·야외',
                  en: 'Indoor or outdoor',
                  ja: '屋内・屋外',
                  zhHans: '室内或户外',
                  zhHant: '室內或戶外',
                ),
                child: _SegmentedChoice<IndoorOutdoorPreference>(
                  value: _draft.indoorOutdoorPreference,
                  options: {
                    IndoorOutdoorPreference.indoor: _text(
                      widget.language,
                      ko: '실내',
                      en: 'Indoor',
                      ja: '屋内',
                      zhHans: '室内',
                      zhHant: '室內',
                    ),
                    IndoorOutdoorPreference.balanced: _text(
                      widget.language,
                      ko: '균형',
                      en: 'Balanced',
                      ja: 'バランス',
                      zhHans: '均衡',
                      zhHant: '均衡',
                    ),
                    IndoorOutdoorPreference.outdoor: _text(
                      widget.language,
                      ko: '야외',
                      en: 'Outdoor',
                      ja: '屋外',
                      zhHans: '户外',
                      zhHant: '戶外',
                    ),
                  },
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(
                      indoorOutdoorPreference: value,
                    ),
                  ),
                ),
              ),
              const _PanelDivider(),
              _LabeledControl(
                label: _text(
                  widget.language,
                  ko: '날씨 변화 민감도',
                  en: 'Weather sensitivity',
                  ja: '天候変化への感度',
                  zhHans: '天气敏感度',
                  zhHant: '天氣敏感度',
                ),
                child: _SegmentedChoice<WeatherSensitivity>(
                  value: _draft.weatherSensitivity,
                  options: {
                    WeatherSensitivity.low: _text(
                      widget.language,
                      ko: '낮음',
                      en: 'Low',
                      ja: '低い',
                      zhHans: '低',
                      zhHant: '低',
                    ),
                    WeatherSensitivity.medium: _text(
                      widget.language,
                      ko: '보통',
                      en: 'Medium',
                      ja: '普通',
                      zhHans: '中',
                      zhHant: '中',
                    ),
                    WeatherSensitivity.high: _text(
                      widget.language,
                      ko: '높음',
                      en: 'High',
                      ja: '高い',
                      zhHans: '高',
                      zhHant: '高',
                    ),
                  },
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(weatherSensitivity: value),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class FoodPreferencesPage extends StatefulWidget {
  const FoodPreferencesPage({
    super.key,
    required this.language,
    required this.initialValue,
  });

  final String language;
  final TravelPreferences initialValue;

  @override
  State<FoodPreferencesPage> createState() => _FoodPreferencesPageState();
}

class _FoodPreferencesPageState extends State<FoodPreferencesPage> {
  late TravelPreferences _draft;
  late final TextEditingController _avoidController;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialValue;
    _avoidController = TextEditingController(text: _draft.avoidIngredients);
  }

  @override
  void dispose() {
    _avoidController.dispose();
    super.dispose();
  }

  void _toggleCuisine(FoodCuisine value) {
    final next = <FoodCuisine>{..._draft.cuisines};
    if (!next.remove(value)) {
      if (next.length == TravelPreferences.maxCuisines) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text(
                widget.language,
                ko: '음식 취향은 최대 4개까지 선택할 수 있어요.',
                en: 'Choose up to four food styles.',
                ja: '料理の好みは4つまで選べます。',
                zhHans: '最多可选择 4 种饮食偏好。',
                zhHant: '最多可選擇 4 種飲食偏好。',
              ),
            ),
          ),
        );
        return;
      }
      next.add(value);
    }
    setState(() => _draft = _draft.copyWith(cuisines: next));
  }

  @override
  Widget build(BuildContext context) {
    return _DetailScaffold(
      title: _text(
        widget.language,
        ko: '음식과 식이 제약',
        en: 'Food and dietary needs',
        ja: '食事と食事制限',
        zhHans: '饮食与饮食限制',
        zhHant: '飲食與飲食限制',
      ),
      saveLabel: _doneLabel(widget.language),
      onSave: () {
        Navigator.of(
          context,
        ).pop(_draft.copyWith(avoidIngredients: _avoidController.text));
      },
      children: [
        _SectionTitle(
          title: _text(
            widget.language,
            ko: '좋아하는 음식',
            en: 'Favorite food styles',
            ja: '好きな料理',
            zhHans: '喜欢的饮食',
            zhHant: '喜歡的飲食',
          ),
          caption: _text(
            widget.language,
            ko: '최대 4개',
            en: 'Up to 4',
            ja: '最大4つ',
            zhHans: '最多 4 个',
            zhHant: '最多 4 個',
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in FoodCuisine.values)
              FilterChip(
                key: ValueKey('food-cuisine-${value.name}'),
                label: Text(_foodCuisineLabel(widget.language, value)),
                avatar: Icon(
                  _foodCuisineIcon(value),
                  size: 18,
                  color: _draft.cuisines.contains(value)
                      ? Colors.white
                      : const Color(0xFFE24A3B),
                ),
                selected: _draft.cuisines.contains(value),
                onSelected: (_) => _toggleCuisine(value),
                selectedColor: const Color(0xFFE24A3B),
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  color: _draft.cuisines.contains(value)
                      ? Colors.white
                      : LalaVisualColors.ink,
                  fontWeight: FontWeight.w800,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: _draft.cuisines.contains(value)
                        ? const Color(0xFFE24A3B)
                        : LalaVisualColors.line,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _SectionTitle(
          title: _text(
            widget.language,
            ko: '새로운 음식',
            en: 'New food comfort',
            ja: '新しい料理',
            zhHans: '尝试新食物',
            zhHant: '嘗試新食物',
          ),
        ),
        _Panel(
          child: _SegmentedChoice<FoodAdventure>(
            value: _draft.foodAdventure,
            options: {
              FoodAdventure.familiar: _text(
                widget.language,
                ko: '익숙하게',
                en: 'Familiar',
                ja: '慣れた味',
                zhHans: '熟悉',
                zhHant: '熟悉',
              ),
              FoodAdventure.balanced: _text(
                widget.language,
                ko: '반반',
                en: 'Mix',
                ja: '半々',
                zhHans: '各半',
                zhHant: '各半',
              ),
              FoodAdventure.adventurous: _text(
                widget.language,
                ko: '적극 탐험',
                en: 'Explore',
                ja: '冒険',
                zhHans: '探索',
                zhHant: '探索',
              ),
            },
            onChanged: (value) =>
                setState(() => _draft = _draft.copyWith(foodAdventure: value)),
          ),
        ),
        const SizedBox(height: 24),
        _SectionTitle(
          title: _text(
            widget.language,
            ko: '반드시 지켜야 해요',
            en: 'Must follow',
            ja: '必ず守る条件',
            zhHans: '必须遵守',
            zhHant: '必須遵守',
          ),
        ),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(
                  widget.language,
                  ko: '식이 방식',
                  en: 'Dietary modes',
                  ja: '食事方式',
                  zhHans: '饮食方式',
                  zhHant: '飲食方式',
                ),
                style: _controlLabelStyle,
              ),
              const SizedBox(height: 10),
              _EnumChips<DietaryMode>(
                values: DietaryMode.values,
                selected: _draft.dietaryModes,
                label: (value) => _dietaryLabel(widget.language, value),
                onChanged: (next) => setState(
                  () => _draft = _draft.copyWith(dietaryModes: next),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _text(
                  widget.language,
                  ko: '알레르기',
                  en: 'Allergens',
                  ja: 'アレルギー',
                  zhHans: '过敏原',
                  zhHant: '過敏原',
                ),
                style: _controlLabelStyle,
              ),
              const SizedBox(height: 10),
              _EnumChips<Allergen>(
                values: Allergen.values,
                selected: _draft.allergens,
                label: (value) => _allergenLabel(widget.language, value),
                onChanged: (next) =>
                    setState(() => _draft = _draft.copyWith(allergens: next)),
              ),
              const SizedBox(height: 20),
              TextField(
                key: const ValueKey('avoid-ingredients-field'),
                controller: _avoidController,
                maxLength: TravelPreferences.maxAvoidIngredientsLength,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: _text(
                    widget.language,
                    ko: '못 먹는 재료',
                    en: 'Ingredients to avoid',
                    ja: '避けたい食材',
                    zhHans: '不能食用的食材',
                    zhHant: '不能食用的食材',
                  ),
                  hintText: _text(
                    widget.language,
                    ko: '예: 고수, 생굴',
                    en: 'e.g. cilantro, raw oysters',
                    ja: '例：パクチー、生牡蠣',
                    zhHans: '例如：香菜、生蚝',
                    zhHant: '例如：香菜、生蠔',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _InfoNotice(
          icon: Icons.info_outline,
          text: _text(
            widget.language,
            ko: '추천 정확도를 위한 참고 정보예요. 알레르기와 식이 조건은 주문 전에 매장에 직접 확인해 주세요.',
            en: 'These settings guide recommendations. Confirm allergies and dietary needs directly with the venue before ordering.',
            ja: 'おすすめの参考情報です。アレルギーや食事条件は注文前に店舗へ直接ご確認ください。',
            zhHans: '这些设置仅用于辅助推荐。点餐前请直接向商家确认过敏与饮食要求。',
            zhHant: '這些設定僅用於輔助推薦。點餐前請直接向店家確認過敏與飲食需求。',
          ),
        ),
      ],
    );
  }
}

class MobilityPreferencesPage extends StatefulWidget {
  const MobilityPreferencesPage({
    super.key,
    required this.language,
    required this.initialValue,
  });

  final String language;
  final TravelPreferences initialValue;

  @override
  State<MobilityPreferencesPage> createState() =>
      _MobilityPreferencesPageState();
}

class _MobilityPreferencesPageState extends State<MobilityPreferencesPage> {
  late TravelPreferences _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return _DetailScaffold(
      title: _text(
        widget.language,
        ko: '이동·접근성',
        en: 'Mobility and accessibility',
        ja: '移動・アクセシビリティ',
        zhHans: '出行与无障碍',
        zhHant: '移動與無障礙',
      ),
      saveLabel: _doneLabel(widget.language),
      onSave: () => Navigator.pop(context, _draft),
      children: [
        _SectionTitle(
          title: _text(
            widget.language,
            ko: '선호 이동 수단',
            en: 'Preferred transport',
            ja: '移動手段',
            zhHans: '首选交通方式',
            zhHant: '偏好交通方式',
          ),
        ),
        _EnumChips<TransportMode>(
          values: TransportMode.values,
          selected: _draft.transportModes,
          label: (value) => _transportLabel(widget.language, value),
          onChanged: (next) =>
              setState(() => _draft = _draft.copyWith(transportModes: next)),
        ),
        const SizedBox(height: 24),
        _SectionTitle(
          title: _text(
            widget.language,
            ko: '이동 범위',
            en: 'Travel range',
            ja: '移動範囲',
            zhHans: '出行范围',
            zhHant: '移動範圍',
          ),
        ),
        _Panel(
          child: Column(
            children: [
              _LabeledControl(
                label: _text(
                  widget.language,
                  ko: '편도 이동',
                  en: 'One-way travel',
                  ja: '片道移動',
                  zhHans: '单程时间',
                  zhHant: '單程時間',
                ),
                child: _IntChips(
                  values: const [15, 30, 60, 90],
                  selected: _draft.maxOneWayMinutes,
                  suffix: _minuteSuffix(widget.language),
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(maxOneWayMinutes: value),
                  ),
                ),
              ),
              const _PanelDivider(),
              _LabeledControl(
                label: _text(
                  widget.language,
                  ko: '최대 환승',
                  en: 'Max transfers',
                  ja: '最大乗換',
                  zhHans: '最多换乘',
                  zhHant: '最多轉乘',
                ),
                child: _IntChips(
                  values: const [0, 1, 2, 3],
                  selected: _draft.maxTransfers,
                  suffix: _countSuffix(widget.language),
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(maxTransfers: value),
                  ),
                ),
              ),
              const _PanelDivider(),
              _LabeledControl(
                label: _text(
                  widget.language,
                  ko: '휴식 빈도',
                  en: 'Rest frequency',
                  ja: '休憩頻度',
                  zhHans: '休息频率',
                  zhHant: '休息頻率',
                ),
                child: _SegmentedChoice<RestFrequency>(
                  value: _draft.restFrequency,
                  options: {
                    RestFrequency.low: _text(
                      widget.language,
                      ko: '적게',
                      en: 'Low',
                      ja: '少なめ',
                      zhHans: '较少',
                      zhHant: '較少',
                    ),
                    RestFrequency.balanced: _text(
                      widget.language,
                      ko: '보통',
                      en: 'Normal',
                      ja: '普通',
                      zhHans: '适中',
                      zhHant: '適中',
                    ),
                    RestFrequency.frequent: _text(
                      widget.language,
                      ko: '자주',
                      en: 'Often',
                      ja: '多め',
                      zhHans: '频繁',
                      zhHant: '頻繁',
                    ),
                  },
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(restFrequency: value),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _SectionTitle(
          title: _text(
            widget.language,
            ko: '반드시 지켜야 할 접근성',
            en: 'Required accessibility',
            ja: '必要なアクセシビリティ',
            zhHans: '必须满足的无障碍条件',
            zhHant: '必須滿足的無障礙條件',
          ),
        ),
        _Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _PreferenceSwitch(
                title: _text(
                  widget.language,
                  ko: '계단이 없는 동선',
                  en: 'Step-free routes',
                  ja: '段差のないルート',
                  zhHans: '无台阶路线',
                  zhHant: '無台階路線',
                ),
                value: _draft.avoidStairs,
                onChanged: (value) => setState(
                  () => _draft = _draft.copyWith(avoidStairs: value),
                ),
              ),
              const _PanelDivider(indent: 16),
              _PreferenceSwitch(
                title: _text(
                  widget.language,
                  ko: '휠체어 접근',
                  en: 'Wheelchair access',
                  ja: '車椅子対応',
                  zhHans: '轮椅通行',
                  zhHant: '輪椅通行',
                ),
                value: _draft.wheelchairAccess,
                onChanged: (value) => setState(
                  () => _draft = _draft.copyWith(wheelchairAccess: value),
                ),
              ),
              const _PanelDivider(indent: 16),
              _PreferenceSwitch(
                title: _text(
                  widget.language,
                  ko: '유아차 접근',
                  en: 'Stroller access',
                  ja: 'ベビーカー対応',
                  zhHans: '婴儿车通行',
                  zhHant: '嬰兒車通行',
                ),
                value: _draft.strollerAccess,
                onChanged: (value) => setState(
                  () => _draft = _draft.copyWith(strollerAccess: value),
                ),
              ),
              const _PanelDivider(indent: 16),
              _PreferenceSwitch(
                title: _text(
                  widget.language,
                  ko: '확인된 접근성 정보만',
                  en: 'Verified accessibility only',
                  ja: '確認済み情報のみ',
                  zhHans: '仅使用已验证信息',
                  zhHant: '僅使用已驗證資訊',
                ),
                subtitle: _text(
                  widget.language,
                  ko: '정보가 없는 장소는 추천에서 제외해요',
                  en: 'Exclude places without accessibility evidence',
                  ja: '情報がない場所はおすすめから除外します',
                  zhHans: '排除没有无障碍依据的地点',
                  zhHant: '排除沒有無障礙依據的地點',
                ),
                value: _draft.verifiedAccessibilityOnly,
                onChanged: (value) => setState(
                  () => _draft = _draft.copyWith(
                    verifiedAccessibilityOnly: value,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class BudgetPreferencesPage extends StatefulWidget {
  const BudgetPreferencesPage({
    super.key,
    required this.language,
    required this.initialValue,
  });

  final String language;
  final TravelPreferences initialValue;

  @override
  State<BudgetPreferencesPage> createState() => _BudgetPreferencesPageState();
}

class _BudgetPreferencesPageState extends State<BudgetPreferencesPage> {
  late TravelPreferences _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return _DetailScaffold(
      title: _text(
        widget.language,
        ko: '예산과 운영 조건',
        en: 'Budget and timing',
        ja: '予算と時間条件',
        zhHans: '预算与时间条件',
        zhHant: '預算與時間條件',
      ),
      saveLabel: _doneLabel(widget.language),
      onSave: () => Navigator.pop(context, _draft),
      children: [
        _SectionTitle(
          title: _text(
            widget.language,
            ko: '여행 운영 방식',
            en: 'Trip operations',
            ja: '旅行の進め方',
            zhHans: '行程方式',
            zhHant: '行程方式',
          ),
        ),
        _Panel(
          child: Column(
            children: [
              _LabeledControl(
                label: _text(
                  widget.language,
                  ko: '예산',
                  en: 'Budget',
                  ja: '予算',
                  zhHans: '预算',
                  zhHant: '預算',
                ),
                child: _SegmentedChoice<BudgetBand>(
                  value: _draft.budgetBand,
                  options: {
                    BudgetBand.value: _text(
                      widget.language,
                      ko: '가성비',
                      en: 'Value',
                      ja: 'お得',
                      zhHans: '实惠',
                      zhHant: '實惠',
                    ),
                    BudgetBand.balanced: _text(
                      widget.language,
                      ko: '균형',
                      en: 'Balanced',
                      ja: 'バランス',
                      zhHans: '均衡',
                      zhHant: '均衡',
                    ),
                    BudgetBand.special: _text(
                      widget.language,
                      ko: '특별하게',
                      en: 'Special',
                      ja: '特別',
                      zhHans: '特别',
                      zhHant: '特別',
                    ),
                  },
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(budgetBand: value),
                  ),
                ),
              ),
              const _PanelDivider(),
              _LabeledControl(
                label: _text(
                  widget.language,
                  ko: '대기 시간 상한',
                  en: 'Maximum wait',
                  ja: '最大待ち時間',
                  zhHans: '最长等待',
                  zhHant: '最長等待',
                ),
                child: _IntChips(
                  values: const [10, 20, 40, 60],
                  selected: _draft.maxWaitMinutes,
                  suffix: _minuteSuffix(widget.language),
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(maxWaitMinutes: value),
                  ),
                ),
              ),
              const _PanelDivider(),
              _LabeledControl(
                label: _text(
                  widget.language,
                  ko: '선호 시간대',
                  en: 'Preferred time',
                  ja: '好きな時間帯',
                  zhHans: '偏好时段',
                  zhHant: '偏好時段',
                ),
                child: _SegmentedChoice<DayRhythm>(
                  value: _draft.dayRhythm,
                  options: {
                    DayRhythm.morning: _text(
                      widget.language,
                      ko: '아침',
                      en: 'Morning',
                      ja: '朝',
                      zhHans: '早晨',
                      zhHant: '早晨',
                    ),
                    DayRhythm.daytime: _text(
                      widget.language,
                      ko: '낮',
                      en: 'Day',
                      ja: '昼',
                      zhHans: '白天',
                      zhHant: '白天',
                    ),
                    DayRhythm.night: _text(
                      widget.language,
                      ko: '야간',
                      en: 'Night',
                      ja: '夜',
                      zhHans: '夜间',
                      zhHant: '夜間',
                    ),
                  },
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(dayRhythm: value),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          padding: EdgeInsets.zero,
          child: _PreferenceSwitch(
            title: _text(
              widget.language,
              ko: '휴무·마감 임박 장소 제외',
              en: 'Exclude closed or closing-soon places',
              ja: '休業・閉店間近を除外',
              zhHans: '排除休息或即将关门的地点',
              zhHant: '排除休息或即將關門的地點',
            ),
            subtitle: _text(
              widget.language,
              ko: '운영 정보가 확인된 경우에만 적용해요',
              en: 'Applied only when operating hours are verified',
              ja: '営業時間が確認できる場合のみ適用します',
              zhHans: '仅在营业信息已验证时应用',
              zhHant: '僅在營業資訊已驗證時套用',
            ),
            value: _draft.excludeClosingSoon,
            onChanged: (value) => setState(
              () => _draft = _draft.copyWith(excludeClosingSoon: value),
            ),
          ),
        ),
      ],
    );
  }
}

class DocentPreferencesPage extends StatefulWidget {
  const DocentPreferencesPage({
    super.key,
    required this.language,
    required this.initialValue,
  });

  final String language;
  final TravelPreferences initialValue;

  @override
  State<DocentPreferencesPage> createState() => _DocentPreferencesPageState();
}

class _DocentPreferencesPageState extends State<DocentPreferencesPage> {
  late TravelPreferences _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return _DetailScaffold(
      title: _text(
        widget.language,
        ko: '도슨트와 언어',
        en: 'Docent and language',
        ja: 'ガイドと表示',
        zhHans: '导览与语言',
        zhHant: '導覽與語言',
      ),
      saveLabel: _doneLabel(widget.language),
      onSave: () => Navigator.pop(context, _draft),
      children: [
        _SectionTitle(
          title: _text(
            widget.language,
            ko: '설명 방식',
            en: 'Narration style',
            ja: '説明スタイル',
            zhHans: '讲解方式',
            zhHant: '講解方式',
          ),
        ),
        _Panel(
          child: Column(
            children: [
              _LabeledControl(
                label: _text(
                  widget.language,
                  ko: '설명 깊이',
                  en: 'Detail level',
                  ja: '説明の深さ',
                  zhHans: '讲解深度',
                  zhHant: '講解深度',
                ),
                child: _SegmentedChoice<DocentDepth>(
                  value: _draft.docentDepth,
                  options: {
                    DocentDepth.short: _text(
                      widget.language,
                      ko: '짧게',
                      en: 'Short',
                      ja: '短く',
                      zhHans: '简短',
                      zhHant: '簡短',
                    ),
                    DocentDepth.standard: _text(
                      widget.language,
                      ko: '보통',
                      en: 'Standard',
                      ja: '標準',
                      zhHans: '标准',
                      zhHant: '標準',
                    ),
                    DocentDepth.deep: _text(
                      widget.language,
                      ko: '깊게',
                      en: 'Deep',
                      ja: '詳しく',
                      zhHans: '深入',
                      zhHant: '深入',
                    ),
                  },
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(docentDepth: value),
                  ),
                ),
              ),
              const _PanelDivider(),
              _LabeledControl(
                label: _text(
                  widget.language,
                  ko: '음성 속도',
                  en: 'Speech speed',
                  ja: '音声速度',
                  zhHans: '语速',
                  zhHant: '語速',
                ),
                child: _SegmentedChoice<double>(
                  value: _draft.narrationSpeed,
                  options: {0.8: '0.8x', 1.0: '1.0x', 1.2: '1.2x'},
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(narrationSpeed: value),
                  ),
                ),
              ),
              const _PanelDivider(),
              _LabeledControl(
                label: _text(
                  widget.language,
                  ko: '장소명 표시',
                  en: 'Place names',
                  ja: '場所名表示',
                  zhHans: '地点名称',
                  zhHant: '地點名稱',
                ),
                child: _SegmentedChoice<PlaceNameMode>(
                  value: _draft.placeNameMode,
                  options: {
                    PlaceNameMode.localized: _text(
                      widget.language,
                      ko: '번역명',
                      en: 'Localized',
                      ja: '翻訳名',
                      zhHans: '译名',
                      zhHant: '譯名',
                    ),
                    PlaceNameMode.localizedWithKorean: _text(
                      widget.language,
                      ko: '번역+한국어',
                      en: '+ Korean',
                      ja: '+ 韓国語',
                      zhHans: '+ 韩文',
                      zhHant: '+ 韓文',
                    ),
                    PlaceNameMode.korean: _text(
                      widget.language,
                      ko: '한국어',
                      en: 'Korean',
                      ja: '韓国語',
                      zhHans: '韩文',
                      zhHant: '韓文',
                    ),
                  },
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(placeNameMode: value),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _PreferenceSwitch(
                title: _text(
                  widget.language,
                  ko: '음성 자동 재생',
                  en: 'Autoplay narration',
                  ja: '音声を自動再生',
                  zhHans: '自动播放讲解',
                  zhHant: '自動播放導覽',
                ),
                subtitle: _text(
                  widget.language,
                  ko: '기본값은 꺼짐이며 실제 음성이 있을 때만 재생해요',
                  en: 'Off by default; plays only when real audio is available',
                  ja: '初期設定はオフ。実際の音声がある場合のみ再生します',
                  zhHans: '默认关闭，仅在有真实音频时播放',
                  zhHant: '預設關閉，僅在有真實音訊時播放',
                ),
                value: _draft.docentAutoplay,
                onChanged: (value) => setState(
                  () => _draft = _draft.copyWith(docentAutoplay: value),
                ),
              ),
              const _PanelDivider(indent: 16),
              _PreferenceSwitch(
                title: _text(
                  widget.language,
                  ko: '장소를 옮겨도 이어 듣기',
                  en: 'Continue between places',
                  ja: '場所を移動しても続ける',
                  zhHans: '切换地点后继续播放',
                  zhHant: '切換地點後繼續播放',
                ),
                value: _draft.continueNarration,
                onChanged: (value) => setState(
                  () => _draft = _draft.copyWith(continueNarration: value),
                ),
              ),
              const _PanelDivider(indent: 16),
              _PreferenceSwitch(
                title: _text(
                  widget.language,
                  ko: '한국어 발음 도움',
                  en: 'Korean pronunciation help',
                  ja: '韓国語の発音ガイド',
                  zhHans: '韩语发音帮助',
                  zhHant: '韓語發音協助',
                ),
                value: _draft.pronunciationHelp,
                onChanged: (value) => setState(
                  () => _draft = _draft.copyWith(pronunciationHelp: value),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({
    required this.title,
    required this.saveLabel,
    required this.onSave,
    required this.children,
  });

  final String title;
  final String saveLabel;
  final VoidCallback onSave;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LalaVisualColors.surface,
      appBar: AppBar(
        backgroundColor: LalaVisualColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(title),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: children,
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: SizedBox(
          height: LalaVisualTokens.actionHeight,
          child: FilledButton(
            key: const ValueKey('preference-detail-apply'),
            onPressed: onSave,
            style: FilledButton.styleFrom(
              backgroundColor: LalaVisualColors.primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  LalaVisualTokens.controlRadius,
                ),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            child: Text(saveLabel),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        border: Border.all(color: LalaVisualColors.line),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.caption});

  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: LalaVisualColors.ink,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (caption != null)
            Text(
              caption!,
              style: const TextStyle(
                color: LalaVisualColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _LabeledControl extends StatelessWidget {
  const _LabeledControl({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: _controlLabelStyle),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _SegmentedChoice<T> extends StatelessWidget {
  const _SegmentedChoice({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          for (final entry in options.entries)
            Expanded(
              child: Semantics(
                selected: entry.key == value,
                button: true,
                child: InkWell(
                  onTap: () => onChanged(entry.key),
                  borderRadius: BorderRadius.circular(6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: entry.key == value
                          ? LalaVisualColors.primaryBlue
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      entry.value,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: entry.key == value
                            ? Colors.white
                            : LalaVisualColors.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreferenceMenuRow extends StatelessWidget {
  const _PreferenceMenuRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 70),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              _LeadingIcon(
                icon: icon,
                color: color,
                background: color.withValues(alpha: 0.10),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: LalaVisualColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: LalaVisualColors.muted,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: LalaVisualColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({
    required this.icon,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _PanelDivider extends StatelessWidget {
  const _PanelDivider({this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Divider(height: 25, indent: indent, color: LalaVisualColors.line);
  }
}

class _PreferenceSwitch extends StatelessWidget {
  const _PreferenceSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      title: Text(
        title,
        style: const TextStyle(
          color: LalaVisualColors.ink,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(
                color: LalaVisualColors.muted,
                fontSize: 12,
                height: 1.3,
              ),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _EnumChips<T> extends StatelessWidget {
  const _EnumChips({
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<T> values;
  final Set<T> selected;
  final String Function(T value) label;
  final ValueChanged<Set<T>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          FilterChip(
            key: ValueKey('enum-${value.toString()}'),
            label: Text(label(value)),
            selected: selected.contains(value),
            onSelected: (_) {
              final next = <T>{...selected};
              if (!next.remove(value)) next.add(value);
              onChanged(next);
            },
            selectedColor: LalaVisualColors.primaryBlue,
            checkmarkColor: Colors.white,
            labelStyle: TextStyle(
              color: selected.contains(value)
                  ? Colors.white
                  : LalaVisualColors.ink,
              fontWeight: FontWeight.w800,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: selected.contains(value)
                    ? LalaVisualColors.primaryBlue
                    : LalaVisualColors.line,
              ),
            ),
          ),
      ],
    );
  }
}

class _IntChips extends StatelessWidget {
  const _IntChips({
    required this.values,
    required this.selected,
    required this.suffix,
    required this.onChanged,
  });

  final List<int> values;
  final int selected;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          ChoiceChip(
            label: Text('$value$suffix'),
            selected: value == selected,
            onSelected: (_) => onChanged(value),
            selectedColor: LalaVisualColors.primaryBlue,
            labelStyle: TextStyle(
              color: value == selected ? Colors.white : LalaVisualColors.ink,
              fontWeight: FontWeight.w800,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: value == selected
                    ? LalaVisualColors.primaryBlue
                    : LalaVisualColors.line,
              ),
            ),
          ),
      ],
    );
  }
}

class _InterestChip extends StatelessWidget {
  const _InterestChip({
    required this.interest,
    required this.language,
    required this.selected,
    required this.onSelected,
  });

  final TravelInterest interest;
  final String language;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final color = _interestColor(interest);
    return FilterChip(
      key: ValueKey('interest-${interest.name}'),
      avatar: Icon(
        _interestIcon(interest),
        size: 18,
        color: selected ? Colors.white : color,
      ),
      label: Text(_interestLabel(language, interest)),
      selected: selected,
      onSelected: onSelected,
      selectedColor: color,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? Colors.white : LalaVisualColors.ink,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: selected ? color : LalaVisualColors.line),
      ),
    );
  }
}

class _InfoNotice extends StatelessWidget {
  const _InfoNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LalaVisualColors.primarySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: LalaVisualColors.primaryBlue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF284E7A),
                height: 1.4,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const TextStyle _controlLabelStyle = TextStyle(
  color: LalaVisualColors.ink,
  fontWeight: FontWeight.w900,
);

String _text(
  String language, {
  required String ko,
  required String en,
  required String ja,
  required String zhHans,
  required String zhHant,
}) => lalaCopyMulti(
  language,
  ko: ko,
  en: en,
  ja: ja,
  zhHans: zhHans,
  zhHant: zhHant,
);

String _doneLabel(String language) => _text(
  language,
  ko: '적용',
  en: 'Apply',
  ja: '適用',
  zhHans: '应用',
  zhHant: '套用',
);

String _minuteSuffix(String language) =>
    normalizeLalaLanguage(language) == 'en' ? ' min' : '분';

String _countSuffix(String language) {
  switch (normalizeLalaLanguage(language)) {
    case 'en':
      return 'x';
    case 'ja':
      return '回';
    case 'zh-Hans':
    case 'zh-Hant':
      return '次';
    default:
      return '회';
  }
}

String _preferenceSummary(String language, TravelPreferences value) {
  final interest = value.interests.isEmpty
      ? _text(
          language,
          ko: '관심사 설정 전',
          en: 'No interests yet',
          ja: '興味は未設定',
          zhHans: '尚未设置兴趣',
          zhHant: '尚未設定興趣',
        )
      : _interestLabel(language, value.interests.first);
  return '${_paceLabel(language, value.pace)} · $interest · '
      '${_walkingLabel(language, value.walkingBand)}';
}

String _foodSummary(String language, TravelPreferences value) {
  final parts = <String>[];
  if (value.cuisines.isNotEmpty) {
    parts.add(_foodCuisineLabel(language, value.cuisines.first));
  }
  if (value.dietaryModes.isNotEmpty || value.allergens.isNotEmpty) {
    parts.add(
      _text(
        language,
        ko: '식이 조건 있음',
        en: 'Dietary needs set',
        ja: '食事条件あり',
        zhHans: '已设置饮食条件',
        zhHant: '已設定飲食條件',
      ),
    );
  }
  return parts.isEmpty
      ? _text(
          language,
          ko: '음식 취향과 필수 조건을 설정해요',
          en: 'Set food tastes and must-follow needs',
          ja: '料理の好みと必須条件を設定',
          zhHans: '设置饮食偏好与必要条件',
          zhHant: '設定飲食偏好與必要條件',
        )
      : parts.join(' · ');
}

String _styleSummary(String language, TravelPreferences value) {
  final style = value.travelStyles.isEmpty
      ? _text(
          language,
          ko: '스타일 설정 전',
          en: 'No style yet',
          ja: 'スタイル未設定',
          zhHans: '尚未设置风格',
          zhHant: '尚未設定風格',
        )
      : _travelStyleLabel(language, value.travelStyles.first);
  final companion = value.companions.isEmpty
      ? _text(
          language,
          ko: '동행 미정',
          en: 'Companion not set',
          ja: '同行者未設定',
          zhHans: '同行者未设置',
          zhHant: '同行者未設定',
        )
      : _companionLabel(language, value.companions.first);
  return '$style · $companion';
}

String _mobilitySummary(String language, TravelPreferences value) {
  final hard =
      value.avoidStairs ||
      value.wheelchairAccess ||
      value.strollerAccess ||
      value.verifiedAccessibilityOnly;
  return '${_walkingLabel(language, value.walkingBand)} · '
      '${value.maxOneWayMinutes}${_minuteSuffix(language)}'
      '${hard ? ' · ${_text(language, ko: '접근성 조건 있음', en: 'Access needs set', ja: 'アクセシビリティ条件あり', zhHans: '已设置无障碍条件', zhHant: '已設定無障礙條件')}' : ''}';
}

String _budgetSummary(String language, TravelPreferences value) =>
    '${_budgetLabel(language, value.budgetBand)} · '
    '${value.maxWaitMinutes}${_minuteSuffix(language)} · '
    '${_dayRhythmLabel(language, value.dayRhythm)}';

String _docentSummary(String language, TravelPreferences value) =>
    '${_docentDepthLabel(language, value.docentDepth)} · '
    '${value.narrationSpeed.toStringAsFixed(1)}x · '
    '${value.docentAutoplay ? _text(language, ko: '자동 재생', en: 'Autoplay', ja: '自動再生', zhHans: '自动播放', zhHant: '自動播放') : _text(language, ko: '직접 재생', en: 'Tap to play', ja: '手動再生', zhHans: '手动播放', zhHant: '手動播放')}';

String _paceLabel(String language, TravelPace value) => switch (value) {
  TravelPace.relaxed => _text(
    language,
    ko: '여유롭게',
    en: 'Relaxed',
    ja: 'ゆったり',
    zhHans: '悠闲',
    zhHant: '悠閒',
  ),
  TravelPace.balanced => _text(
    language,
    ko: '균형 있게',
    en: 'Balanced',
    ja: 'バランス',
    zhHans: '均衡',
    zhHant: '均衡',
  ),
  TravelPace.packed => _text(
    language,
    ko: '알차게',
    en: 'Full',
    ja: '充実',
    zhHans: '充实',
    zhHant: '充實',
  ),
};

String _walkingLabel(String language, WalkingBand value) => switch (value) {
  WalkingBand.short => _text(
    language,
    ko: '걷기 짧게',
    en: 'Short walks',
    ja: '短い徒歩',
    zhHans: '少步行',
    zhHant: '少步行',
  ),
  WalkingBand.medium => _text(
    language,
    ko: '걷기 보통',
    en: 'Moderate walks',
    ja: '徒歩は普通',
    zhHans: '适量步行',
    zhHant: '適量步行',
  ),
  WalkingBand.long => _text(
    language,
    ko: '오래 걷기',
    en: 'Long walks',
    ja: '長い徒歩',
    zhHans: '长距离步行',
    zhHant: '長距離步行',
  ),
};

String _interestLabel(String language, TravelInterest value) {
  final labels = <TravelInterest, List<String>>{
    TravelInterest.localFood: ['로컬 음식', 'Local food', 'ローカル料理', '本地美食', '在地美食'],
    TravelInterest.cafe: ['카페', 'Cafes', 'カフェ', '咖啡馆', '咖啡館'],
    TravelInterest.history: ['전통·역사', 'History', '伝統・歴史', '传统历史', '傳統歷史'],
    TravelInterest.arts: ['미술·공연', 'Arts', '芸術・公演', '艺术演出', '藝術表演'],
    TravelInterest.nature: ['자연', 'Nature', '自然', '自然', '自然'],
    TravelInterest.walk: ['산책', 'Walks', '散歩', '散步', '散步'],
    TravelInterest.night: ['야경', 'Night views', '夜景', '夜景', '夜景'],
    TravelInterest.shopping: ['쇼핑', 'Shopping', '買い物', '购物', '購物'],
    TravelInterest.market: ['시장', 'Markets', '市場', '市场', '市場'],
    TravelInterest.festival: ['축제', 'Festivals', '祭り', '节庆', '節慶'],
    TravelInterest.handsOn: ['체험', 'Hands-on', '体験', '体验', '體驗'],
    TravelInterest.photography: ['사진', 'Photography', '写真', '摄影', '攝影'],
  };
  return _localizedList(language, labels[value]!);
}

IconData _interestIcon(TravelInterest value) => switch (value) {
  TravelInterest.localFood => Icons.restaurant,
  TravelInterest.cafe => Icons.local_cafe_outlined,
  TravelInterest.history => Icons.account_balance_outlined,
  TravelInterest.arts => Icons.palette_outlined,
  TravelInterest.nature => Icons.eco_outlined,
  TravelInterest.walk => Icons.directions_walk,
  TravelInterest.night => Icons.nightlight_outlined,
  TravelInterest.shopping => Icons.shopping_bag_outlined,
  TravelInterest.market => Icons.storefront_outlined,
  TravelInterest.festival => Icons.celebration_outlined,
  TravelInterest.handsOn => Icons.handyman_outlined,
  TravelInterest.photography => Icons.photo_camera_outlined,
};

Color _interestColor(TravelInterest value) => switch (value) {
  TravelInterest.localFood || TravelInterest.market => const Color(0xFFE24A3B),
  TravelInterest.cafe || TravelInterest.photography => const Color(0xFFF08A3E),
  TravelInterest.history || TravelInterest.arts => const Color(0xFF7A56C2),
  TravelInterest.nature || TravelInterest.walk => const Color(0xFF148467),
  TravelInterest.night || TravelInterest.shopping => const Color(0xFF0B67D8),
  TravelInterest.festival || TravelInterest.handsOn => const Color(0xFFB83D75),
};

String _foodCuisineLabel(String language, FoodCuisine value) {
  final labels = <FoodCuisine, List<String>>{
    FoodCuisine.korean: ['한식', 'Korean', '韓国料理', '韩餐', '韓式料理'],
    FoodCuisine.streetFood: ['분식·길거리', 'Street food', '屋台料理', '街头小吃', '街頭小吃'],
    FoodCuisine.cafeDessert: [
      '카페·디저트',
      'Cafe & dessert',
      'カフェ・デザート',
      '咖啡甜点',
      '咖啡甜點',
    ],
    FoodCuisine.marketFood: ['시장 음식', 'Market food', '市場料理', '市场美食', '市場美食'],
    FoodCuisine.worldCuisine: [
      '세계 요리',
      'World cuisine',
      '世界の料理',
      '世界料理',
      '世界料理',
    ],
  };
  return _localizedList(language, labels[value]!);
}

String _travelStyleLabel(String language, TravelStyle value) {
  final labels = <TravelStyle, List<String>>{
    TravelStyle.famous: ['대표 명소', 'Famous sights', '名所', '知名景点', '知名景點'],
    TravelStyle.hiddenLocal: [
      '숨은 동네',
      'Hidden neighborhoods',
      '穴場の街',
      '小众街区',
      '巷弄秘境',
    ],
    TravelStyle.residentFavorite: [
      '주민 추천',
      'Local favorites',
      '住民おすすめ',
      '居民推荐',
      '居民推薦',
    ],
    TravelStyle.newPlaces: ['새로운 곳', 'New places', '新しい場所', '新地点', '新地點'],
    TravelStyle.revisit: ['다시 찾는 곳', 'Familiar returns', '再訪', '重游', '重遊'],
    TravelStyle.spontaneous: ['즉흥 탐색', 'Spontaneous', '気ままな探索', '随性探索', '隨興探索'],
  };
  return _localizedList(language, labels[value]!);
}

String _companionLabel(String language, TravelCompanion value) {
  final labels = <TravelCompanion, List<String>>{
    TravelCompanion.solo: ['혼자', 'Solo', 'ひとり', '独自', '獨自'],
    TravelCompanion.partner: ['연인', 'Partner', '恋人', '伴侣', '伴侶'],
    TravelCompanion.friends: ['친구', 'Friends', '友人', '朋友', '朋友'],
    TravelCompanion.family: ['가족', 'Family', '家族', '家人', '家人'],
    TravelCompanion.children: ['어린이', 'Children', '子ども', '儿童', '兒童'],
    TravelCompanion.senior: ['어르신', 'Senior', 'シニア', '长者', '長者'],
    TravelCompanion.pet: ['반려동물', 'Pet', 'ペット', '宠物', '寵物'],
  };
  return _localizedList(language, labels[value]!);
}

IconData _foodCuisineIcon(FoodCuisine value) => switch (value) {
  FoodCuisine.korean => Icons.rice_bowl_outlined,
  FoodCuisine.streetFood => Icons.tapas_outlined,
  FoodCuisine.cafeDessert => Icons.cake_outlined,
  FoodCuisine.marketFood => Icons.storefront_outlined,
  FoodCuisine.worldCuisine => Icons.public,
};

String _dietaryLabel(String language, DietaryMode value) {
  final labels = <DietaryMode, List<String>>{
    DietaryMode.vegetarian: ['채식', 'Vegetarian', 'ベジタリアン', '素食', '素食'],
    DietaryMode.vegan: ['비건', 'Vegan', 'ヴィーガン', '纯素', '全素'],
    DietaryMode.halal: ['할랄', 'Halal', 'ハラール', '清真', '清真'],
    DietaryMode.kosher: ['코셔', 'Kosher', 'コーシャ', '犹太洁食', '猶太潔食'],
  };
  return _localizedList(language, labels[value]!);
}

String _allergenLabel(String language, Allergen value) {
  final labels = <Allergen, List<String>>{
    Allergen.nuts: ['견과류', 'Nuts', 'ナッツ', '坚果', '堅果'],
    Allergen.shellfish: ['갑각류', 'Shellfish', '甲殻類', '甲壳类', '甲殼類'],
    Allergen.dairy: ['유제품', 'Dairy', '乳製品', '乳制品', '乳製品'],
    Allergen.eggs: ['달걀', 'Eggs', '卵', '鸡蛋', '雞蛋'],
    Allergen.gluten: ['글루텐', 'Gluten', 'グルテン', '麸质', '麩質'],
    Allergen.soy: ['콩', 'Soy', '大豆', '大豆', '大豆'],
  };
  return _localizedList(language, labels[value]!);
}

String _transportLabel(String language, TransportMode value) {
  final labels = <TransportMode, List<String>>{
    TransportMode.walk: ['도보', 'Walk', '徒歩', '步行', '步行'],
    TransportMode.transit: ['대중교통', 'Transit', '公共交通', '公共交通', '大眾運輸'],
    TransportMode.taxi: ['택시', 'Taxi', 'タクシー', '出租车', '計程車'],
    TransportMode.car: ['자가용', 'Car', '車', '自驾', '自駕'],
    TransportMode.bicycle: ['자전거', 'Bicycle', '自転車', '自行车', '自行車'],
  };
  return _localizedList(language, labels[value]!);
}

String _budgetLabel(String language, BudgetBand value) => switch (value) {
  BudgetBand.value => _localizedList(language, [
    '가성비',
    'Value',
    'お得',
    '实惠',
    '實惠',
  ]),
  BudgetBand.balanced => _localizedList(language, [
    '균형 예산',
    'Balanced',
    'バランス',
    '均衡',
    '均衡',
  ]),
  BudgetBand.special => _localizedList(language, [
    '특별한 경험',
    'Special',
    '特別',
    '特别',
    '特別',
  ]),
};

String _dayRhythmLabel(String language, DayRhythm value) => switch (value) {
  DayRhythm.morning => _localizedList(language, [
    '아침형',
    'Morning',
    '朝型',
    '早晨',
    '早晨',
  ]),
  DayRhythm.daytime => _localizedList(language, [
    '낮 중심',
    'Daytime',
    '昼中心',
    '白天',
    '白天',
  ]),
  DayRhythm.night => _localizedList(language, [
    '야간형',
    'Night',
    '夜型',
    '夜间',
    '夜間',
  ]),
};

String _docentDepthLabel(String language, DocentDepth value) => switch (value) {
  DocentDepth.short => _localizedList(language, [
    '짧은 설명',
    'Short',
    '短い説明',
    '简短',
    '簡短',
  ]),
  DocentDepth.standard => _localizedList(language, [
    '보통 설명',
    'Standard',
    '標準',
    '标准',
    '標準',
  ]),
  DocentDepth.deep => _localizedList(language, [
    '깊은 설명',
    'Deep',
    '詳しい説明',
    '深入',
    '深入',
  ]),
};

String _localizedList(String language, List<String> values) {
  return switch (normalizeLalaLanguage(language)) {
    'en' => values[1],
    'ja' => values[2],
    'zh-Hans' => values[3],
    'zh-Hant' => values[4],
    _ => values[0],
  };
}
