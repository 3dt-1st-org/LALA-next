// V1 bounds-query (Lane B) — D5 trigger tests.
// shouldReloadPlacesForMapMove: reload fires on a pure zoom (level change) as
// well as a pan (center moved >= threshold). Legacy callers that omit the new
// optional level params keep the distance-only behavior (zero assertion change
// to widget_test.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/core/geo/geo_helpers.dart';

void main() {
  // Coordinates ~1.4 km apart (well over the 250 m default threshold).
  const farLat = 37.2636;
  const farLng = 127.0286;
  const movedLat = 37.2760;
  const movedLng = 127.0400;

  group('D5 level-changed OR-clause', () {
    test('reload fires on a pure zoom (center unchanged, level changed)', () {
      expect(
        shouldReloadPlacesForMapMove(
          hasAnyPlaces: true,
          lastFetchLat: farLat,
          lastFetchLng: farLng,
          currentLat: farLat,
          currentLng: farLng,
          lastFetchLevel: 5,
          currentLevel: 4,
        ),
        isTrue,
      );
    });

    test('no reload when center and level both unchanged', () {
      expect(
        shouldReloadPlacesForMapMove(
          hasAnyPlaces: true,
          lastFetchLat: farLat,
          lastFetchLng: farLng,
          currentLat: farLat,
          currentLng: farLng,
          lastFetchLevel: 5,
          currentLevel: 5,
        ),
        isFalse,
      );
    });

    test('reload still fires on pan beyond threshold regardless of level', () {
      expect(
        shouldReloadPlacesForMapMove(
          hasAnyPlaces: true,
          lastFetchLat: farLat,
          lastFetchLng: farLng,
          currentLat: movedLat,
          currentLng: movedLng,
          lastFetchLevel: 5,
          currentLevel: 5,
        ),
        isTrue,
      );
    });
  });

  group('legacy callers (no level params) — behavior unchanged', () {
    test('first fetch always reloads', () {
      expect(
        shouldReloadPlacesForMapMove(
          hasAnyPlaces: false,
          lastFetchLat: farLat,
          lastFetchLng: farLng,
          currentLat: farLat,
          currentLng: farLng,
        ),
        isTrue,
      );
    });

    test('small move under threshold does not reload', () {
      expect(
        shouldReloadPlacesForMapMove(
          hasAnyPlaces: true,
          lastFetchLat: farLat,
          lastFetchLng: farLng,
          currentLat: farLat + 0.0004,
          currentLng: farLng + 0.0004,
        ),
        isFalse,
      );
    });

    test('move beyond threshold reloads', () {
      expect(
        shouldReloadPlacesForMapMove(
          hasAnyPlaces: true,
          lastFetchLat: farLat,
          lastFetchLng: farLng,
          currentLat: movedLat,
          currentLng: movedLng,
        ),
        isTrue,
      );
    });
  });
}
