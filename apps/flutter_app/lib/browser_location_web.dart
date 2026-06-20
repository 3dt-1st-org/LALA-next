import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'browser_location_result.dart';

Future<BrowserLocationResult> requestBrowserLocation(Duration timeout) {
  final geolocation = web.window.navigator.geolocation;
  final completer = Completer<BrowserLocationResult>();
  geolocation.getCurrentPosition(
    ((web.GeolocationPosition position) {
      final coords = position.coords;
      final lat = coords.latitude.toDouble();
      final lng = coords.longitude.toDouble();
      if (!completer.isCompleted) {
        completer.complete(BrowserLocationResult.found(lat: lat, lng: lng));
      }
    }).toJS,
    ((web.GeolocationPositionError error) {
      if (completer.isCompleted) {
        return;
      }
      if (error.code == 1) {
        completer.complete(const BrowserLocationResult.denied());
      } else {
        completer.complete(const BrowserLocationResult.unavailable());
      }
    }).toJS,
    web.PositionOptions(
      enableHighAccuracy: true,
      timeout: timeout.inMilliseconds,
      maximumAge: 0,
    ),
  );

  return completer.future.timeout(
    timeout,
    onTimeout: () => const BrowserLocationResult.unavailable(),
  );
}
