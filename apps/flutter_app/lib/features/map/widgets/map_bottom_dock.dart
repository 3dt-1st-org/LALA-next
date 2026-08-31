import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/place_labels.dart';
import '../../../shared/labels/dataset_freshness_label.dart';
import '../../../shared/labels/source_label.dart';
import '../../../shared/widgets/tiny_meta.dart';
import '../../docent/widgets/dock_docent_preview.dart';
import '../../home/home_view_helpers.dart';
import '../../place/place_helpers.dart';
import '../../place/widgets/category_badge.dart';
import '../../place/widgets/place_reason_freshness.dart';
import '../../place/widgets/place_weather_source_line.dart';
import 'empty_dock_content.dart';

/// 지도 하단 독(선택 장소 요약 + 도슨트 미리보기)(C3 추출 — main.dart 의 _MapBottomDock).
class MapBottomDock extends StatelessWidget {
  static const double mobileCollapsedHeight = 84;

  const MapBottomDock({
    super.key,
    required this.isWide,
    required this.places,
    required this.source,
    this.weather,
    required this.dataAsOf,
    required this.topPlace,
    required this.uiLanguage,
    required this.height,
    this.expanded = true,
    required this.docentScript,
    required this.docentAudio,
    required this.docentAction,
    required this.audioLoading,
    required this.audioError,
    required this.canFetchAudio,
    required this.showEvidence,
    required this.error,
    required this.placeFailureKind,
    required this.recommendationRecoveryPending,
    required this.onFetchAudio,
    required this.onAddToPlan,
    required this.onOpenDetail,
    required this.onRefresh,
    required this.onToggleEvidence,
    this.onToggleExpanded,
  });

  final bool isWide;
  final List<LalaPlace> places;
  final String? source;

  /// V1-RC3: 선택 장소 날씨(이미 dashboard 의 currentWeather = publicWeatherOrNull 통과).
  /// 새 fetch 없이 독에만 포크. null/placeholder/fallback 이면 날씨 줄이 정직하게 생략된다.
  final LalaWeather? weather;

  /// 정직한 data-as-of(snapshot build timestamp). present 일 때만 신선도 라벨 표시.
  final String? dataAsOf;
  final LalaPlace? topPlace;
  final String uiLanguage;
  final double height;
  final bool expanded;
  final String? docentScript;
  final LalaAudioResponse? docentAudio;
  final String? docentAction;
  final bool audioLoading;
  final String? audioError;
  final bool canFetchAudio;
  final bool showEvidence;
  final String? error;
  // 추천 로드 실패의 honest 종류(unavailable vs error). null = 실패 없음(준비 중).
  final RecommendationFailureKind? placeFailureKind;
  final bool recommendationRecoveryPending;
  final VoidCallback onFetchAudio;
  final VoidCallback onAddToPlan;
  final VoidCallback onOpenDetail;
  final VoidCallback onRefresh;
  final VoidCallback onToggleEvidence;
  final VoidCallback? onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final currentPlace = topPlace;
    final showExpandedContent = currentPlace == null || expanded;
    return AnimatedContainer(
      key: const ValueKey('map-bottom-dock'),
      height: height,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 28,
            offset: Offset(0, -10),
            color: Color(0x22000000),
          ),
        ],
      ),
      child: showExpandedContent
          ? _buildExpandedContent(context, currentPlace)
          : _buildCollapsedContent(context, currentPlace),
    );
  }

  Widget _buildCollapsedContent(BuildContext context, LalaPlace currentPlace) {
    final expandLabel = lalaCopyMulti(
      uiLanguage,
      ko: '장소 요약 펼치기',
      en: 'Expand place summary',
      ja: 'スポット概要を展開',
      zhHans: '展开地点摘要',
      zhHant: '展開地點摘要',
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: _handleHeaderDragEnd,
      child: Semantics(
        container: true,
        button: true,
        excludeSemantics: true,
        label:
            '$expandLabel, ${placeDisplayName(currentPlace, uiLanguage)}, '
            '${currentPlace.distanceM}m',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('map-dock-expand-toggle'),
            onTap: onToggleExpanded,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 12, 8),
              child: Column(
                children: [
                  _DockHandle(color: const Color(0xFFCBD5E0)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      CategoryBadge(
                        category: currentPlace.category,
                        language: uiLanguage,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          placeDisplayName(currentPlace, uiLanguage),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: const Color(0xFF111827),
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${currentPlace.distanceM}m',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const ExcludeSemantics(
                        child: Icon(
                          Icons.keyboard_arrow_up,
                          color: Color(0xFF2B6CB0),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedContent(BuildContext context, LalaPlace? currentPlace) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, isWide ? 14 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: currentPlace == null || isWide
                        ? null
                        : onToggleExpanded,
                    onVerticalDragEnd: currentPlace == null || isWide
                        ? null
                        : _handleHeaderDragEnd,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: _DockHandle(color: Color(0xFFCBD5E0)),
                    ),
                  ),
                ),
              ),
              if (!isWide && currentPlace != null && onToggleExpanded != null)
                IconButton(
                  key: const ValueKey('map-dock-collapse-toggle'),
                  tooltip: lalaCopyMulti(
                    uiLanguage,
                    ko: '장소 요약 접기',
                    en: 'Collapse place summary',
                    ja: 'スポット概要を折りたたむ',
                    zhHans: '收起地点摘要',
                    zhHant: '收合地點摘要',
                  ),
                  onPressed: onToggleExpanded,
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
              TextButton.icon(
                onPressed: currentPlace == null ? null : onOpenDetail,
                icon: const Icon(Icons.open_in_full, size: 18),
                label: Text(
                  lalaCopyMulti(
                    uiLanguage,
                    ko: '상세',
                    en: 'Details',
                    ja: '詳細',
                    zhHans: '详情',
                    zhHant: '詳情',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (currentPlace == null)
            EmptyDockContent(
              language: uiLanguage,
              errorLabel: error,
              failureKind: placeFailureKind,
              recoveryPending: recommendationRecoveryPending,
              onRetry: onRefresh,
            )
          else ...[
            Row(
              children: [
                CategoryBadge(
                  category: currentPlace.category,
                  language: uiLanguage,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    placeDisplayName(currentPlace, uiLanguage),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF111827),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    if (!showEvidence) {
                      onToggleEvidence();
                    }
                    onOpenDetail();
                  },
                  child: Text(
                    lalaCopyMulti(
                      uiLanguage,
                      ko: '점수/근거',
                      en: 'Signals',
                      ja: 'スコア/根拠',
                      zhHans: '评分/依据',
                      zhHant: '評分/依據',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TinyMeta(placeRegionLabel(currentPlace, uiLanguage)),
                TinyMeta('${currentPlace.distanceM}m'),
                if (sourceLabel(source, language: uiLanguage)
                    case final String src when src != '-')
                  TinyMeta(src),
                if (placeFreshnessText(currentPlace) case final String f)
                  TinyMeta(f),
                if (datasetFreshnessLabel(dataAsOf, uiLanguage)
                    case final String label)
                  TinyMeta(label),
              ],
            ),
            PlaceReasonLine(place: currentPlace, topSpacing: 8),
            PlaceWeatherSourceLine(
              weather: weather,
              language: uiLanguage,
              topSpacing: 4,
            ),
            const SizedBox(height: 12),
            DockDocentPreview(
              place: currentPlace,
              language: uiLanguage,
              script: docentScript,
              action: docentAction,
              audioLoading: audioLoading,
              audioError: audioError,
              docentAudio: docentAudio,
              canFetchAudio: canFetchAudio,
              onFetchAudio: onFetchAudio,
              onAddToPlan: onAddToPlan,
              onOpenDetail: onOpenDetail,
            ),
          ],
        ],
      ),
    );
  }

  void _handleHeaderDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity;
    if (velocity == null || onToggleExpanded == null) {
      return;
    }
    if ((!expanded && velocity < -180) || (expanded && velocity > 180)) {
      onToggleExpanded!();
    }
  }
}

class _DockHandle extends StatelessWidget {
  const _DockHandle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('map-dock-drag-handle'),
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
