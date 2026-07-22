import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';

/// 행사 진행 상태 필(C3 추출 — main.dart 의 _EventStatusPill).
class EventStatusPill extends StatelessWidget {
  const EventStatusPill({super.key, required this.isOngoing, required this.language});

  final bool isOngoing;
  final String language;

  @override
  Widget build(BuildContext context) {
    final color = isOngoing ? const Color(0xFF2B6CB0) : const Color(0xFF94A3B8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Text(
        isOngoing
            ? lalaCopy(language, ko: '진행 중', en: 'Ongoing')
            : lalaCopy(language, ko: '종료', en: 'Ended'),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}
