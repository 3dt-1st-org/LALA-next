import 'package:flutter/material.dart';

import '../place_helpers.dart';

/// 장소 카테고리 배지(C3 추출 — main.dart 의 _CategoryBadge).
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.category, this.language = 'ko'});

  final String category;
  final String language;

  @override
  Widget build(BuildContext context) {
    final color = switch (category) {
      'attraction' => const Color(0xFFC53030),
      'restaurant' => const Color(0xFFF5C842),
      'event' => const Color(0xFF2B6CB0),
      'culture_venue' => const Color(0xFF0F766E),
      _ => const Color(0xFF1A202C),
    };
    final textColor = category == 'restaurant'
        ? const Color(0xFF1A202C)
        : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        categoryLabel(category, language: language),
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
