import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

/// A place panel whose content and resize gestures share one scroll controller.
class DraggablePlaceDock extends StatelessWidget {
  const DraggablePlaceDock({
    super.key,
    required this.initialHeight,
    required this.onDismiss,
    required this.builder,
  });
  final double initialHeight;
  final VoidCallback onDismiss;
  final Widget Function(BuildContext, ScrollController, double) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final initial = (initialHeight / box.maxHeight).clamp(0.12, 0.85);
      return NotificationListener<DraggableScrollableNotification>(
        onNotification: (event) {
          if (event.depth == 0 && event.extent <= 0.041) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) onDismiss();
            });
          }
          return false;
        },
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              ...ScrollConfiguration.of(context).dragDevices,
              PointerDeviceKind.mouse,
            },
          ),
          child: DraggableScrollableSheet(
            initialChildSize: initial,
            minChildSize: 0.04,
            maxChildSize: 1,
            snap: true,
            snapSizes: [initial],
            builder: (context, controller) => LayoutBuilder(
              builder: (context, panel) {
                return Center(
                  child: SizedBox(
                    width: box.maxWidth,
                    child: builder(context, controller, panel.maxHeight),
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
  );
}
