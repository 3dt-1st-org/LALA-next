import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/labels/dust_label.dart';
import '../../../shared/widgets/compact_info_tile.dart';
import '../../docent/docent_helpers.dart';
import '../../docent/widgets/docent_subtitle.dart';
import '../../planner/planner_helpers.dart';
import '../../weather/weather_helpers.dart';

/// 코스+도슨트 요약 패널(C3 추출 — main.dart 의 _RouteAndDocentPanel).
class RouteAndDocentPanel extends StatelessWidget {
  const RouteAndDocentPanel({
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
    required this.onFetchAudio,
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
  final VoidCallback onFetchAudio;

  @override
  Widget build(BuildContext context) {
    final script = docentScript?.script;
    final canFetchAudio =
        liveSpeechEnabled &&
        hasUsableDocentScript(script, language) &&
        !audioLoading;
    final slots = dailyPlan?.slots ?? const <LalaPlanSlot>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: CompactInfoTile(
                icon: Icons.route,
                label: lalaCopy(language, ko: '오늘 코스', en: 'Today route'),
                value: slots.isEmpty
                    ? lalaCopy(
                        language,
                        ko: '날씨 기준 대체 동선 준비 중',
                        en: 'Preparing a weather-aware route',
                      )
                    : planSlotTitle(slots.first, language),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CompactInfoTile(
                icon: Icons.cloud,
                label: lalaCopy(language, ko: '날씨', en: 'Weather'),
                value: weather == null
                    ? lalaCopy(language, ko: '확인 중', en: 'Checking')
                    : '${temperatureLabel(weather!.temp)} · ${dustSituationLabel(weather!.dust, language)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        DocentSubtitle(
          place: place,
          language: language,
          script: script,
          action: intervention?.recommendedAction,
          audioLoading: audioLoading,
          audioError: audioError,
          docentAudio: docentAudio,
          canFetchAudio: canFetchAudio,
          onFetchAudio: onFetchAudio,
        ),
      ],
    );
  }
}
