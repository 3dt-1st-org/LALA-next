import 'package:flutter/material.dart';

/// 날씨 예보 차트의 데이터 점(C3-2 추출 — 자급자족형).
class WeatherChartPoint {
  const WeatherChartPoint({
    required this.x,
    required this.y,
    required this.label,
  });

  final double x;
  final double y;
  final String label;
}

/// 날씨 예보 추세선 차트 페인터(Flutter 페인팅만 사용, 외부 helper 의존 없음).
class WeatherForecastChartPainter extends CustomPainter {
  const WeatherForecastChartPainter({required this.points});

  final List<WeatherChartPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    for (final y in <double>[26, 52, 78]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (points.isEmpty) {
      return;
    }

    final path = Path()..moveTo(points.first.x, points.first.y);
    for (var index = 1; index < points.length; index += 1) {
      final previous = points[index - 1];
      final current = points[index];
      final midX = (previous.x + current.x) / 2;
      path.cubicTo(midX, previous.y, midX, current.y, current.x, current.y);
    }

    final linePaint = Paint()
      ..color = const Color(0xFF2B6CB0)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);

    final fillPaint = Paint()..color = const Color(0xFFF5C842);
    final strokePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    for (final point in points) {
      final offset = Offset(point.x, point.y);
      canvas.drawCircle(offset, 5.5, fillPaint);
      canvas.drawCircle(offset, 5.5, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant WeatherForecastChartPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
