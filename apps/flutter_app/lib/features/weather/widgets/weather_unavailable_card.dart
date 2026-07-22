import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';

/// 날씨 데이터 미준비 상태 카드(C3 추출 — main.dart 의 _WeatherUnavailableCard).
class WeatherUnavailableCard extends StatelessWidget {
  const WeatherUnavailableCard({super.key, required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('weather-unavailable-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 38,
            color: Color(0xFF64748B),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lalaCopy(
                    language,
                    ko: '날씨 데이터 준비 중',
                    en: 'Weather data is being prepared',
                  ),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  lalaCopy(
                    language,
                    ko: '실시간 관측값이 확인될 때 온도와 미세먼지를 표시합니다.',
                    en: 'Temperature and dust appear when verified observations are available.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
