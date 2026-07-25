// Wave-1 location/weather: focused unit tests for the region context and the
// permanently-denied permission status.
//
// - RegionContext carries coordinates, a stable region id, exclusive ko/en
//   labels, and a source (current/manual/default).
// - RegionContextStore publishes a choice across the app shell and reverts.
// - permanentlyDenied is a status distinct from denied/unavailable/found so the
//   UI can route to settings instead of silently re-prompting.
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/manual_location_options.dart';

ManualLocationOption _busanOption() {
  return const ManualLocationOption(
    id: 'busan-haeundae',
    provinceId: 'busan',
    provinceKo: '부산광역시',
    provinceEn: 'Busan',
    labelKo: '해운대구',
    labelEn: 'Haeundae-gu',
    lat: 35.16,
    lng: 129.16,
  );
}

void main() {
  group('RegionContext', () {
    test('current carries coordinates and a current source', () {
      final context = RegionContext.current(lat: 37.1, lng: 127.1);
      expect(context.source, RegionSource.current);
      expect(context.isDefault, isFalse);
      expect(context.regionId, 'current');
      expect(context.lat, 37.1);
      expect(context.lng, 127.1);
    });

    test('manual carries the option id, coordinates and exclusive labels', () {
      final context = RegionContext.manual(_busanOption());
      expect(context.source, RegionSource.manual);
      expect(context.regionId, 'busan-haeundae');
      expect(context.lat, 35.16);
      expect(context.lng, 129.16);
      // Labels are exclusive per language (no mixing).
      expect(context.label('ko'), '해운대구');
      expect(context.label('en'), 'Haeundae-gu');
    });

    test('equality is by coordinates, region id and source', () {
      expect(
        RegionContext.current(lat: 37.0, lng: 127.0),
        RegionContext.current(lat: 37.0, lng: 127.0),
      );
      // Same coords but different source are distinct contexts.
      expect(
        RegionContext.current(lat: 35.16, lng: 129.16),
        isNot(RegionContext.manual(_busanOption())),
      );
    });
  });

  group('RegionContextStore', () {
    setUp(RegionContextStore.clear);

    test('starts with no real context (disclosed default)', () {
      expect(RegionContextStore.current, isNull);
    });

    test('publishes a manual choice and reverts on clear', () {
      RegionContextStore.set(RegionContext.manual(_busanOption()));
      expect(RegionContextStore.current?.regionId, 'busan-haeundae');
      RegionContextStore.clear();
      expect(RegionContextStore.current, isNull);
    });

    test('notifies listeners on set and clear', () {
      final seen = <String?>[];
      RegionContextStore.listenable.addListener(() {
        seen.add(RegionContextStore.current?.regionId);
      });
      RegionContextStore.set(RegionContext.manual(_busanOption()));
      RegionContextStore.clear();
      expect(seen, <String?>['busan-haeundae', null]);
    });
  });

  group('LalaLocationResultStatus', () {
    test('permanentlyDenied is distinct from denied and unavailable', () {
      expect(
        LalaLocationResultStatus.values.toSet(),
        containsAll(<LalaLocationResultStatus>{
          LalaLocationResultStatus.found,
          LalaLocationResultStatus.denied,
          LalaLocationResultStatus.permanentlyDenied,
          LalaLocationResultStatus.unavailable,
        }),
      );
      expect(
        LalaLocationResultStatus.permanentlyDenied ==
            LalaLocationResultStatus.denied,
        isFalse,
      );
    });

    test('permanentlyDenied result carries no location', () {
      const result = LalaLocationResult.permanentlyDenied();
      expect(result.status, LalaLocationResultStatus.permanentlyDenied);
      expect(result.location, isNull);
    });
  });
}
