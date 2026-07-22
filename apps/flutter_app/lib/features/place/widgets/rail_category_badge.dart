import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../place_helpers.dart';

/// 레일 카드용 카테고리 배지(C3 추출 — main.dart 의 _RailCategoryBadge).
class RailCategoryBadge extends StatelessWidget {
  const RailCategoryBadge({super.key, required this.place, required this.language});

  final LalaPlace place;
  final String language;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(place.category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        railCategoryLabel(place, language),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}
