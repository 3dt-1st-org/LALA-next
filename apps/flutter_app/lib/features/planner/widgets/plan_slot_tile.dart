import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/l10n/multi_language_text.dart';
import '../../../shared/l10n/place_labels.dart';
import '../../docent/widgets/docent_play_button.dart';
import '../planner_helpers.dart';
import '../spend_band_helpers.dart';

/// 일정 슬롯 타일(C3 추출 — main.dart 의 _PlanSlotTile).
class PlanSlotTile extends StatelessWidget {
  const PlanSlotTile({
    super.key,
    required this.slot,
    required this.language,
    required this.onSelectPlace,
    this.swapReason,
    this.visitStatus,
    this.onToggleVisit,
    this.spendBand,
    this.spendUnavailable = false,
    this.onPlayDocent,
  });

  final LalaPlanSlot slot;
  final String language;
  final ValueChanged<LalaPlace> onSelectPlace;

  /// 날씨 교체 사유(P6A §04 Screen 04 swapped 상태). null 이면 일반 표시.
  final String? swapReason;

  // V5-B VISIT (§V5-B D2): current visit status
  // ('planned' | 'visited' | 'not_visited'). null →
  // visit badge not rendered (backward-compatible for callers not wiring V5-B).
  final String? visitStatus;

  /// Opens the visit outcome editor. The badge remains a 44dp tap target.
  final VoidCallback? onToggleVisit;

  // V5-B SPEND (§V5-B D3): offline category-band estimate. null + false → no
  // spend row rendered. The caller passes either [spendBand] (known category) or
  // [spendUnavailable] (honest-unavailable band); never a fabricated number.
  final SpendBand? spendBand;
  final bool spendUnavailable;

  /// 이슈 #120 §6: 슬롯별 도슨트 재생 진입(선택). null 이면 버튼을 만들지 않는다.
  /// 타일 탭(스낵바)과 독립인 제스처 영역이다.
  final VoidCallback? onPlayDocent;

  @override
  Widget build(BuildContext context) {
    final place = slot.place;
    final periodLabelText = periodLabel(slot.period, language: language);
    final title = place == null
        ? planSlotTitle(slot, language)
        : placeDisplayName(place, language);
    final subtitle = place == null ? null : placeRegionLabel(place, language);
    final weatherHint = singleLanguageText(slot.weatherHint ?? '', language);
    final detail = planSlotDetail(slot, language);
    final travelTimeLabel = planSlotTravelTimeLabel(slot, language);
    final estimatedHoursLabel = planSlotEstimatedHoursLabel(slot, language);
    final indoorOutdoorLabel = slot.indoorOutdoor == null
        ? null
        : (slot.indoorOutdoor == 'indoor'
              ? lalaCopyMulti(
                  language,
                  ko: '실내',
                  en: 'Indoor',
                  ja: '屋内',
                  zhHans: '室内',
                  zhHant: '室內',
                )
              : lalaCopyMulti(
                  language,
                  ko: '야외',
                  en: 'Outdoor',
                  ja: '屋外',
                  zhHans: '室外',
                  zhHant: '室外',
                ));
    // V3-C D2/D3/D4 투영: forecast_window(예보) · air_quality_bad(야외 먼지) ·
    // closure_state(운영 상태). null 은 honest-empty(placeholder 없음/unknown).
    final forecastWindowText = planSlotForecastWindowLabel(slot, language);
    final airQualityBadText = planSlotAirQualityBadLabel(slot, language);
    final closureStateText = planSlotClosureStateLabel(slot, language);
    // D4 배지 색/아이콘은 원천 state 기반(null → unknown).
    final closureStateKey = (slot.closureState ?? 'unknown').trim().toLowerCase();
    // 기존 토큰만 재사용(teal=open/positive, red=closed/bad, slate=unknown/neutral).
    final closureBadgeColor = switch (closureStateKey) {
      'open' => const Color(0xFF0F766E),
      'closed' => const Color(0xFFC53030),
      _ => const Color(0xFF64748B),
    };
    final closureBadgeIcon = switch (closureStateKey) {
      'open' => Icons.check_circle_outline,
      'closed' => Icons.cancel_outlined,
      _ => Icons.help_outline,
    };
    final metaEntries = <String>[
      ?travelTimeLabel,
      ?estimatedHoursLabel,
    ];
    // V5-B VISIT/SPEND badge text (only when wired by the caller).
    final visitLabel = visitStatus == null ? null : _visitBadgeLabel(visitStatus!, language);
    final spendLabel = spendBand?.label ??
        (spendUnavailable ? spendBandUnavailableLabel(language) : null);
    // 접근성(§13.5): 슬롯 메타(시간대/실내·야외/이동시간/추정시간/운영상태/예보/대기질)를
    // 하나의 시맨틱 라벨로 합쳐 화면 읽기 사용자에게 전달. 색상 단독 신호를 피하기 위해
    // 실내·야외·운영상태는 모두 아이콘+텍스트+라벨 삼중으로 표현한다.
    final semanticsParts = <String>[
      periodLabelText,
      title,
      ?subtitle,
      closureStateText,
      ?indoorOutdoorLabel,
      ?weatherHint,
      ?forecastWindowText,
      ...metaEntries,
      ?airQualityBadText,
      ?visitLabel,
      ?spendLabel,
    ];
    return Semantics(
      container: true,
      button: place != null,
      label: semanticsParts.join(', '),
      child: Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey('planner-slot-${place?.placeId ?? slot.period}'),
          borderRadius: BorderRadius.circular(12),
          onTap: place == null ? null : () => onSelectPlace(place),
          // 최소 44dp 터치 타겟 보장(내용이 짧아도 타일 전체 높이 하한선).
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        periodIcon(slot.period),
                        size: 17,
                        color: const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        periodLabelText,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      if (weatherHint != null) ...[
                        const Spacer(),
                        Text(
                          weatherHint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: const Color(0xFF94A3B8),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                      if (forecastWindowText != null) ...[
                        // D2: 예보가 확보된 슬롯에만 "time · temp" 표시.
                        // null 이면 줄 자리 없이 숨긴다(placeholder/spinner 없음).
                        if (weatherHint == null) const Spacer(),
                        if (weatherHint != null) const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            forecastWindowText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: const Color(0xFF475569),
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ],
                      if (slot.indoorOutdoor != null) ...[
                        if (weatherHint == null && forecastWindowText == null)
                          const Spacer(),
                        Icon(
                          slot.indoorOutdoor == 'indoor'
                              ? Icons.home_work_outlined
                              : Icons.park_outlined,
                          size: 13,
                          color: slot.indoorOutdoor == 'indoor'
                              ? const Color(0xFF0F766E)
                              : const Color(0xFFC53030),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          indoorOutdoorLabel!,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: slot.indoorOutdoor == 'indoor'
                                    ? const Color(0xFF0F766E)
                                    : const Color(0xFFC53030),
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ],
                  ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF1E293B),
                  fontWeight: FontWeight.w900,
                  height: 1.18,
                ),
              ),
              // D4: 운영 상태 배지(open/closed/unknown). 색상 단독 신호를 피하려고
              // 아이콘+텍스트+시맨틱 라벨 삼중 표시(실내·야외 패턴과 동일). null→unknown.
              // 기존 칩 배경/보더 토큰에 상태색 보더+아이콘+텍스트만 입힌다(색 토큰 추가 없음).
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: closureBadgeColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(closureBadgeIcon, size: 11, color: closureBadgeColor),
                      const SizedBox(width: 3),
                      Text(
                        closureStateText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: closureBadgeColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // V5-B VISIT + SPEND (§V5-B D2/D3): rendered only when the caller
              // wires them. Existing callers that omit all three params see the
              // legacy tile shape unchanged. Both reuse the documented slate chip
              // tokens (no new color); icon+text+semantics so color is never the
              // sole signal (§13.5).
              if (visitLabel != null || spendLabel != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (visitLabel != null)
                      _VisitBadge(
                        language: language,
                        status: visitStatus!,
                        label: visitLabel,
                        onToggle: onToggleVisit,
                      ),
                    if (spendLabel != null)
                      _SpendBandChip(
                        label: spendLabel,
                        unavailable: spendBand == null && spendUnavailable,
                      ),
                  ],
                ),
              ],
              if (swapReason != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBF4FE),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.swap_horiz,
                        size: 12,
                        color: const Color(0xFF2B6CB0),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          swapReason!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: const Color(0xFF2B6CB0),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (detail != null) ...[
                const SizedBox(height: 6),
                Text(
                  detail,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
              if (metaEntries.isNotEmpty) ...[
                const SizedBox(height: 6),
                Semantics(
                  container: true,
                  label: metaEntries.join(', '),
                  child: Padding(
                    // Keep the meta row clear of the 44dp tap target below/above.
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final entry in metaEntries)
                          _PlanSlotMetaChip(text: entry),
                      ],
                    ),
                  ),
                ),
              ],
              if (airQualityBadText != null) ...[
                // D3: 야외 슬롯에만 먼지 나쁨 마커 표시. null/false/실내면 숨긴다
                // (null 을 "나쁨"으로 조작하지 않는다 — honest-empty). 빨강 토큰 재사용.
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 13,
                      color: Color(0xFFC53030),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        airQualityBadText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: const Color(0xFFC53030),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (place != null) ...[
                const SizedBox(height: 7),
                Align(
                  alignment: Alignment.centerRight,
                  child: onPlayDocent == null
                      ? const Icon(
                          Icons.chevron_right,
                          color: Color(0xFF94A3B8),
                          size: 20,
                        )
                      : Row(
                          // 이슈 #120 §6: 슬롯별 도슨트 재생(44dp). 중첩 제스처에서
                          // 안쪽이 이기므로 버튼 탭은 타일 탭으로 새지 않는다.
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DocentPlayButton(
                              key: ValueKey(
                                'plan-slot-docent-play-${place.placeId}',
                              ),
                              language: language,
                              onPressed: onPlayDocent,
                              visual: 30,
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.chevron_right,
                              color: Color(0xFF94A3B8),
                              size: 20,
                            ),
                          ],
                        ),
                ),
              ],
            ],
          ),
        ),
          ),
        ),
      ),
    );
  }
}

/// 일정 슬롯 부가 메타(도보 이동시간 / 추정 운영시간)용 컴팩트 칩.
/// 기존 타일의 slate 토큰(배경/보더/텍스트 색)만 재사용하고 새 토큰을 만들지 않는다.
/// §12.3: 추정 운영시간은 authority 가 아니므로 항상 (추정)/(est.) 마커와 함께 표시.
class _PlanSlotMetaChip extends StatelessWidget {
  const _PlanSlotMetaChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFF475569),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// V5-B VISIT badge text for a bounded outcome.
String _visitBadgeLabel(String status, String language) {
  return switch (status.trim().toLowerCase()) {
    'visited' => lalaCopyMulti(
      language,
      ko: '방문함',
      en: 'Visited',
      ja: '訪問済み',
      zhHans: '已到访',
      zhHant: '已到訪',
    ),
    'not_visited' => lalaCopyMulti(
      language,
      ko: '방문하지 않음',
      en: 'Not visited',
      ja: '未訪問',
      zhHans: '未到访',
      zhHant: '未到訪',
    ),
    _ => lalaCopyMulti(
      language,
      ko: '예정',
      en: 'Planned',
      ja: '予定',
      zhHans: '计划中',
      zhHant: '計畫中',
    ),
  };
}

/// V5-B VISIT badge: planned / visited / not visited, never color-alone.
/// Tappable with a 44dp minimum target when [onToggle] is non-null.
class _VisitBadge extends StatelessWidget {
  const _VisitBadge({
    required this.language,
    required this.status,
    required this.label,
    this.onToggle,
  });

  final String language;
  final String status;
  final String label;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();
    final color = switch (normalized) {
      'visited' => const Color(0xFF0F766E),
      'not_visited' => const Color(0xFFC53030),
      _ => const Color(0xFF64748B),
    };
    final icon = switch (normalized) {
      'visited' => Icons.check_circle,
      'not_visited' => Icons.do_not_disturb_alt_rounded,
      _ => Icons.radio_button_unchecked,
    };
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
    if (onToggle == null) {
      return chip;
    }
    // Min 44dp touch target (§13.5); the action opens the explicit S-25 editor.
    final toggleLabel = lalaCopyMulti(
      language,
      ko: '방문 결과 변경',
      en: 'Change visit outcome',
      ja: '訪問結果を変更',
      zhHans: '更改到访结果',
      zhHant: '變更到訪結果',
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(6),
        child: Semantics(
          button: true,
          label: toggleLabel,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: chip,
          ),
        ),
      ),
    );
  }
}

/// V5-B SPEND band chip: estimate or honest-unavailable. Reuses the documented
/// slate meta-chip tokens; the unavailable variant adds a help icon so absence is
/// never read as a zero/blank number (B5 honest-unavailable).
class _SpendBandChip extends StatelessWidget {
  const _SpendBandChip({required this.label, this.unavailable = false});

  final String label;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            unavailable ? Icons.help_outline : Icons.payments_outlined,
            size: 12,
            color: const Color(0xFF64748B),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF475569),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
