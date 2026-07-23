import 'package:flutter/material.dart';

import '../../../app/lala_metrics.dart';
import '../../../shared/l10n/lala_copy.dart';

/// 일정 생성 로딩 카드.
///
/// 진실된 중립 준비 상태만 표시한다: 백엔드(createDailyPlan)는 단일 비동기 호출이라
/// 단계 시그널이 없으므로, 타이머 기반 클라이언트 추정(예: "장소 고르는 중")을
/// 실제 진행으로 위장하지 않는다. 대시보드 없는 비율 미정(indeterminate) 진행 바와
/// Semantics 로 준비 중임을 접근 가능하게 전달한다. 재시도는 실패 뷰에서만.
class PlannerLoadingCard extends StatelessWidget {
  const PlannerLoadingCard({super.key, required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    final title = lalaCopy(
      language,
      ko: '오늘 일정을 준비하고 있어요',
      en: 'Preparing your daily plan',
    );
    final subtitle = lalaCopy(
      language,
      ko: '추천 장소와 동선을 정리 중입니다.',
      en: 'Arranging recommended places and your route.',
    );
    return Semantics(
      container: true,
      label: title,
      child: Container(
        key: const ValueKey('planner-loading-card'),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(LalaMetrics.cardRadius),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF1E293B),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 비율 미정 진행 바: 특정 % 를 암시하지 않는 진실된 준비 표시.
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: const LinearProgressIndicator(minHeight: 4),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
