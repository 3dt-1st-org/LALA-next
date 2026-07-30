import 'package:flutter/material.dart';

import '../place_helpers.dart';

/// 장소 카테고리 배지(C3 추출 — main.dart 의 _CategoryBadge).
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({
    super.key,
    required this.category,
    this.language = 'ko',
  });

  final String category;
  final String language;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(category);
    final textColor = categoryOnTextColor(category);
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
