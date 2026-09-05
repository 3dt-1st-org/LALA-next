// Open-vector embed bridge/callback compatibility (Draft #187 checkpoint).
// The open embed must speak the exact same provider-neutral bridge contract
// the NAVER path already feeds into `decodeLalaMapCameraIdlePayload` and the
// placeTap handler: cameraIdle payloads (map + JSON string transports) with
// SW/NE bounds, placeTap payloads, and zoom/level conversion parity.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/lala_map_models.dart';
import 'package:lala_next_app/lala_map_provider.dart';

void main() {
  group('open-vector cameraIdle payloads decode through the shared SSOT', () {
    test('native (decoded map) payload with bounds', () {
      // Shape produced by open-map-embed.html onMoveEnd (maplibre
      // getCenter/getBounds/getZoom), including the 750 ms suppression gate.
      final camera = decodeLalaMapCameraIdlePayload(<String, dynamic>{
        'source': 'lala-open-map',
        'bridgeId': 'lala-open-map-0-bridge',
        'type': 'cameraIdle',
        'lat': 37.5663,
        'lng': 126.9779,
        'level': 6,
        'sw_lat': 37.4832,
        'sw_lng': 126.8591,
        'ne_lat': 37.6494,
        'ne_lng': 127.0967,
      });
      expect(camera, isNotNull);
      expect(camera!.lat, closeTo(37.5663, 1e-9));
      expect(camera.lng, closeTo(126.9779, 1e-9));
      expect(camera.level, 6);
      expect(camera.bounds, isNotNull);
      expect(camera.bounds!.swLat, closeTo(37.4832, 1e-9));
      expect(camera.bounds!.swLng, closeTo(126.8591, 1e-9));
      expect(camera.bounds!.neLat, closeTo(37.6494, 1e-9));
      expect(camera.bounds!.neLng, closeTo(127.0967, 1e-9));
    });

    test('web (JSON string postMessage) payload with bounds', () {
      final camera = decodeLalaMapCameraIdlePayload(jsonEncode({
        'source': 'lala-open-map',
        'bridgeId': 'lala-open-map-0-bridge',
        'type': 'cameraIdle',
        'lat': 37.5663,
        'lng': 126.9779,
        'level': 6,
        'sw_lat': 37.4832,
        'sw_lng': 126.8591,
        'ne_lat': 37.6494,
        'ne_lng': 127.0967,
      }));
      expect(camera, isNotNull);
      expect(camera!.bounds, isNotNull);
      expect(camera.bounds!.neLat, closeTo(37.6494, 1e-9));
    });

    test('numeric-string coercion matches provider bridges', () {
      final camera = decodeLalaMapCameraIdlePayload(<String, dynamic>{
        'type': 'cameraIdle',
        'lat': '37.5663',
        'lng': '126.9779',
        'level': '6',
        'sw_lat': '37.4832',
        'sw_lng': '126.8591',
        'ne_lat': '37.6494',
        'ne_lng': '127.0967',
      });
      expect(camera, isNotNull);
      expect(camera!.level, 6);
      expect(camera.bounds, isNotNull);
    });
  });

  group('open-vector non-camera payloads route to the placeTap handler', () {
    test('placeTap payload is not misread as a camera idle', () {
      final camera = decodeLalaMapCameraIdlePayload(<String, dynamic>{
        'source': 'lala-open-map',
        'bridgeId': 'bridge',
        'type': 'placeTap',
        'placeId': 'place-42',
      });
      expect(camera, isNull);
    });

    test('mapError payload is not misread as a camera idle', () {
      // Includes the honest no_multilingual_labels blocker code.
      for (final code in <String>[
        'style_load',
        'style_timeout',
        'runtime',
        'runtime_missing',
        'no_multilingual_labels',
      ]) {
        final camera = decodeLalaMapCameraIdlePayload(<String, dynamic>{
          'source': 'lala-open-map',
          'bridgeId': 'bridge',
          'type': 'mapError',
          'code': code,
        });
        expect(camera, isNull, reason: 'code: $code');
      }
    });
  });

  group('zoom/level conversion parity with the NAVER path', () {
    test('embed min/max zoom map onto the LALA level contract', () {
      // open-map-embed.html clamps MapLibre zoom into [9, 17], the exact
      // image of levels [10, 2] under the shared 19 - level conversion.
      expect(lalaMapLevelToNaverZoom(2), 17);
      expect(lalaMapLevelToNaverZoom(10), 9);
      expect(naverZoomToLalaMapLevel(17), 2);
      expect(naverZoomToLalaMapLevel(9), 10);
      expect(naverZoomToLalaMapLevel(3.7), 15.clamp(2, 10));
      expect(naverZoomToLalaMapLevel(24), 2);
      expect(naverZoomToLalaMapLevel(-5), 10);
    });
  });

  group('bridge source scoping', () {
    test('open-vector messages never claim the NAVER source marker', () {
      // The web/native handlers accept exactly the marker of the provider
      // they launched, so a cross-provider message cannot pass validation.
      expect(kLalaOpenMapBridgeSource, 'lala-open-map');
      expect(kLalaOpenMapBridgeSource, isNot('lala-naver-map'));
    });
  });
}
