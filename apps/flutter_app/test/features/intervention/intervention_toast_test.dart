// P6G §03: InterventionToast presentational 위젯 상태 검증.
// - KO/EN 배타 라벨/버튼/닫기 tooltip.
// - onOpenPlanner / onDismiss 콜백 정확히 1회.
// - 긴 라벨 maxLines:2 + ellipsis 오버플로 안전.
// - ConstrainedBox maxWidth 430 준수.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/features/intervention/widgets/intervention_toast.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets(
    'KO: shows the label, plan button and close tooltip exclusively',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          InterventionToast(
            label: '비 내릴 확률이 높아요.',
            language: 'ko',
            onOpenPlanner: () {},
            onDismiss: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('비 내릴 확률이 높아요.'), findsOneWidget);
      expect(find.text('일정 보기'), findsOneWidget);
      expect(find.byTooltip('닫기'), findsOneWidget);
      // KO·EN 배타: 영어 카피가 섞이지 않는다.
      expect(find.text('Plan'), findsNothing);
      expect(find.byTooltip('Close'), findsNothing);
    },
  );

  testWidgets(
    'EN: shows the label, plan button and close tooltip exclusively',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          InterventionToast(
            label: 'Rain is likely.',
            language: 'en',
            onOpenPlanner: () {},
            onDismiss: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Rain is likely.'), findsOneWidget);
      expect(find.text('Plan'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('일정 보기'), findsNothing);
      expect(find.byTooltip('닫기'), findsNothing);
    },
  );

  testWidgets('plan button invokes onOpenPlanner exactly once', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _wrap(
        InterventionToast(
          label: '라벨',
          language: 'ko',
          onOpenPlanner: () => calls += 1,
          onDismiss: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('intervention-toast-plan')));
    await tester.pump();

    expect(calls, 1);
  });

  testWidgets('close button invokes onDismiss exactly once', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _wrap(
        InterventionToast(
          label: '라벨',
          language: 'ko',
          onOpenPlanner: () {},
          onDismiss: () => calls += 1,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('intervention-toast-close')));
    await tester.pump();

    expect(calls, 1);
  });

  testWidgets('long label is capped at 2 lines with ellipsis (overflow-safe)', (
    tester,
  ) async {
    final longLabel = '비 내릴 확률이 높아요. 우산을 챙기세요. ' * 12;
    await tester.pumpWidget(
      _wrap(
        InterventionToast(
          label: longLabel,
          language: 'ko',
          onOpenPlanner: () {},
          onDismiss: () {},
        ),
      ),
    );
    await tester.pump();

    final text = tester.widget<Text>(find.text(longLabel));
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('toast respects the 430 maxWidth constraint', (tester) async {
    final longLabel = '비 내릴 확률이 높아요. 우산을 챙기세요. ' * 24;
    await tester.pumpWidget(
      _wrap(
        InterventionToast(
          label: longLabel,
          language: 'ko',
          onOpenPlanner: () {},
          onDismiss: () {},
        ),
      ),
    );
    await tester.pump();

    final width = tester.getSize(find.byType(InterventionToast)).width;
    expect(width, lessThanOrEqualTo(430));
  });
}
