// V1 bounds-query (Lane B) — D4 bridge decode tests.
// Verifies the shared SSOT decode used by BOTH the native JS-channel path
// (lala_map_view_native.dart, decoded-map input) and the web DOM-event path
// (lala_map_view_web.dart, JSON-string input). Bounds parse when all four
// fields are present and omit (null) otherwise → center+radius fallback (B2).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/lala_map_models.dart';

void main() {
  group('decodeLalaMapCameraIdlePayload — native (decoded map) path', () {
    test('parses all four bounds fields when present', () {
      final camera = decodeLalaMapCameraIdlePayload(<String, dynamic>{
        'type': 'cameraIdle',
        'lat': 37.5,
        'lng': 126.9,
        'level': 4,
        'sw_lat': 37.0,
        'sw_lng': 126.0,
        'ne_lat': 38.0,
        'ne_lng': 127.8,
      });
      expect(camera, isNotNull);
      expect(camera!.lat, 37.5);
      expect(camera.lng, 126.9);
      expect(camera.level, 4);
      expect(camera.bounds, isNotNull);
      expect(camera.bounds!.swLat, 37.0);
      expect(camera.bounds!.swLng, 126.0);
      expect(camera.bounds!.neLat, 38.0);
      expect(camera.bounds!.neLng, 127.8);
    });

    test('omits bounds (null) when the four fields are absent', () {
      final camera = decodeLalaMapCameraIdlePayload(<String, dynamic>{
        'type': 'cameraIdle',
        'lat': 37.5,
        'lng': 126.9,
        'level': 4,
      });
      expect(camera, isNotNull);
      expect(camera!.bounds, isNull);
    });

    test('omits bounds when only some fields are present (all-or-none)', () {
      final camera = decodeLalaMapCameraIdlePayload(<String, dynamic>{
        'type': 'cameraIdle',
        'lat': 37.5,
        'lng': 126.9,
        'level': 4,
        'sw_lat': 37.0,
        'sw_lng': 126.0,
        // ne_lat / ne_lng missing
      });
      expect(camera, isNotNull);
      expect(camera!.bounds, isNull);
    });

    test('returns null for a non-cameraIdle message (placeId path)', () {
      final camera = decodeLalaMapCameraIdlePayload(<String, dynamic>{
        'placeId': 'place-42',
      });
      expect(camera, isNull);
    });

    test('returns null when lat/lng/level are missing', () {
      final camera = decodeLalaMapCameraIdlePayload(<String, dynamic>{
        'type': 'cameraIdle',
        'lat': 37.5,
      });
      expect(camera, isNull);
    });

    test('coerces numeric strings from provider bridge messages', () {
      final camera = decodeLalaMapCameraIdlePayload(<String, dynamic>{
        'type': 'cameraIdle',
        'lat': '37.5',
        'lng': '126.9',
        'level': '4',
        'sw_lat': '37.0',
        'sw_lng': '126.0',
        'ne_lat': '38.0',
        'ne_lng': '127.8',
      });
      expect(camera, isNotNull);
      expect(camera!.lat, 37.5);
      expect(camera.level, 4);
      expect(camera.bounds, isNotNull);
      expect(camera.bounds!.neLng, 127.8);
    });
  });

  group('decodeLalaMapCameraIdlePayload — web (JSON string) path', () {
    test('parses a JSON-string detail with bounds', () {
      final payload = jsonEncode({
        'lat': 37.5,
        'lng': 126.9,
        'level': 4,
        'sw_lat': 37.0,
        'sw_lng': 126.0,
        'ne_lat': 38.0,
        'ne_lng': 127.8,
      });
      final camera = decodeLalaMapCameraIdlePayload(payload);
      expect(camera, isNotNull);
      expect(camera!.bounds, isNotNull);
      expect(camera.bounds!.swLat, 37.0);
      expect(camera.bounds!.neLat, 38.0);
    });

    test('JSON-string detail without bounds → null bounds', () {
      final payload = jsonEncode({'lat': 37.5, 'lng': 126.9, 'level': 4});
      final camera = decodeLalaMapCameraIdlePayload(payload);
      expect(camera, isNotNull);
      expect(camera!.bounds, isNull);
    });

    test('malformed JSON string → null', () {
      expect(decodeLalaMapCameraIdlePayload('not-json'), isNull);
    });

    test('non-map payload → null', () {
      expect(decodeLalaMapCameraIdlePayload(42), isNull);
      expect(decodeLalaMapCameraIdlePayload(null), isNull);
    });
  });
}
