// 모바일 비주얼 계약(Slice C / 03-acceptance M1,M2): pin-first 클러스터 정책 검증.
// - 79 장소 + level 10 → 개별 핀(클러스터 없음).
// - 80+ 장소 + level 10 → 정책에 따라 실제 클러스터 허용.
// - 선택 마커는 클러스터가 활성일 때도 개별 핀으로 유지(01-flow §F2.5).
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/map/map_helpers.dart';

void main() {
  test('79 places at level 10 render individual pins with no cluster bubble', () {
    final places = List<LalaPlace>.generate(
      79,
      (i) => _place('pin-$i', 100 + i),
    );

    final markers = clusterMapPlacesForMap(
      places: places,
      selected: null,
      mapLevel: 10,
      language: 'ko',
    );

    expect(markers.where((m) => m.isCluster), isEmpty);
    // 정책 미충족 시 take(60) 까지 개별 핀으로 내보낸다.
    expect(markers.where((m) => !m.isCluster), hasLength(60));
  });

  test('80 places at level 10 may form a real cluster under the policy', () {
    final places = List<LalaPlace>.generate(
      80,
      (i) => _place('dense-$i', 100 + i),
    );

    final markers = clusterMapPlacesForMap(
      places: places,
      selected: null,
      mapLevel: 10,
      language: 'ko',
    );

    // 80곳 + level 10 → 클러스터 정책(places.length >= 80 && mapLevel >= 10) 활성.
    expect(markers.where((m) => m.isCluster), isNotEmpty);
    final cluster = markers.firstWhere((m) => m.isCluster);
    expect(cluster.clusterCount, greaterThan(1));
  });

  test('selected marker stays individual while clustering is active', () {
    final places = List<LalaPlace>.generate(
      80,
      (i) => _place('sel-$i', 100 + i),
    );
    final selected = places.first;

    final markers = clusterMapPlacesForMap(
      places: places,
      selected: selected,
      mapLevel: 10,
      language: 'ko',
    );

    final selectedMarkers = markers.where((m) => m.id == selected.placeId);
    expect(selectedMarkers, isNotEmpty);
    expect(selectedMarkers.every((m) => !m.isCluster), isTrue);
    expect(selectedMarkers.any((m) => m.selected), isTrue);
  });
}

LalaPlace _place(String id, int distanceM) {
  return LalaPlace(
    placeId: id,
    name: id,
    nameKo: id,
    category: 'restaurant',
    lat: 37.2800,
    lng: 127.0100,
    address: '경기도 수원시 팔달구 행궁동',
    regionKo: '수원',
    regionEn: 'Suwon',
    distanceM: distanceM,
    source: 'db',
    upstreamSource: 'tour_api',
  );
}
