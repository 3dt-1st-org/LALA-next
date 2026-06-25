import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/kakao_map_models.dart';

void main() {
  test('sameKakaoMapPlaces treats equivalent rebuilt markers as unchanged', () {
    final first = <KakaoMapPlace>[
      const KakaoMapPlace(
        id: 'place-1',
        name: '서울도서관',
        category: 'culture_venue',
        lat: 37.5665,
        lng: 126.9780,
        selected: true,
      ),
      const KakaoMapPlace(
        id: 'cluster-1',
        name: '추천 3곳',
        category: 'event',
        lat: 37.5670,
        lng: 126.9790,
        clusterCount: 3,
        clusterMemberIds: <String>['a', 'b', 'c'],
      ),
    ];

    final rebuilt = <KakaoMapPlace>[
      const KakaoMapPlace(
        id: 'place-1',
        name: '서울도서관',
        category: 'culture_venue',
        lat: 37.5665,
        lng: 126.9780,
        selected: true,
      ),
      const KakaoMapPlace(
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
    expect(sameKakaoMapPlaces(first, rebuilt), isTrue);
  });

  test('sameKakaoMapPlaces detects marker state changes that require rerender', () {
    final previous = <KakaoMapPlace>[
      const KakaoMapPlace(
        id: 'place-1',
        name: '서울도서관',
        category: 'culture_venue',
        lat: 37.5665,
        lng: 126.9780,
      ),
    ];

    final changed = <KakaoMapPlace>[
      const KakaoMapPlace(
        id: 'place-1',
        name: '서울도서관',
        category: 'culture_venue',
        lat: 37.5665,
        lng: 126.9780,
        selected: true,
      ),
    ];

    expect(sameKakaoMapPlaces(previous, changed), isFalse);
  });
}
