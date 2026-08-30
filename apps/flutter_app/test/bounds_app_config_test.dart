// V1 bounds-query (Lane B) — D4 call-site carrier tests.
// LalaAppConfig.bounds: copyWith carries bounds; null preserves prior bounds.
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/lala_map_models.dart';

LalaAppConfig _base() => const LalaAppConfig(baseUri: 'https://example.test');

void main() {
  group('LalaAppConfig.bounds', () {
    test('defaults to null (center+radius fallback)', () {
      expect(_base().bounds, isNull);
    });

    test('copyWith(bounds:...) carries the viewport rectangle', () {
      const bounds = LalaMapBounds(
        swLat: 37.0,
        swLng: 126.0,
        neLat: 38.0,
        neLng: 127.5,
      );
      final config = _base().copyWith(bounds: bounds);
      expect(config.bounds, equals(bounds));
    });

    test('copyWith(bounds:null) preserves the prior bounds', () {
      const bounds = LalaMapBounds(
        swLat: 37.0,
        swLng: 126.0,
        neLat: 38.0,
        neLng: 127.5,
      );
      final config = _base().copyWith(bounds: bounds);
      // A subsequent copyWith that omits bounds (or passes null) keeps it.
      final threaded = config.copyWith(category: 'restaurant');
      expect(threaded.bounds, equals(bounds));
    });

    test('copyWith(other fields) does not disturb bounds', () {
      const bounds = LalaMapBounds(
        swLat: 37.0,
        swLng: 126.0,
        neLat: 38.0,
        neLng: 127.5,
      );
      final config = _base().copyWith(bounds: bounds, lat: 37.5, lng: 127.0);
      expect(config.bounds, equals(bounds));
      expect(config.lat, 37.5);
    });
  });
}
