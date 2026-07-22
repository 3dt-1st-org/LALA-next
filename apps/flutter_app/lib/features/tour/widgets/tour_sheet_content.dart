import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/l10n/place_labels.dart';
import '../../../shared/widgets/muted_sheet_card.dart';
import '../../docent/widgets/tour_audio_bar.dart';
import '../../docent/widgets/tour_script_card.dart';
import '../../place/place_helpers.dart';
import '../../place/widgets/place_image.dart';
import '../tour_helpers.dart';
import 'tour_stop_tile.dart';
import 'tour_tag.dart';

/// 맛집 투어 시트 본문(C3 추출 — main.dart 의 _TourSheetContent).
class TourSheetContent extends StatelessWidget {
  const TourSheetContent({
    super.key,
    required this.places,
    required this.language,
    required this.tourAudio,
    required this.audioLoading,
    required this.audioError,
    required this.liveSpeechEnabled,
    required this.onFetchAudio,
    required this.onSelectPlace,
  });

  final List<LalaPlace> places;
  final String language;
  final LalaAudioResponse? tourAudio;
  final bool audioLoading;
  final String? audioError;
  final bool liveSpeechEnabled;
  final VoidCallback onFetchAudio;
  final ValueChanged<LalaPlace> onSelectPlace;

  @override
  Widget build(BuildContext context) {
    final items = places.take(5).toList(growable: false);
    if (items.isEmpty) {
      return MutedSheetCard(
        icon: Icons.restaurant_menu,
        label: lalaCopy(
          language,
          ko: '근처 맛집 투어 후보를 찾고 있습니다.',
          en: 'Looking for nearby food tour stops.',
        ),
      );
    }

    final headline = lalaCopy(
      language,
      ko: '가까운 맛집 ${items.length}곳을 이어 걷는 코스',
      en: '${items.length} nearby food stops for a walkable route',
    );
    final first = items.first;
    final script = tourGuideScript(items, language);
    final sourceLabelText = lalaCopy(
      language,
      ko: '${items.length}개 맛집 · 공식 데이터 기반',
      en: '${items.length} restaurants · Official data',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFF5C842)),
          ),
          child: Row(
            children: [
              if (hasOfficialPlaceImage(first)) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: PlaceImage(place: first, width: 64, height: 64),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF1A202C),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      lalaCopy(
                        language,
                        ko: '${placeDisplayName(first, language)}부터 시작 · ${first.distanceM}m',
                        en: 'Start at ${placeDisplayName(first, language)} · ${first.distanceM}m',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final place in items)
              TourTag(
                key: ValueKey('tour-tag-${place.placeId}'),
                label: placeDisplayName(place, language),
                onPressed: () => onSelectPlace(place),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TourScriptCard(
          script: script,
          sourceLabel: sourceLabelText,
          language: language,
        ),
        const SizedBox(height: 12),
        if (liveSpeechEnabled) ...[
          TourAudioBar(
            language: language,
            audio: tourAudio,
            loading: audioLoading,
            error: audioError,
            onFetchAudio: onFetchAudio,
          ),
          const SizedBox(height: 14),
        ],
        ...items.indexed.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TourStopTile(
              key: ValueKey('tour-stop-${entry.$2.placeId}'),
              index: entry.$1,
              place: entry.$2,
              language: language,
              onTap: () => onSelectPlace(entry.$2),
            ),
          ),
        ),
      ],
    );
  }
}
