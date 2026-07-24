import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/l10n/place_labels.dart';
import '../../../shared/labels/dust_label.dart';
import '../../../shared/widgets/tiny_meta.dart';
import '../../weather/weather_helpers.dart';

/// 일정 개요 카드(C3 추출 — main.dart 의 _PlannerOverviewCard).
/// 위치·날씨 요약과 일정 재생성 버튼을 노출한다.
class PlannerOverviewCard extends StatelessWidget {
  const PlannerOverviewCard({
    super.key,
    required this.language,
    required this.weather,
    required this.dailyPlan,
    required this.visibleSlotCount,
    required this.loading,
    required this.onRegenerate,
  });

  final String language;
  final LalaWeather? weather;
  final LalaDailyPlan? dailyPlan;
  final int visibleSlotCount;
  final bool loading;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final location = weather?.location?.trim().isNotEmpty == true
        ? locationLabel(weather!.location, language)
        : lalaCopy(language, ko: '현재 위치', en: 'Current location');
    // 모바일 비주얼 계약 remediation E: 날씨/먼지를 한 줄 긴 문자열(말줄임/중복 라벨)로
    // 만들지 않고 각 사실을 별도 컴팩트 칩으로 분리해 Wrap 한다.
    final dust = weather?.dust;
    final weatherChips = <Widget>[
      if (weather == null)
        TinyMeta(lalaCopy(language, ko: '날씨 확인 중', en: 'Checking weather'))
      else ...<Widget>[
        TinyMeta(outdoorLabel(weather!.outdoorStatus, language: language)),
        TinyMeta(temperatureLabel(weather!.temp)),
        if (dust != null) ...<Widget>[
          if (dust.pm10.trim().isNotEmpty)
            TinyMeta(
              compactDustPart(
                label: 'PM10',
                value: dust.pm10,
                grade: dustPollutantGradeLabel(dust, 'pm10', language),
              ),
            ),
          if (dust.pm25.trim().isNotEmpty)
            TinyMeta(
              compactDustPart(
                label: 'PM2.5',
                value: dust.pm25,
                grade: dustPollutantGradeLabel(dust, 'pm25', language),
              ),
            ),
        ],
      ],
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: <Widget>[
                    ...weatherChips,
                    if (visibleSlotCount > 0)
                      TinyMeta(
                        lalaCopy(
                          language,
                          ko: '$visibleSlotCount개 일정',
                          en: '$visibleSlotCount stops',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const ValueKey('planner-regenerate'),
            onPressed: loading ? null : onRegenerate,
            icon: loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 17),
            label: Text(lalaCopy(language, ko: '일정 재생성', en: 'Regenerate')),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2B6CB0),
              side: const BorderSide(color: Color(0xFFB9D4F3)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}
