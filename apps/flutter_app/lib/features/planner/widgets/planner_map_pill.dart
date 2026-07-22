import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/widgets/small_status_pill.dart';

/// 하루 일정 진입 필(C3 추출 — main.dart 의 _PlannerMapPill).
/// 지도 컨트롤 행에서 일정 시트를 여는 버튼이다.
class PlannerMapPill extends StatelessWidget {
  const PlannerMapPill({
    super.key,
    required this.dailyPlan,
    required this.language,
    required this.onPressed,
  });

  final LalaDailyPlan? dailyPlan;
  final String language;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final slots = dailyPlan?.slots ?? const <LalaPlanSlot>[];
    return SmallStatusPill(
      key: const ValueKey('planner-pill-hit-target'),
      icon: Icons.event_note,
      label: language == 'en' ? 'Daily Plan' : '하루 일정',
      active: slots.isNotEmpty,
      onPressed: onPressed,
    );
  }
}
