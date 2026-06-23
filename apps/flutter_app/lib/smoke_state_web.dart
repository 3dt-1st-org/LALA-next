import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

void publishLalaSmokeState(Map<String, Object?> state) {
  web.window.setProperty('__lalaAppState'.toJS, state.jsify());
}
