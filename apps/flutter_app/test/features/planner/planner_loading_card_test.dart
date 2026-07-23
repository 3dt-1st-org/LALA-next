import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/features/planner/widgets/planner_loading_card.dart';

void main() {
  testWidgets(
    'renders one truthful preparation card with accessible progress',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: const PlannerLoadingCard(language: 'ko'))),
      );

      // 단일 카드만(중복 렌더 금지).
      expect(find.byKey(const ValueKey('planner-loading-card')), findsOneWidget);

      // 진실된 중립 준비 문구(백엔드 단계 시그널이 없으므로 추정 단계 아님).
      expect(find.text('오늘 일정을 준비하고 있어요'), findsOneWidget);

      // 접근 가능 진행 표시: 비율 미정(indeterminate) 바.
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // 타이머 기반 가짜 단계/취소 문구는 없어야 한다.
      expect(find.text('장소 고르는 중'), findsNothing);
      expect(find.text('동선 정리 중'), findsNothing);
      expect(find.textContaining('취소'), findsNothing);
      expect(find.textContaining('진행'), findsNothing);
    },
  );

  testWidgets('keeps English neutral copy working', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: const PlannerLoadingCard(language: 'en'))),
    );
    expect(find.text('Preparing your daily plan'), findsOneWidget);
    expect(find.textContaining('준비'), findsNothing);
  });
}
