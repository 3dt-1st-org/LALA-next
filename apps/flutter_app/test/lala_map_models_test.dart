import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/lala_map_models.dart';

void main() {
  test('sameLalaMapPlaces treats equivalent rebuilt markers as unchanged', () {
    final first = <LalaMapPlace>[
      const LalaMapPlace(
        id: 'place-1',
        name: '서울도서관',
        category: 'culture_venue',
        lat: 37.5665,
        lng: 126.9780,
        selected: true,
      ),
      const LalaMapPlace(
        id: 'cluster-1',
        name: '추천 3곳',
        category: 'event',
        lat: 37.5670,
        lng: 126.9790,
        clusterCount: 3,
        clusterMemberIds: <String>['a', 'b', 'c'],
      ),
    ];

    final rebuilt = <LalaMapPlace>[
      const LalaMapPlace(
        id: 'place-1',
        name: '서울도서관',
        category: 'culture_venue',
        lat: 37.5665,
        lng: 126.9780,
        selected: true,
      ),
      const LalaMapPlace(
        id: 'cluster-1',
        name: '추천 3곳',
        category: 'event',
        lat: 37.5670,
        lng: 126.9790,
        clusterCount: 3,
        clusterMemberIds: <String>['a', 'b', 'c'],
      ),
    ];

    expect(identical(first, rebuilt), isFalse);
    expect(sameLalaMapPlaces(first, rebuilt), isTrue);
  });

  test(
    'sameLalaMapPlaces detects marker state changes that require rerender',
    () {
      final previous = <LalaMapPlace>[
        const LalaMapPlace(
          id: 'place-1',
          name: '서울도서관',
          category: 'culture_venue',
          lat: 37.5665,
          lng: 126.9780,
        ),
      ];

      final changed = <LalaMapPlace>[
        const LalaMapPlace(
          id: 'place-1',
          name: '서울도서관',
          category: 'culture_venue',
          lat: 37.5665,
          lng: 126.9780,
          selected: true,
        ),
      ];

      expect(sameLalaMapPlaces(previous, changed), isFalse);
    },
  );

  test('converts LALA level to NAVER zoom without changing app semantics', () {
    expect(lalaMapLevelToNaverZoom(2), 17);
    expect(lalaMapLevelToNaverZoom(6), 13);
    expect(lalaMapLevelToNaverZoom(10), 9);
    expect(lalaMapLevelToNaverZoom(0), 17);
    expect(lalaMapLevelToNaverZoom(99), 9);
  });

  test('converts NAVER zoom back to a clamped LALA level', () {
    expect(naverZoomToLalaMapLevel(17), 2);
    expect(naverZoomToLalaMapLevel(13), 6);
    expect(naverZoomToLalaMapLevel(9), 10);
    expect(naverZoomToLalaMapLevel(22), 2);
    expect(naverZoomToLalaMapLevel(1), 10);
  });
}
