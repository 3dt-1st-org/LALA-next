// S-14 날씨 관측 시각 배지 — WeatherSheetContent 의 현재 날씨 요약(히어로 카드)
// 바로 아래에 관측 시각과 신선도(current/stale)를 정직하게 노출한다.
// record_time 이 없거나 망가졌거나 미래 skew 면 나이를 발명하지 않고
// '관측 시각 확인 중' 문구만 보여준다(절대 '방금 전' 아님).
// 고정 폭 Row 대신 Wrap 조합으로 좁은 화면/큰 텍스트에서도 넘치지 않게 감싼다.
import 'package:flutter/material.dart';

import '../weather_observation_freshness.dart';

class WeatherObservationBadge extends StatelessWidget {
  const WeatherObservationBadge({
    super.key,
    required this.recordTime,
    required this.language,
    this.now,
  });

  final String? recordTime;
  final String language;

  /// Clock dependency (clock dependency). In production it is always
  /// `DateTime.now()`; tests inject a fixed time to guarantee determinism. It is
  /// never used for anything other than freshness determination/labeling.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final info = weatherObservationInfo(
      recordTime: recordTime,
      now: now ?? DateTime.now(),
      language: language,
    );
    final isStale = info.freshness == WeatherObservationFreshness.stale;
    return Semantics(
      key: const ValueKey('weather-observed-time'),
      container: true,
      excludeSemantics: true,
      label: info.semanticsLabel,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(
            Icons.schedule,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          Text(
            info.label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (info.statusLabel.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isStale
                    ? const Color(0xFFFEF3C7)
                    : const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(999),
              ),
              // 고정 Row 대신 Wrap: 좁은 폭/큰 텍스트에서 칩 안 텍스트가 줄바꿈된다.
              child: Wrap(
                spacing: 4,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isStale
                          ? const Color(0xFFB7791F)
                          : const Color(0xFF2F855A),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    info.statusLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isStale
                          ? const Color(0xFF92400E)
                          : const Color(0xFF166534),
                      fontWeight: FontWeight.w800,
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
