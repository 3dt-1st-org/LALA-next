import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/features/planner/widgets/plan_timeline_entry.dart';

void main() {
  testWidgets('timeline connects middle slots without extending past ends', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: const <Widget>[
              PlanTimelineEntry(
                first: true,
                last: false,
                positionLabel: 'Plan stop 1 of 3',
                child: SizedBox(height: 72),
              ),
              PlanTimelineEntry(
                first: false,
                last: false,
                positionLabel: 'Plan stop 2 of 3',
                child: SizedBox(height: 72),
              ),
              PlanTimelineEntry(
                first: false,
                last: true,
                positionLabel: 'Plan stop 3 of 3',
                child: SizedBox(height: 72),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('plan-timeline-dot')), findsNWidgets(3));
    expect(
      find.byKey(const ValueKey('plan-timeline-line-before')),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const ValueKey('plan-timeline-line-after')),
      findsNWidgets(2),
    );
    expect(find.bySemanticsLabel('Plan stop 2 of 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
