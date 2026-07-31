import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/core/navigation/local_signal_action.dart';

void main() {
  test(
    'action controller consumes a request once and collapses duplicates',
    () {
      final controller = LocalSignalActionController();
      var notifications = 0;
      controller.addListener(() => notifications++);
      const request = LocalSignalPlaceActionRequest(
        placeId: 'place-1',
        action: LocalSignalPlaceAction.viewPlace,
      );

      controller.dispatch(request);
      controller.dispatch(request);

      expect(notifications, 1);
      expect(controller.takePending(), request);
      expect(controller.takePending(), isNull);
    },
  );

  test('a newer typed action replaces an older pending action', () {
    final controller = LocalSignalActionController();
    const view = LocalSignalPlaceActionRequest(
      placeId: 'place-1',
      action: LocalSignalPlaceAction.viewPlace,
    );
    const plan = LocalSignalPlaceActionRequest(
      placeId: 'place-1',
      action: LocalSignalPlaceAction.addToPlan,
    );

    controller.dispatch(view);
    controller.dispatch(plan);

    expect(controller.takePending(), plan);
  });
}
