import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/features/search/widgets/search_results_skeleton.dart';
import 'package:lala_next_app/shared/widgets/skeleton_box.dart';

void main() {
  testWidgets('SkeletonBox renders an accessible shimmer placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SkeletonBox(width: 120, height: 16)),
      ),
    );
    expect(find.byType(SkeletonBox), findsOneWidget);
    expect(find.bySemanticsLabel('loading'), findsOneWidget);
  });

  testWidgets(
    'search loading renders 3 result-shaped skeletons with no mock places',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SearchResultsSkeleton())),
      );
      // 카드당 6개(배지·타이틀2·지역2·사진) × 3카드 = 18개 스켈레톤 박스.
      expect(find.byType(SkeletonBox), findsNWidgets(18));

      // 가짜 최근/인기/장소명·빈 스피너는 없어야 한다.
      expect(find.textContaining('최근'), findsNothing);
      expect(find.textContaining('인기'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}
