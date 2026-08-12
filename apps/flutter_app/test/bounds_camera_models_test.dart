// V1 bounds-query (Lane B) — D4 model carrier tests.
// Covers KakaoMapBounds value equality and KakaoMapCamera.optional bounds.
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/kakao_map_models.dart';

void main() {
  group('KakaoMapBounds', () {
    test('value equality mirrors KakaoMapPlace semantics', () {
      const a = KakaoMapBounds(
        swLat: 37.0,
        swLng: 126.0,
        neLat: 38.0,
        neLng: 127.5,
      );
      const b = KakaoMapBounds(
        swLat: 37.0,
        swLng: 126.0,
        neLat: 38.0,
        neLng: 127.5,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality on any differing corner', () {
      const base = KakaoMapBounds(
        swLat: 37.0,
        swLng: 126.0,
        neLat: 38.0,
        neLng: 127.5,
      );
      expect(
        base ==
            const KakaoMapBounds(
              swLat: 37.1,
              swLng: 126.0,
              neLat: 38.0,
              neLng: 127.5,
            ),
        isFalse,
      );
      expect(
        base ==
            const KakaoMapBounds(
              swLat: 37.0,
              swLng: 126.0,
              neLat: 38.0,
              neLng: 127.6,
            ),
        isFalse,
      );
    });
  });

  group('KakaoMapCamera optional bounds', () {
    test('null bounds — center+radius fallback carrier (state B2)', () {
      const camera = KakaoMapCamera(lat: 37.26, lng: 127.03, level: 5);
      expect(camera.bounds, isNull);
    });

    test('round-trips bounds when supplied', () {
      const bounds = KakaoMapBounds(
        swLat: 37.0,
        swLng: 126.0,
        neLat: 38.0,
        neLng: 127.5,
      );
      const camera = KakaoMapCamera(
        lat: 37.5,
        lng: 126.75,
        level: 4,
        bounds: bounds,
      );
      expect(camera.bounds, isNotNull);
      expect(camera.bounds!.swLat, 37.0);
      expect(camera.bounds!.swLng, 126.0);
      expect(camera.bounds!.neLat, 38.0);
      expect(camera.bounds!.neLng, 127.5);
    });
  });
}
