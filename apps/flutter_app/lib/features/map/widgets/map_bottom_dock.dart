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

  @override
  Widget build(BuildContext context) {
    final currentPlace = topPlace;
    return SizedBox(
      key: const ValueKey('map-bottom-dock'),
      height: height,
      child: DecoratedBox(
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
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, isWide ? 14 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onTap: onOpenDetail,
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCBD5E0),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: currentPlace == null ? null : onOpenDetail,
                    icon: const Icon(Icons.keyboard_arrow_up),
                    // V6: 도슨트 상세 진입 라벨 — 방문객 로케일도 현지화(계약 I1).
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
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
                    // V1-RC3(D-Src): sourceLabel 이 '-'(null/빈 source) 이면 칩을 생략한다
                    // (독·상세가 bare '-' 대신 정직한 부재로 일치).
                    if (sourceLabel(source, language: uiLanguage)
                        case final String src when src != '-')
                      TinyMeta(src),
                    // V1-RC2(D-2): per-place 신선도(장소 단위). 아래 칩은
                    // 데이터셋 기준(dataAsOf)으로 별개 — 이름/개념 다르게 유지.
                    if (placeFreshnessText(currentPlace) case final String f)
                      TinyMeta(f),
                    if (datasetFreshnessLabel(dataAsOf, uiLanguage)
                        case final String label)
                      TinyMeta(label),
                  ],
                ),
                // V1-RC2: per-place reason(reason 없으면 PlaceReasonLine 이 렌더 생략 → 빈 공간 없음).
                PlaceReasonLine(place: currentPlace, topSpacing: 8),
                // V1-RC3: 날씨 요약 · 날씨 출처 1줄(weather null/fallback 이면 생략 → 빈 공간 없음).
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
        ),
      ),
    );
  }
}
