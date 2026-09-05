import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../../app/lala_visual_tokens.dart';
import '../../../../shared/l10n/lala_copy.dart';
import '../../../../shared/l10n/multi_language_text.dart';
import '../../../../shared/l10n/place_labels.dart';
import '../../../planner/planner_helpers.dart';

enum InterventionComparisonDecision { keepCurrent, applyAlternative }

class InterventionComparisonArguments {
  const InterventionComparisonArguments({required this.intervention});

  final LalaIntervention intervention;
}

/// S-21: compares one observed intervention with its API-provided alternative.
///
/// The page never mutates the plan directly. It returns a decision to the
/// owning [PlanPage], which can atomically publish and undo the replacement.
class InterventionComparisonPage extends StatelessWidget {
  const InterventionComparisonPage({
    required this.language,
    this.arguments,
    super.key,
  });

  final String language;
  final InterventionComparisonArguments? arguments;

  @override
  Widget build(BuildContext context) {
    final intervention = arguments?.intervention;
    return Scaffold(
      key: const ValueKey('intervention-comparison-page'),
      backgroundColor: LalaVisualColors.surface,
      appBar: AppBar(
        backgroundColor: LalaVisualColors.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          key: const ValueKey('intervention-comparison-back'),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: Text(
          _copy(
            language,
            ko: '상황 변화 비교',
            en: 'Compare plan changes',
            ja: '状況変化を比較',
            zhHans: '比较行程变化',
            zhHant: '比較行程變化',
          ),
        ),
        centerTitle: true,
      ),
      body: intervention == null || !intervention.shouldIntervene
          ? _UnavailableState(language: language)
          : _ComparisonBody(language: language, intervention: intervention),
    );
  }
}

class _ComparisonBody extends StatelessWidget {
  const _ComparisonBody({required this.language, required this.intervention});

  final String language;
  final LalaIntervention intervention;

  @override
  Widget build(BuildContext context) {
    final alternative = intervention.alternativeSlot;
    return SafeArea(
      top: false,
      child: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: <Widget>[
                _ChangeSummary(language: language, intervention: intervention),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final current = _SlotCard(
                      key: const ValueKey('intervention-current-slot'),
                      language: language,
                      label: _copy(
                        language,
                        ko: '현재 일정',
                        en: 'Current plan',
                        ja: '現在のプラン',
                        zhHans: '当前计划',
                        zhHant: '目前計畫',
                      ),
                      slot: intervention.originalSlot,
                      accent: LalaVisualColors.muted,
                    );
                    final proposed = _SlotCard(
                      key: const ValueKey('intervention-alternative-slot'),
                      language: language,
                      label: _copy(
                        language,
                        ko: '추천 대안',
                        en: 'Suggested alternative',
                        ja: 'おすすめの代替案',
                        zhHans: '建议替代方案',
                        zhHant: '建議替代方案',
                      ),
                      slot: alternative,
                      accent: LalaVisualColors.primaryBlue,
                    );
                    if (constraints.maxWidth >= 600) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(child: current),
                          const SizedBox(width: 12),
                          Expanded(child: proposed),
                        ],
                      );
                    }
                    return Column(
                      children: <Widget>[
                        current,
                        const SizedBox(height: 12),
                        proposed,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                _EvidencePanel(language: language, intervention: intervention),
              ],
            ),
          ),
          _BottomActions(
            language: language,
            hasAlternative: alternative != null,
          ),
        ],
      ),
    );
  }
}

class _ChangeSummary extends StatelessWidget {
  const _ChangeSummary({required this.language, required this.intervention});

  final String language;
  final LalaIntervention intervention;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // F-051 hierarchy: one short chip per observable trigger factor so the
    // "why" scans before the prose. Chips come only from the API factor list —
    // an unlabeled factor is dropped, never invented.
    final chipLabels = intervention.triggerFactors
        .map((factor) => _factorChipLabel(factor, language))
        .whereType<String>()
        .toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        border: Border.all(color: const Color(0xFFF4C77D)),
      ),
      child: Semantics(
        container: true,
        label: <String>[
          _triggerLabel(intervention.triggerType, language),
          ...chipLabels,
          intervention.reason,
          if (intervention.recommendedAction.trim().isNotEmpty)
            intervention.recommendedAction,
        ].join(', '),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.change_circle_outlined,
                  color: Color(0xFF9A5B00),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _triggerLabel(intervention.triggerType, language),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF744210),
                    ),
                  ),
                ),
              ],
            ),
            if (chipLabels.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  for (final label in chipLabels)
                    _ConstraintChip(label: label, icon: _factorChipIcon()),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Text(intervention.reason, style: theme.textTheme.bodyLarge),
            if (intervention.recommendedAction.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                intervention.recommendedAction,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: LalaVisualColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.language,
    required this.label,
    required this.slot,
    required this.accent,
    super.key,
  });

  final String language;
  final String label;
  final LalaPlanSlot? slot;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = slot;
    final title = value == null
        ? _copy(
            language,
            ko: '비교할 일정 정보가 없어요',
            en: 'No comparable slot data',
            ja: '比較できる予定情報がありません',
            zhHans: '没有可比较的行程信息',
            zhHant: '沒有可比較的行程資訊',
          )
        : value.place == null
        ? value.title
        : placeDisplayName(value.place!, language);
    // F-051: per-side constraint badges (weather / air quality / closure /
    // indoor-outdoor) from the real slot projections — the same values the
    // plan tile shows. Null projections render no badge (honest empty), so the
    // original card visibly carries the problem states the API reported.
    final closureLabel = value == null
        ? null
        : planSlotClosureStateLabel(value, language);
    final closureKey = value == null
        ? 'unknown'
        : (value.closureState ?? 'unknown').trim().toLowerCase();
    // Shared with the plan tile so balanced never renders as an outdoor claim.
    final indoorOutdoorLabel = value == null
        ? null
        : planSlotIndoorOutdoorLabel(value, language);
    final airQualityLabel = value == null
        ? null
        : planSlotAirQualityBadLabel(value, language);
    final weatherHint = value == null
        ? null
        : singleLanguageText(value.weatherHint ?? '', language);
    final semanticsLabel = <String?>[
      label,
      title,
      if (value != null) _slotTime(value, language),
      closureLabel,
      indoorOutdoorLabel,
      weatherHint,
      airQualityLabel,
      if (value != null) _openingHours(value, language),
      if (value != null) _travelAuthority(value, language),
      value?.recommendationReason,
    ].whereType<String>().join(', ');
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: LalaVisualColors.card,
          borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
          border: Border.all(color: accent.withValues(alpha: 0.38)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: accent,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            if (value != null) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  _ClosureChip(label: closureLabel!, stateKey: closureKey),
                  if (indoorOutdoorLabel != null)
                    _ConstraintChip(
                      label: indoorOutdoorLabel,
                      icon: planSlotIndoorOutdoorIcon(value),
                    ),
                  if (weatherHint != null)
                    _ConstraintChip(
                      label: weatherHint,
                      icon: Icons.cloud_outlined,
                    ),
                  if (airQualityLabel != null)
                    _ConstraintChip(
                      label: airQualityLabel,
                      icon: Icons.warning_amber_rounded,
                      emphasized: true,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _FactRow(
                icon: Icons.schedule_outlined,
                text: _slotTime(value, language),
              ),
              const SizedBox(height: 8),
              _FactRow(
                icon: Icons.storefront_outlined,
                text: _openingHours(value, language),
              ),
              const SizedBox(height: 8),
              _FactRow(
                icon: Icons.directions_walk_outlined,
                text: _travelAuthority(value, language),
              ),
              if ((value.recommendationReason ?? '')
                  .trim()
                  .isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  value.recommendationReason!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: LalaVisualColors.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Open/closed/unknown badge mirroring the plan tile's D4 badge: state color +
/// icon + text (never color-alone), slate chip background tokens.
class _ClosureChip extends StatelessWidget {
  const _ClosureChip({required this.label, required this.stateKey});

  final String label;
  final String stateKey;

  @override
  Widget build(BuildContext context) {
    final color = switch (stateKey) {
      'open' => const Color(0xFF0F766E),
      'closed' => const Color(0xFFC53030),
      _ => const Color(0xFF64748B),
    };
    final icon = switch (stateKey) {
      'open' => Icons.check_circle_outline,
      'closed' => Icons.cancel_outlined,
      _ => Icons.help_outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Neutral constraint chip (indoor/outdoor, weather hint, factor chips) on the
/// documented slate chip tokens. [emphasized] switches to the red marker token
/// for poor-air-quality states — icon + text still carry the meaning.
class _ConstraintChip extends StatelessWidget {
  const _ConstraintChip({
    required this.label,
    required this.icon,
    this.emphasized = false,
  });

  final String label;
  final IconData icon;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final color = emphasized
        ? const Color(0xFFC53030)
        : const Color(0xFF475569);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: emphasized ? const Color(0xFFC53030) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Icon(icon, size: 18, color: LalaVisualColors.muted),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            color: LalaVisualColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class _EvidencePanel extends StatelessWidget {
  const _EvidencePanel({required this.language, required this.intervention});

  final String language;
  final LalaIntervention intervention;

  @override
  Widget build(BuildContext context) {
    final factors = intervention.triggerFactors
        .map((factor) => _factorLabel(factor, language))
        .where((label) => label != null)
        .cast<String>()
        .toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LalaVisualColors.primarySoft,
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _copy(
              language,
              ko: '판단 근거',
              en: 'Decision basis',
              ja: '判断根拠',
              zhHans: '判断依据',
              zhHant: '判斷依據',
            ),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _FactRow(
            icon: Icons.source_outlined,
            text: _sourceLabel(intervention.source, language),
          ),
          const SizedBox(height: 8),
          _FactRow(
            icon: Icons.update_outlined,
            text: _copy(
              language,
              ko: '관측 시각은 이 응답에 포함되지 않았어요.',
              en: 'Observation time is not included in this response.',
              ja: '観測時刻はこの応答に含まれていません。',
              zhHans: '此响应未包含观测时间。',
              zhHant: '此回應未包含觀測時間。',
            ),
          ),
          if (factors.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            ...factors.map(
              (factor) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _FactRow(icon: Icons.check_circle_outline, text: factor),
              ),
            ),
          ],
          const SizedBox(height: 2),
          _FactRow(
            icon: Icons.route_outlined,
            text: intervention.distanceComparison == null
                ? _copy(
                    language,
                    ko: '비교 가능한 이동 거리 근거가 없어요.',
                    en: 'Comparable travel-distance evidence is unavailable.',
                    ja: '比較できる移動距離の根拠はありません。',
                    zhHans: '暂无可比较的出行距离依据。',
                    zhHant: '暫無可比較的移動距離依據。',
                  )
                : _copy(
                    language,
                    ko: '이동 거리 근거가 포함된 제안이에요.',
                    en: 'This suggestion includes travel-distance evidence.',
                    ja: '移動距離の根拠を含む提案です。',
                    zhHans: '此建议包含出行距离依据。',
                    zhHant: '此建議包含移動距離依據。',
                  ),
          ),
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({required this.language, required this.hasAlternative});

  final String language;
  final bool hasAlternative;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      12 + MediaQuery.paddingOf(context).bottom,
    ),
    decoration: const BoxDecoration(
      color: LalaVisualColors.card,
      border: Border(top: BorderSide(color: LalaVisualColors.line)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Failure semantics: a disabled apply must explain itself instead of
        // leaving the user guessing. Honest copy — no invented alternative.
        if (!hasAlternative)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.search_off_rounded,
                  size: 16,
                  color: LalaVisualColors.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _copy(
                      language,
                      ko: '조건에 맞는 대체 장소를 찾지 못했어요. 일정을 유지하거나 다시 만들 수 있어요.',
                      en: 'No matching alternative was found. You can keep the plan or regenerate it.',
                      ja: '条件に合う代替スポットが見つかりませんでした。予定を維持するか、作り直せます。',
                      zhHans: '未找到符合条件的替代地点。您可以保留当前计划或重新生成。',
                      zhHant: '未找到符合條件的替代地點。您可以保留目前計畫或重新產生。',
                    ),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: LalaVisualColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('intervention-keep-current'),
                onPressed: () =>
                    context.pop(InterventionComparisonDecision.keepCurrent),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, LalaVisualTokens.actionHeight),
                ),
                child: Text(
                  _copy(
                    language,
                    ko: '기존 일정 유지',
                    en: 'Keep current',
                    ja: '現在の予定を維持',
                    zhHans: '保留当前计划',
                    zhHant: '保留目前計畫',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                key: const ValueKey('intervention-apply-alternative'),
                onPressed: hasAlternative
                    ? () => context.pop(
                        InterventionComparisonDecision.applyAlternative,
                      )
                    : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, LalaVisualTokens.actionHeight),
                ),
                child: Text(
                  _copy(
                    language,
                    ko: '대안 적용',
                    en: 'Apply alternative',
                    ja: '代替案を適用',
                    zhHans: '应用替代方案',
                    zhHant: '套用替代方案',
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _UnavailableState extends StatelessWidget {
  const _UnavailableState({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.event_available_outlined, size: 42),
          const SizedBox(height: 14),
          Text(
            _copy(
              language,
              ko: '지금 비교할 상황 변화가 없어요.',
              en: 'There is no plan change to compare right now.',
              ja: '現在比較する状況変化はありません。',
              zhHans: '目前没有可比较的行程变化。',
              zhHant: '目前沒有可比較的行程變化。',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}

String _slotTime(LalaPlanSlot slot, String language) {
  if ((slot.startTime ?? '').trim().isNotEmpty) {
    return slot.startTime!;
  }
  return _copy(
    language,
    ko: '시작 시각 미확인',
    en: 'Start time unavailable',
    ja: '開始時刻は未確認',
    zhHans: '开始时间未确认',
    zhHant: '開始時間未確認',
  );
}

String _openingHours(LalaPlanSlot slot, String language) {
  if ((slot.estimatedOpeningHours ?? '').trim().isNotEmpty) {
    return _copy(
      language,
      ko: '${slot.estimatedOpeningHours} (추정)',
      en: '${slot.estimatedOpeningHours} (estimated)',
      ja: '${slot.estimatedOpeningHours}（推定）',
      zhHans: '${slot.estimatedOpeningHours}（估算）',
      zhHant: '${slot.estimatedOpeningHours}（估算）',
    );
  }
  return _copy(
    language,
    ko: '운영 시간 미확인',
    en: 'Opening hours unavailable',
    ja: '営業時間は未確認',
    zhHans: '营业时间未确认',
    zhHant: '營業時間未確認',
  );
}

String _travelAuthority(LalaPlanSlot slot, String language) {
  final minutes = slot.travelTimeFromPreviousMinutes;
  if (minutes != null) {
    return _copy(
      language,
      ko: '이전 장소에서 약 $minutes분',
      en: 'About $minutes min from the previous stop',
      ja: '前の場所から約$minutes分',
      zhHans: '距上一站约 $minutes 分钟',
      zhHant: '距上一站約 $minutes 分鐘',
    );
  }
  return _copy(
    language,
    ko: '이동 시간 근거 미확인',
    en: 'Travel time unavailable',
    ja: '移動時間の根拠は未確認',
    zhHans: '出行时间依据未确认',
    zhHant: '移動時間依據未確認',
  );
}

String _triggerLabel(String? trigger, String language) => switch (trigger) {
  'bad_weather' => _copy(
    language,
    ko: '날씨 변화가 일정에 영향을 줘요',
    en: 'Weather may affect this plan',
    ja: '天候の変化が予定に影響します',
    zhHans: '天气变化可能影响行程',
    zhHant: '天氣變化可能影響行程',
  ),
  'bad_air_quality' => _copy(
    language,
    ko: '미세먼지가 일정에 영향을 줘요',
    en: 'Air quality may affect this plan',
    ja: '大気が予定に影響します',
    zhHans: '空气质量可能影响行程',
    zhHant: '空氣品質可能影響行程',
  ),
  'closure_detected' => _copy(
    language,
    ko: '운영 상태를 다시 확인해야 해요',
    en: 'The opening status needs another look',
    ja: '営業状況を再確認してください',
    zhHans: '需要重新确认营业状态',
    zhHant: '需要重新確認營業狀態',
  ),
  'bad_weather_and_closure' => _copy(
    language,
    ko: '날씨와 운영 상태가 함께 달라졌어요',
    en: 'Weather and opening status both changed',
    ja: '天候と営業状況の両方が変わりました',
    zhHans: '天气与营业状态均有变化',
    zhHant: '天氣與營業狀態均有變化',
  ),
  'bad_weather_and_air_quality' => _copy(
    language,
    ko: '날씨와 미세먼지가 함께 영향을 줘요',
    en: 'Weather and air quality both affect this plan',
    ja: '天候と大気の両方が予定に影響します',
    zhHans: '天气与空气质量均影响行程',
    zhHant: '天氣與空氣品質均影響行程',
  ),
  'bad_air_quality_and_closure' => _copy(
    language,
    ko: '미세먼지와 운영 상태를 함께 확인해야 해요',
    en: 'Air quality and opening status both need attention',
    ja: '大気と営業状況の両方を確認してください',
    zhHans: '需同时关注空气质量与营业状态',
    zhHant: '需同時關注空氣品質與營業狀態',
  ),
  'bad_weather_and_air_quality_and_closure' => _copy(
    language,
    ko: '날씨·미세먼지·운영 상태를 모두 확인해야 해요',
    en: 'Weather, air quality and opening status all need attention',
    ja: '天候・大気・営業状況をすべて確認してください',
    zhHans: '需同时关注天气、空气质量与营业状态',
    zhHant: '需同時關注天氣、空氣品質與營業狀態',
  ),
  _ => _copy(
    language,
    ko: '일정에 영향을 주는 변화가 있어요',
    en: 'A change may affect your plan',
    ja: '予定に影響する変化があります',
    zhHans: '出现了可能影响行程的变化',
    zhHant: '出現了可能影響行程的變化',
  ),
};

String _sourceLabel(String source, String language) {
  final label = switch (source) {
    'db' => 'LALA DB',
    'public_mvp_snapshot' => 'LALA public snapshot',
    'mixed' => 'LALA mixed sources',
    _ => _copy(
      language,
      ko: '출처 미확인',
      en: 'Source unavailable',
      ja: '出典は未確認',
      zhHans: '来源未确认',
      zhHant: '來源未確認',
    ),
  };
  return _copy(
    language,
    ko: '출처: $label',
    en: 'Source: $label',
    ja: '出典: $label',
    zhHans: '来源：$label',
    zhHant: '來源：$label',
  );
}

String? _factorLabel(Map<String, dynamic> factor, String language) {
  final kind = factor['factor'];
  final value = factor['value'];
  if (kind == 'weather_outdoor_status' && value == 'bad') {
    return _copy(
      language,
      ko: '현재 야외 활동 조건이 좋지 않아요.',
      en: 'Current outdoor conditions are unfavorable.',
      ja: '現在、屋外活動に適さない状況です。',
      zhHans: '当前不适合户外活动。',
      zhHant: '目前不適合戶外活動。',
    );
  }
  // P4: the observed bad dust grade discloses the air-quality cause on its own —
  // never folded into the weather wording above.
  if (kind == 'air_quality_dust_grade' && (value == 'bad' || value == 'very_bad')) {
    return _copy(
      language,
      ko: '관측된 미세먼지 등급이 나빠요.',
      en: 'The observed air-quality grade is poor.',
      ja: '観測された大気の等級が悪いです。',
      zhHans: '观测到的空气质量等级较差。',
      zhHant: '觀測到的空氣品質等級較差。',
    );
  }
  // Why: the API emits the closure factor as slot_closure_state (planner
  // service), so mapping only the legacy closure_state/opening_hours kinds
  // silently dropped the closure reason from the evidence panel.
  if (kind == 'slot_closure_state' || kind == 'closure_state') {
    return _copy(
      language,
      ko: '추정 운영시간 기준으로 영업 종료 가능성이 관측됐어요.',
      en: 'A possible closure was observed from the estimated opening hours.',
      ja: '推定営業時間に基づき、営業終了の可能性が確認されました。',
      zhHans: '根据估算营业时间，观测到可能已打烊。',
      zhHant: '根據估算營業時間，觀測到可能已打烊。',
    );
  }
  if (kind == 'opening_hours') {
    return _copy(
      language,
      ko: '운영 시간 근거가 변화했어요.',
      en: 'The opening-hours evidence changed.',
      ja: '営業時間の根拠が変わりました。',
      zhHans: '营业时间依据发生了变化。',
      zhHant: '營業時間依據發生了變化。',
    );
  }
  return null;
}

/// Short chip label for the change-summary hierarchy (F-051). Same factor
/// families as [_factorLabel]; null for kinds this build cannot label — the
/// chip row never invents a reason the API did not report.
String? _factorChipLabel(Map<String, dynamic> factor, String language) {
  final kind = factor['factor'];
  final value = factor['value'];
  if (kind == 'weather_outdoor_status' && value == 'bad') {
    return _copy(
      language,
      ko: '날씨 악화',
      en: 'Poor weather',
      ja: '天候悪化',
      zhHans: '天气恶劣',
      zhHant: '天氣惡劣',
    );
  }
  // P4: AQ factor gets its own chip label — poor air quality never renders as a
  // weather chip.
  if (kind == 'air_quality_dust_grade' && (value == 'bad' || value == 'very_bad')) {
    return _copy(
      language,
      ko: '미세먼지 나쁨',
      en: 'Poor air quality',
      ja: '大気悪化',
      zhHans: '空气质量差',
      zhHant: '空氣品質差',
    );
  }
  if (kind == 'slot_closure_state' ||
      kind == 'closure_state' ||
      kind == 'opening_hours') {
    return _copy(
      language,
      ko: '운영 상태 변화',
      en: 'Opening-status change',
      ja: '営業状況の変化',
      zhHans: '营业状态变化',
      zhHant: '營業狀態變化',
    );
  }
  return null;
}

IconData _factorChipIcon() => Icons.flag_outlined;

String _copy(
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
