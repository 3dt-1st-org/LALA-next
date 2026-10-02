import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

/// A place panel whose content and resize gestures share one scroll controller.
class DraggablePlaceDock extends StatefulWidget {
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
  State<DraggablePlaceDock> createState() => _DraggablePlaceDockState();
}

class _DraggablePlaceDockState extends State<DraggablePlaceDock> {
  final _controller = DraggableScrollableController();
  bool? _branchEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // StatefulShellRoute disables tickers for its inactive tab branches.
    final enabled = TickerMode.valuesOf(context).enabled;
    if (_branchEnabled == false && enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _branchEnabled == true && _controller.isAttached) {
          _controller.reset();
        }
      });
    }
    _branchEnabled = enabled;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final initial = (widget.initialHeight / box.maxHeight).clamp(0.12, 0.85);
      return NotificationListener<DraggableScrollableNotification>(
        onNotification: (event) {
          if (event.depth == 0 && event.extent <= 0.041) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) widget.onDismiss();
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
            controller: _controller,
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
                    child: widget.builder(context, controller, panel.maxHeight),
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
