import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../planner/widgets/planner_map_pill.dart';
import '../../weather/widgets/weather_map_pill.dart';

/// 지도 플로팅 유틸리티 컨트롤 행(플래너 + 날씨 필)(C3 추출 — main.dart 의 _MapUtilityControlRow).
class MapUtilityControlRow extends StatelessWidget {
  const MapUtilityControlRow({
    super.key,
    required this.dailyPlan,
    required this.weather,
    required this.language,
    required this.onOpenPlanner,
    required this.onOpenWeather,
  });

  final LalaDailyPlan? dailyPlan;
  final LalaWeather? weather;
  final String language;
  final VoidCallback onOpenPlanner;
  final VoidCallback onOpenWeather;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('map-utility-control-row'),
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: PlannerMapPill(
              dailyPlan: dailyPlan,
              language: language,
              onPressed: onOpenPlanner,
            ),
          ),
        ),
        const SizedBox(width: 46),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: WeatherMapPill(
              key: const ValueKey('weather-pill'),
              weather: weather,
              language: language,
              onPressed: onOpenWeather,
            ),
          ),
        ),
      ],
    );
  }
}
