import 'package:flutter/material.dart';

import 'kakao_map_models.dart';

Widget buildKakaoMapView({
  required String javascriptKey,
  required double centerLat,
  required double centerLng,
  required int level,
  required List<KakaoMapPlace> places,
  ValueChanged<String>? onPlaceTap,
}) {
  return Container(
    color: const Color(0xFFEAF2FB),
    alignment: Alignment.center,
    child: Semantics(
      label: 'Kakao Map API fallback',
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              blurRadius: 18,
              offset: Offset(0, 8),
              color: Color(0x18000000),
            ),
          ],
        ),
        child: const Text(
          'Kakao Map API',
          style: TextStyle(
            color: Color(0xFF1A202C),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ),
  );
}
