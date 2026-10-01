import 'package:flutter/widgets.dart';

/// September 13 MVP: preserve deferred implementations without exposing them.
class LalaProductScope extends InheritedWidget {
  const LalaProductScope({
    super.key,
    required this.meetingMvp,
    required super.child,
  });

  final bool meetingMvp;

  static bool isMeetingMvp(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<LalaProductScope>()
          ?.meetingMvp ??
      false;

  @override
  bool updateShouldNotify(LalaProductScope oldWidget) =>
      meetingMvp != oldWidget.meetingMvp;
}
