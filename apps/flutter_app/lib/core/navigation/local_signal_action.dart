import 'package:flutter/foundation.dart';

/// A typed, in-process hand-off from the Local Signals projection to the
/// existing map/detail/planner owner. It carries no coordinates or user data.
enum LocalSignalPlaceAction { viewPlace, addToPlan }

@immutable
class LocalSignalPlaceActionRequest {
  const LocalSignalPlaceActionRequest({
    required this.placeId,
    required this.action,
  });

  final String placeId;
  final LocalSignalPlaceAction action;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalSignalPlaceActionRequest &&
          other.placeId == placeId &&
          other.action == action;

  @override
  int get hashCode => Object.hash(placeId, action);
}

/// Single-flight action seam. The map shell consumes a request once; repeated
/// identical taps cannot create duplicate map/planner transitions.
class LocalSignalActionController extends ChangeNotifier {
  LocalSignalPlaceActionRequest? _pending;

  LocalSignalPlaceActionRequest? get pending => _pending;

  void dispatch(LocalSignalPlaceActionRequest request) {
    if (_pending == request) return;
    _pending = request;
    notifyListeners();
  }

  LocalSignalPlaceActionRequest? takePending() {
    final request = _pending;
    _pending = null;
    return request;
  }
}
