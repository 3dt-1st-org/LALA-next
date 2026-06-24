import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

int _eventCount = 0;

void publishLalaSmokeState(Map<String, Object?> state) {
  web.window.setProperty('__lalaAppState'.toJS, state.jsify());
}

void publishLalaSmokeEvent(Map<String, Object?> event) {
  _eventCount += 1;
  final payload = <String, Object?>{
    'count': _eventCount,
    'latest': <String, Object?>{
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      ...event,
    },
  };
  web.window.setProperty('__lalaAppEvent'.toJS, payload.jsify());
}
