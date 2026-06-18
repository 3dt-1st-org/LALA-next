import 'package:flutter/material.dart';

import 'kakao_map_models.dart';

class KakaoMapFallbackView extends StatelessWidget {
  const KakaoMapFallbackView({
    super.key,
    required this.message,
    required this.language,
    required this.centerLat,
    required this.centerLng,
    required this.places,
    this.onPlaceTap,
  });

  final String message;
  final String language;
  final double centerLat;
  final double centerLng;
  final List<KakaoMapPlace> places;
  final ValueChanged<String>? onPlaceTap;

  @override
  Widget build(BuildContext context) {
    final visiblePlaces = places.take(40).toList(growable: false);
    return ColoredBox(
      key: ValueKey(
        'kakao-map-fallback-center-${centerLat.toStringAsFixed(4)}-${centerLng.toStringAsFixed(4)}',
      ),
      color: const Color(0xFFEAF2FB),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _FallbackMapPainter())),
          for (final place in visiblePlaces)
            _FallbackMarker(
              place: place,
              language: language,
              position: _fallbackPosition(
                lat: place.lat,
                lng: place.lng,
                centerLat: centerLat,
                centerLng: centerLng,
              ),
              onTap: onPlaceTap == null
                  ? null
                  : () => onPlaceTap?.call(place.id),
            ),
          Center(
            child: Semantics(
              label: language == 'en' ? 'Map preview' : '지도 미리보기',
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 18,
                      offset: Offset(0, 8),
                      color: Color(0x18000000),
                    ),
                  ],
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF1A202C),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FallbackMarker extends StatelessWidget {
  const _FallbackMarker({
    required this.place,
    required this.language,
    required this.position,
    required this.onTap,
  });

  final KakaoMapPlace place;
  final String language;
  final ({double x, double y}) position;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final size = place.isCluster ? 48.0 : (place.selected ? 42.0 : 34.0);
    final screenSize = MediaQuery.sizeOf(context);
    final marker = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (place.selected && !place.isCluster) ...[
          Container(
            constraints: const BoxConstraints(maxWidth: 132),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF111827).withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 18,
                  offset: Offset(0, 6),
                  color: Color(0x2E0F172A),
                ),
              ],
            ),
            child: Text(
              place.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 5),
        ],
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: place.isCluster
                ? Border.all(color: _markerColor(place.category), width: 2.2)
                : null,
            boxShadow: const [
              BoxShadow(
                blurRadius: 14,
                offset: Offset(0, 4),
                color: Color(0x380F172A),
              ),
            ],
          ),
          child: place.isCluster
              ? Text(
                  '${place.clusterCount}',
                  style: TextStyle(
                    color: _markerTextColor(place.category),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                )
              : Container(
                  width: size * 0.64,
                  height: size * 0.64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _markerColor(place.category),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Icon(
                    _markerIcon(place.category),
                    color: place.category == 'event'
                        ? const Color(0xFF1A202C)
                        : Colors.white,
                    size: place.selected ? 15 : 13,
                  ),
                ),
        ),
      ],
    );

    return Positioned(
      left: screenSize.width * position.x / 100,
      top: screenSize.height * position.y / 100,
      child: Transform.translate(
        offset: Offset(-size / 2, place.selected ? -size - 34 : -size / 2),
        child: Semantics(
          button: onTap != null,
          label: place.isCluster
              ? (language == 'en'
                    ? '${place.clusterCount} places'
                    : '${place.clusterCount}곳')
              : place.name,
          child: GestureDetector(
            key: ValueKey('kakao-map-marker-${place.id}'),
            onTap: onTap,
            child: marker,
          ),
        ),
      ),
    );
  }
}

class _FallbackMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFEAF7EE), Color(0xFFF8FAFC), Color(0xFFE7F1FF)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final parkPaint = Paint()..color = const Color(0x3322C55E);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.16, size.height * 0.24),
        width: size.width * 0.34,
        height: size.height * 0.26,
      ),
      parkPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.80, size.height * 0.72),
        width: size.width * 0.28,
        height: size.height * 0.22,
      ),
      parkPaint,
    );

    final roadPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.78)
      ..strokeWidth = 22
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final roadPath = Path()
      ..moveTo(size.width * -0.1, size.height * 0.76)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.52,
        size.width * 0.54,
        size.height * 0.58,
        size.width * 1.1,
        size.height * 0.36,
      );
    canvas.drawPath(roadPath, roadPaint);

    final sideRoadPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.58)
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.34, size.height * -0.1),
      Offset(size.width * 0.72, size.height * 1.1),
      sideRoadPaint,
    );

    final riverPaint = Paint()..color = const Color(0x292B6CB0);
    final riverPath = Path()
      ..moveTo(size.width * -0.1, size.height * 0.62)
      ..quadraticBezierTo(
        size.width * 0.38,
        size.height * 0.72,
        size.width * 1.1,
        size.height * 0.56,
      )
      ..lineTo(size.width * 1.1, size.height * 0.66)
      ..quadraticBezierTo(
        size.width * 0.42,
        size.height * 0.82,
        size.width * -0.1,
        size.height * 0.70,
      )
      ..close();
    canvas.drawPath(riverPath, riverPaint);
  }

  @override
  bool shouldRepaint(covariant _FallbackMapPainter oldDelegate) => false;
}

({double x, double y}) _fallbackPosition({
  required double lat,
  required double lng,
  required double centerLat,
  required double centerLng,
}) {
  final x = 50 + ((lng - centerLng) * 7200);
  final y = 50 - ((lat - centerLat) * 9000);
  return (x: x.clamp(8, 92).toDouble(), y: y.clamp(12, 82).toDouble());
}

Color _markerColor(String category) {
  return switch (category) {
    'restaurant' => const Color(0xFFC53030),
    'event' => const Color(0xFFF5C842),
    'culture_venue' => const Color(0xFF2B6CB0),
    'attraction' => const Color(0xFFD73333),
    _ => const Color(0xFF1A202C),
  };
}

Color _markerTextColor(String category) {
  if (category == 'restaurant') {
    return const Color(0xFF6B4F0D);
  }
  return switch (category) {
    'event' => const Color(0xFF2B6CB0),
    'culture_venue' => const Color(0xFF2B6CB0),
    'attraction' => const Color(0xFFD73333),
    _ => const Color(0xFF1A202C),
  };
}

IconData _markerIcon(String category) {
  return switch (category) {
    'restaurant' => Icons.restaurant,
    'event' => Icons.calendar_month,
    'culture_venue' => Icons.account_balance,
    'attraction' => Icons.account_balance,
    _ => Icons.place,
  };
}
