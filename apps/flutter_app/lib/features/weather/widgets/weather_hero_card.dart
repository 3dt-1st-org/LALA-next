import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/place_labels.dart';
import '../../../shared/labels/source_label.dart';
import '../../place/widgets/proof_chip.dart';
import '../weather_helpers.dart';

/// 날씨 히어로 카드(C3 추출 — main.dart 의 _WeatherHeroCard).
/// S-14: 고정 Row 는 320dp + TextScaler.linear(2) 에서 출처 칩이 넘쳤다.
/// 넓은 폭에서는 종전과 동일한 배치(아이콘·텍스트 좌측, 칩 우측 고정)를
/// 유지하고, 좁은 폭/큰 텍스트에서는 칩이 아래 run 으로 감싸지는 Wrap 조합.
class WeatherHeroCard extends StatelessWidget {
  const WeatherHeroCard({
    super.key,
    required this.weather,
    required this.language,
  });

  final LalaWeather weather;
  final String language;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 아이콘(42) + 간격(14) 을 제외한 텍스트 폭 상한 — 미래 날짜/긴 지역명이
          // 카드를 벗어나지 않게 한다.
          final maxWidth = constraints.maxWidth;
          final textColumnMaxWidth = math.max(
            0.0,
            maxWidth.isFinite ? maxWidth - 42 - 14 : 240.0,
          );
          return Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 10,
            children: [
              Wrap(
                spacing: 14,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(
                    Icons.wb_cloudy_outlined,
                    size: 42,
                    color: Color(0xFF2B6CB0),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: textColumnMaxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          locationLabel(weather.location, language),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        // P1: 빈 온도는 큰 '-' 헤드라인으로 보이지 않고, 야외 상태로 대체.
                        Text(
                          temperatureLabelOrNull(weather.temp) ??
                              outdoorLabel(
                                weather.outdoorStatus,
                                language: language,
                              ),
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: const Color(0xFF111827),
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              ProofChip(
                key: const ValueKey('weather-source-chip'),
                label: weatherSourceLabel(weather.source, language: language),
              ),
            ],
          );
        },
      ),
    );
  }
}
