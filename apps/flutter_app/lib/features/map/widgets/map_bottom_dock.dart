import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/place_labels.dart';
import '../../../shared/labels/source_label.dart';
import '../../../shared/widgets/tiny_meta.dart';
import '../../docent/widgets/dock_docent_preview.dart';
import '../../home/home_view_helpers.dart';
import '../../place/widgets/category_badge.dart';
import 'empty_dock_content.dart';

/// 지도 하단 독(선택 장소 요약 + 도슨트 미리보기)(C3 추출 — main.dart 의 _MapBottomDock).
class MapBottomDock extends StatelessWidget {
  const MapBottomDock({
    super.key,
    required this.isWide,
    required this.places,
    required this.source,
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
                    label: Text(uiLanguage == 'en' ? 'Details' : '상세'),
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
                        uiLanguage == 'en' ? 'Signals' : '점수/근거',
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
                    TinyMeta(sourceLabel(source, language: uiLanguage)),
                    if (_freshnessLabel(dataAsOf, uiLanguage)
                        case final String label)
                      TinyMeta(label),
                  ],
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

final RegExp _freshnessDateOnly = RegExp(r'^(\d{4}-\d{2}-\d{2})');

/// 정직한 신선도 라벨: 실제 snapshot generated_at 의 날짜(YYYY-MM-DD) 부분만 사용.
/// [dataAsOf] 가 없거나 날짜 파식 불가 → null(honest absence, 라벨 미표시).
/// 절대 fabricate/invent/mok timestamp 를 넣지 않는다.
String? _freshnessLabel(String? dataAsOf, String language) {
  if (dataAsOf == null) return null;
  final match = _freshnessDateOnly.firstMatch(dataAsOf);
  if (match == null) return null;
  final date = match.group(1)!;
  return language == 'en' ? 'Data as of: $date' : '데이터 기준: $date';
}
