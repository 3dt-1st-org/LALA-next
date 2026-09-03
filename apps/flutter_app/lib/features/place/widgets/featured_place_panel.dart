// C3 최종: main.dart 에서 이관. 본문 불변(이동만).
import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/docent/docent_helpers.dart';
import 'package:lala_next_app/features/docent/widgets/docent_subtitle.dart';
import 'package:lala_next_app/features/place/place_helpers.dart';
import 'package:lala_next_app/features/place/widgets/event_info_card.dart';
import 'package:lala_next_app/features/place/widgets/featured_place_header.dart';
import 'package:lala_next_app/features/place/widgets/place_context_card.dart';
import 'package:lala_next_app/features/place/widgets/public_data_proof_row.dart';
import 'package:lala_next_app/features/place/widgets/signal_grid.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/presentation/restaurant_communication_entry_card.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';
import 'package:lala_next_app/shared/widgets/muted_sheet_card.dart';

class FeaturedPlacePanel extends StatelessWidget {
  const FeaturedPlacePanel({
    super.key,
    required this.place,
    required this.language,
    required this.weather,
    required this.intervention,
    required this.dailyPlan,
    required this.docentScript,
    required this.docentAudio,
    required this.audioLoading,
    required this.audioError,
    required this.liveSpeechEnabled,
    required this.source,
    required this.showEvidence,
    required this.savedPlaceIds,
    required this.detailDocentPlayedPlaceIds,
    required this.onToggleEvidence,
    required this.onToggleSavedPlace,
    required this.onAddToPlan,
    required this.onFetchAudio,
    this.onOpenFullDetails,
    this.preferencesStore,
  });

  final LalaPlace? place;
  final String language;
  final LalaWeather? weather;
  final LalaIntervention? intervention;
  final LalaDailyPlan? dailyPlan;
  final LalaDocentScript? docentScript;
  final LalaAudioResponse? docentAudio;
  final bool audioLoading;
  final String? audioError;
  final bool liveSpeechEnabled;
  final String? source;
  final bool showEvidence;
  final Set<String> savedPlaceIds;
  final Set<String> detailDocentPlayedPlaceIds;
  final VoidCallback onToggleEvidence;
  final ValueChanged<String> onToggleSavedPlace;
  final VoidCallback onAddToPlan;
  final VoidCallback onFetchAudio;
  final VoidCallback? onOpenFullDetails;
  final TravelPreferencesStore? preferencesStore;

  @override
  Widget build(BuildContext context) {
    final currentPlace = place;
    if (currentPlace == null) {
      return MutedSheetCard(
        icon: Icons.place_outlined,
        label: lalaCopyMulti(
          language,
          ko: '이 주변 추천을 준비 중입니다. 지도를 움직이거나 잠시 뒤 다시 시도해 주세요.',
          en: 'Recommendations are still being prepared here. Move the map or try again shortly.',
          ja: 'この周辺のおすすめを準備中です。地図を動かすか、しばらくしてからもう一度お試しください。',
          zhHans: '正在准备这附近的推荐。请移动地图或稍后重试。',
          zhHant: '正在準備這附近的推薦。請移動地圖或稍後再試。',
        ),
      );
    }
    final score = currentPlace.score;
    final components = score?.components;
    final slots = dailyPlan?.slots ?? const <LalaPlanSlot>[];
    final effectiveDocent = docentScript?.placeId == currentPlace.placeId
        ? docentScript
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FeaturedPlaceHeader(
          place: currentPlace,
          language: language,
          showEvidence: showEvidence,
          saved: savedPlaceIds.contains(currentPlace.placeId),
          onToggleSaved: () => onToggleSavedPlace(currentPlace.placeId),
        ),
        const SizedBox(height: 12),
        PlaceContextCard(
          place: currentPlace,
          language: language,
          weather: weather,
          source: source,
          showEvidence: showEvidence,
        ),
        if (currentPlace.category.toLowerCase() == 'restaurant') ...[
          const SizedBox(height: 12),
          RestaurantCommunicationEntryCard(
            language: language,
            store: preferencesStore,
          ),
        ],
        if (onOpenFullDetails != null) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('open-full-place-details'),
            onPressed: onOpenFullDetails,
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(
              lalaCopyMulti(
                language,
                ko: '전체 상세 보기',
                en: 'Open full details',
                ja: '詳細を全画面で見る',
                zhHans: '查看完整详情',
                zhHant: '查看完整詳情',
              ),
            ),
          ),
        ],
        if (shouldShowEventInfo(currentPlace)) ...[
          const SizedBox(height: 12),
          EventInfoCard(place: currentPlace, language: language),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onToggleEvidence,
            icon: Icon(
              showEvidence ? Icons.visibility_off : Icons.insights_outlined,
            ),
            label: Text(
              showEvidence
                  ? lalaCopyMulti(
                      language,
                      ko: '점수/근거 숨기기',
                      en: 'Hide signals',
                      ja: 'スコア・根拠を隠す',
                      zhHans: '隐藏评分和依据',
                      zhHant: '隱藏評分和依據',
                    )
                  : lalaCopyMulti(
                      language,
                      ko: '점수/근거 보기',
                      en: 'Show signals',
                      ja: 'スコア・根拠を見る',
                      zhHans: '查看评分和依据',
                      zhHant: '查看評分和依據',
                    ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1A202C),
              side: const BorderSide(color: Color(0xFFD7E3F5)),
            ),
          ),
        ),
        if (showEvidence) ...[
          const SizedBox(height: 12),
          SignalGrid(
            language: language,
            localSpending: components?.localSpendingScore,
            demandDispersion: components?.demandDispersionScore,
            cultureRelevance: components?.cultureRelevanceScore,
            weatherFit: components?.weatherFitScore,
          ),
        ],
        const SizedBox(height: 12),
        DocentSubtitle(
          place: currentPlace,
          language: language,
          script: effectiveDocent?.script,
          action:
              intervention?.recommendedAction ??
              (slots.isEmpty ? null : slots.first.title),
          audioLoading: audioLoading,
          audioError: audioError,
          docentAudio: docentAudio,
          canFetchAudio:
              liveSpeechEnabled &&
              hasUsableDocentScript(effectiveDocent?.script, language) &&
              !audioLoading &&
              !detailDocentPlayedPlaceIds.contains(currentPlace.placeId),
          onFetchAudio: onFetchAudio,
          onAddToPlan: onAddToPlan,
        ),
        if (showEvidence) ...[
          const SizedBox(height: 12),
          PublicDataProofRow(
            place: currentPlace,
            language: language,
            source: source ?? currentPlace.source,
            weather: weather,
            score: score,
          ),
        ],
      ],
    );
  }
}
