import 'package:flutter/material.dart';

/// Connects plan cards into one readable day flow without changing slot data.
class PlanTimelineEntry extends StatelessWidget {
  const PlanTimelineEntry({
    super.key,
    required this.child,
    required this.first,
    required this.last,
    required this.positionLabel,
  });

  final Widget child;
  final bool first;
  final bool last;
  final String positionLabel;

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFCBD5E1);
    const accent = Color(0xFF0B67D8);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 28,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                if (!first)
                  const Positioned(
                    top: 0,
                    left: 13,
                    width: 2,
                    height: 28,
                    child: ColoredBox(
                      key: ValueKey('plan-timeline-line-before'),
                      color: line,
                    ),
                  ),
                if (!last)
                  const Positioned(
                    top: 28,
                    bottom: 0,
                    left: 13,
                    width: 2,
                    child: ColoredBox(
                      key: ValueKey('plan-timeline-line-after'),
                      color: line,
                    ),
                  ),
                Positioned(
                  top: 21,
                  left: 7,
                  child: Semantics(
                    label: positionLabel,
                    child: Container(
                      key: const ValueKey('plan-timeline-dot'),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: accent, width: 3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 10),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
