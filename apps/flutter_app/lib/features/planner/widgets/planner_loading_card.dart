import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';

/// 일정 생성 로딩 카드(C3 추출 — main.dart 의 _PlannerLoadingCard).
/// 일정 슬롯이 비어 있을 때 보여주는 인디케이터 + 안내 문구.
class PlannerLoadingCard extends StatelessWidget {
  const PlannerLoadingCard({super.key, required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lalaCopy(
                    language,
                    ko: '일정을 생성하는 중...',
                    en: 'Generating your daily plan...',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF1E293B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  lalaCopy(
                    language,
                    ko: '처음 방문하는 장소는 최대 5~10초 소요돼요',
                    en: 'New locations may take 5-10 seconds.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
