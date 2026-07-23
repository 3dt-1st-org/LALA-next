import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/features/map/map_helpers.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

/// clusterMapPlacesForMap 임계값 불변량 검증.
/// 임계치: shouldUseClusters = places.length >= 80 && mapLevel >= 10.
/// → 상세 줌(level<10)에서는 항상 개별 핀, 클러스터는 저상세(level>=10)+다수일 때만.
/// 코드 탐색으로 요구를 이미 만족함을 입증했으므로, 임계치는 건드리지 않고 고정.
LalaPlace _place(String id, double distanceM) => LalaPlace(
      placeId: id,
      name: id,
      category: 'restaurant',
      lat: 37.2636,
      lng: 127.0286,
      address: '테스트 주소',
      distanceM: distanceM.toInt(),
      source: 'db',
    );

void main() {
  test('detail zoom renders only individual markers regardless of count', () {
    final many = List<LalaPlace>.generate(
      120,
      (i) => _place('detail-$i', 100.0 + i),
    );

    final markers = clusterMapPlacesForMap(
      places: many,
      selected: null,
      mapLevel: 4,
      language: 'ko',
    );

    expect(markers.where((marker) => marker.isCluster), isEmpty);
    // 상세 줌에서는 핀을 60개로 제한하지만 모두 개별 마커.
    expect(markers.length, lessThanOrEqualTo(60));
    expect(markers.every((marker) => !marker.isCluster), isTrue);
  });

  test('clusters appear only at low detail with many places', () {
    final many = List<LalaPlace>.generate(
      120,
      (i) => _place('cluster-$i', 100.0 + i),
    );

    final markers = clusterMapPlacesForMap(
      places: many,
      selected: null,
      mapLevel: 11,
      language: 'ko',
    );

    expect(markers.where((marker) => marker.isCluster), isNotEmpty);
  });

  test('few places never cluster even at low detail', () {
    final few = List<LalaPlace>.generate(
      20,
      (i) => _place('few-$i', 100.0 + i),
    );

    final markers = clusterMapPlacesForMap(
      places: few,
      selected: null,
      mapLevel: 11,
      language: 'ko',
    );

    expect(markers.where((marker) => marker.isCluster), isEmpty);
  });
}
