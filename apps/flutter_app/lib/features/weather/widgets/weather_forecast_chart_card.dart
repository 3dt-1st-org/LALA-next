import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../weather_helpers.dart';
import 'weather_forecast_chart_painter.dart';

/// 날씨 예보 추세선 차트 카드(C3 추출 — main.dart 의 _WeatherForecastChartCard).
class WeatherForecastChartCard extends StatelessWidget {
  const WeatherForecastChartCard({
    super.key,
    required this.items,
    required this.language,
  });

  final List<LalaForecastItem> items;
  final String language;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(8).toList(growable: false);
    final columnWidth = visibleItems.length <= 4 ? 72.0 : 62.0;
    final chartWidth = math.max(
      MediaQuery.sizeOf(context).width - 72,
      visibleItems.length * columnWidth,
    );
    final points = buildWeatherChartPoints(
      items: visibleItems,
      columnWidth: columnWidth,
      chartHeight: 96,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: chartWidth,
          child: Column(
            children: [
              SizedBox(
                height: 98,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: WeatherForecastChartPainter(points: points),
                      ),
                    ),
                    for (final point in points)
                      Positioned(
                        left: point.x - 18,
                        top: math.max(0, point.y - 26),
                        width: 36,
                        child: Text(
                          point.label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF1A202C),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  for (final item in visibleItems)
                    SizedBox(
                      width: columnWidth,
                      child: Icon(
                        weatherForecastIcon(item.icon),
                        size: 22,
                        color: const Color(0xFF2B6CB0),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (final item in visibleItems)
                    SizedBox(
                      width: columnWidth,
                      child: Text(
                        weatherChartTimeLabel(item.time, language: language),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
