import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../weather/weather_helpers.dart';

/// V1-RC3: 선택 장소 날씨 요약 + 날씨 근원(출처) 단일 라인(1줄 ellipsis). [PlaceReasonLine]
/// 와 같은 스타일/구조의 SSOT 위젯으로, 날씨 텍스트는 [publicWeatherSummary] 한 곳에서만
/// 조립된다(독·상세 표면 분산 금지). placeholder/fallback/빈 요약이면 렌더하지 않는다
/// (honest omission — 독 높이에 빈 공간이 남지 않는다).
///
/// [topSpacing] > 0 일 때 요약이 있으면 상단 간격도 같이 렌더하고, 없으면 0(빈 공간 없음)
/// — [PlaceReasonLine] 과 동일한 호출측 간격 규칙.
class PlaceWeatherSourceLine extends StatelessWidget {
  const PlaceWeatherSourceLine({
    super.key,
    required this.weather,
    required this.language,
    this.topSpacing = 0,
  });

  final LalaWeather? weather;
  final String language;
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    final s = publicWeatherSummary(weather, language);
    final summary = s.summary;
    if (summary == null) {
      return const SizedBox.shrink();
    }
    // source 는 summary 가 있을 때만 의미(§3 pairing). 비어 있으면 구분자 없이 요약만
    // 노출 — 값 없는 귀속 표시(뒤에 매단 ' · ')는 오해를 끼친다.
    final source = s.source;
    final text = (source == null || source.isEmpty)
        ? summary
        : '$summary · $source';
    final row = Row(
      children: [
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
    if (topSpacing <= 0) {
      return row;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: topSpacing),
        row,
      ],
    );
  }
}
