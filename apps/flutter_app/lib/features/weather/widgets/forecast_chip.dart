import 'package:flutter/material.dart';

import 'package:lala_next_app/shared/l10n/lala_copy.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../weather_helpers.dart';

/// 예보 단일 칩(C3 추출 — main.dart 의 _ForecastChip).
class ForecastChip extends StatelessWidget {
  const ForecastChip({super.key, required this.item, required this.language});

  final LalaForecastItem item;
  final String language;

  @override
  Widget build(BuildContext context) {
    // P1: 빈 예보 온도는 '-' 한 글자로 보이지 않고, 시간만 남긴다.
    final tempLabel = temperatureLabelOrNull(item.temp);
    return Container(
      width: 88,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            // V6: ko 만 'N시' 변환(방문객/EN 은 원본 24h 표기).
            normalizeLalaLanguage(language) == 'ko'
                ? weatherChartTimeLabel(item.time)
                : item.time,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w800,
            ),
          ),
          if (tempLabel != null) ...[
            const SizedBox(height: 6),
            Text(
              tempLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ],
      ),
    );
  }
}
