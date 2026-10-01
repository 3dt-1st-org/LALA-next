import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/features/map/widgets/draggable_place_dock.dart';

void main() {
  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('place dock expands and dismisses with $kind', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DraggablePlaceDock(
              initialHeight: 180,
              onDismiss: () => dismissed = true,
              builder: (context, controller, height) => Container(
                key: const ValueKey('panel'),
                color: Colors.white,
                child: ListView(
                  controller: controller,
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 80, child: Text('Handle')),
                    Text('Place'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(const ValueKey('panel'))).width, 800);
      await tester.drag(find.text('Handle'), const Offset(0, -500), kind: kind);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('panel'))).height, 600);
      await tester.drag(find.text('Handle'), const Offset(0, 650), kind: kind);
      await tester.pumpAndSettle();
      expect(dismissed, isTrue);
    });
  }
}
