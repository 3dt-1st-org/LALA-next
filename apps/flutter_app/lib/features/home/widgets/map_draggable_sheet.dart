// C3 최종: main.dart 에서 이관. 본문 불변(이동만).
import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/place/widgets/featured_place_panel.dart';
import 'package:lala_next_app/features/map/domain/active_map_sheet.dart';
import 'package:lala_next_app/features/planner/widgets/planner_sheet_content.dart';
import 'package:lala_next_app/features/tour/widgets/tour_sheet_content.dart';
import 'package:lala_next_app/features/weather/widgets/weather_sheet_content.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

class MapDraggableSheet extends StatelessWidget {
  const MapDraggableSheet({super.key,
    required this.activeSheet,
    required this.place,
    required this.places,
    required this.weather,
    required this.language,
    required this.loading,
    required this.intervention,
    required this.dailyPlan,
    required this.docentScript,
    required this.docentAudio,
    required this.tourAudio,
    required this.audioLoading,
    required this.audioError,
    required this.tourAudioLoading,
    required this.tourAudioError,
    required this.liveSpeechEnabled,
    required this.source,
    required this.showEvidence,
    required this.savedPlaceIds,
    required this.detailDocentPlayedPlaceIds,
    required this.onToggleEvidence,
    required this.onToggleSavedPlace,
    required this.onAddToPlan,
    required this.onFetchAudio,
    required this.onFetchTourAudio,
    required this.onSelectPlace,
    required this.onRefresh,
    required this.onClose,
  });

  final ActiveMapSheet activeSheet;
  final LalaPlace? place;
  final List<LalaPlace> places;
  final LalaWeather? weather;
  final String language;
  final bool loading;
  final LalaIntervention? intervention;
  final LalaDailyPlan? dailyPlan;
  final LalaDocentScript? docentScript;
  final LalaAudioResponse? docentAudio;
  final LalaAudioResponse? tourAudio;
  final bool audioLoading;
  final String? audioError;
  final bool tourAudioLoading;
  final String? tourAudioError;
  final bool liveSpeechEnabled;
  final String? source;
  final bool showEvidence;
  final Set<String> savedPlaceIds;
  final Set<String> detailDocentPlayedPlaceIds;
  final VoidCallback onToggleEvidence;
  final ValueChanged<String> onToggleSavedPlace;
  final VoidCallback onAddToPlan;
  final VoidCallback onFetchAudio;
  final VoidCallback onFetchTourAudio;
  final ValueChanged<LalaPlace> onSelectPlace;
  final VoidCallback onRefresh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final title = switch (activeSheet) {
      ActiveMapSheet.detail => language == 'en' ? 'Details' : '장소 상세',
      ActiveMapSheet.planner => language == 'en' ? 'Daily Plan' : '하루 일정',
      ActiveMapSheet.weather => language == 'en' ? 'Weather' : '날씨',
      ActiveMapSheet.tour => language == 'en' ? 'Food Tour' : '맛집 투어',
    };
    final icon = switch (activeSheet) {
      ActiveMapSheet.detail => Icons.place_outlined,
      ActiveMapSheet.planner => Icons.route_outlined,
      ActiveMapSheet.weather => Icons.wb_cloudy_outlined,
      ActiveMapSheet.tour => Icons.restaurant_menu,
    };
    final initialSize = switch (activeSheet) {
      ActiveMapSheet.detail => 0.66,
      ActiveMapSheet.planner => 0.52,
      ActiveMapSheet.weather => 0.44,
      ActiveMapSheet.tour => 0.68,
    };

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
          ),
        ),
        DraggableScrollableSheet(
          initialChildSize: initialSize,
          minChildSize: 0.30,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.98),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 32,
                    offset: Offset(0, -12),
                    color: Color(0x26000000),
                  ),
                ],
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E0),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(icon, color: const Color(0xFF2B6CB0)),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: const Color(0xFF111827),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: lalaCopy(language, ko: '닫기', en: 'Close'),
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  switch (activeSheet) {
                    ActiveMapSheet.detail => FeaturedPlacePanel(
                      place: place,
                      language: language,
                      weather: weather,
                      intervention: intervention,
                      dailyPlan: dailyPlan,
                      docentScript: docentScript,
                      docentAudio: docentAudio,
                      audioLoading: audioLoading,
                      audioError: audioError,
                      liveSpeechEnabled: liveSpeechEnabled,
                      source: source,
                      showEvidence: showEvidence,
                      savedPlaceIds: savedPlaceIds,
                      detailDocentPlayedPlaceIds: detailDocentPlayedPlaceIds,
                      onToggleEvidence: onToggleEvidence,
                      onToggleSavedPlace: onToggleSavedPlace,
                      onAddToPlan: onAddToPlan,
                      onFetchAudio: onFetchAudio,
                    ),
                    ActiveMapSheet.planner => PlannerSheetContent(
                      language: language,
                      weather: weather,
                      dailyPlan: dailyPlan,
                      intervention: intervention,
                      loading: loading,
                      onRegenerate: onRefresh,
                      onSelectPlace: onSelectPlace,
                    ),
                    ActiveMapSheet.weather => WeatherSheetContent(
                      language: language,
                      weather: weather,
                    ),
                    ActiveMapSheet.tour => TourSheetContent(
                      places: places,
                      language: language,
                      tourAudio: tourAudio,
                      audioLoading: tourAudioLoading,
                      audioError: tourAudioError,
                      liveSpeechEnabled: liveSpeechEnabled,
                      onFetchAudio: onFetchTourAudio,
                      onSelectPlace: onSelectPlace,
                    ),
                  },
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
