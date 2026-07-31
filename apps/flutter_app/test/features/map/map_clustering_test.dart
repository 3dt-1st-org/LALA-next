// Runtime remediation: API 최대 60개에 맞춘 bounded clustering + 대비 회귀.
//  - sparse 8 + 근접 level → 개별 pin
//  - dense 60 + 기본 level → 실제 cluster, 최대 16 marker
//  - 원거리 level(>=10) → 실제 cluster
//  - 선택 마커는 cluster 활성 시에도 개별 핀으로 유지(01-flow §F2.5)
//  - 비-restaurant pin icon = white, restaurant pin icon = restaurantInk (P6A §2.3)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/features/map/map_helpers.dart';
import 'package:lala_next_app/kakao_map_fallback.dart';
import 'package:lala_next_app/kakao_map_models.dart';

void main() {
  group('bounded cluster policy', () {
    test('sparse 8 nearby candidates stay as individual pins', () {
      final places = List<LalaPlace>.generate(8, (i) => _place('pin-$i'));
      final markers = clusterMapPlacesForMap(
        places: places,
        selected: null,
        mapLevel: 6,
        language: 'ko',
      );
      expect(markers.where((m) => m.isCluster), isEmpty);
      expect(markers, hasLength(8));
    });

    test('dense 60 produces real clusters and a bounded marker set', () {
      final places = List<LalaPlace>.generate(60, (i) => _place('dense-$i'));
      final markers = clusterMapPlacesForMap(
        places: places,
        selected: null,
        mapLevel: 6,
        language: 'ko',
      );
      expect(markers.where((m) => m.isCluster), isNotEmpty);
      expect(markers, hasLength(lessThanOrEqualTo(16)));
      expect(
        markers.fold<int>(0, (sum, marker) => sum + (marker.clusterCount ?? 1)),
        60,
      );
    });

    test('empty viewport result leaves no markers', () {
      final markers = clusterMapPlacesForMap(
        places: const <LalaPlace>[],
        selected: null,
        mapLevel: 10,
        language: 'ko',
      );
      expect(markers, isEmpty);
    });

    test('selected marker stays individual while clustering is active', () {
      final places = List<LalaPlace>.generate(60, (i) => _place('sel-$i'));
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
      expect(markers.where((m) => m.isCluster), isNotEmpty);
      expect(markers, hasLength(lessThanOrEqualTo(17)));
    });

    test('far zoom clusters a sparse co-located result', () {
      final places = List<LalaPlace>.generate(8, (i) => _place('far-$i'));
      final markers = clusterMapPlacesForMap(
        places: places,
        selected: null,
        mapLevel: 10,
        language: 'ko',
      );
      expect(markers.where((m) => m.isCluster), hasLength(1));
      expect(markers.single.clusterCount, 8);
    });
  });

  group('marker on-fill contrast (P6A §2.3)', () {
    testWidgets('non-restaurant pin icon is white', (tester) async {
      await _pumpFallback(
        tester,
        const KakaoMapPlace(
          id: 'p1',
          name: 'P',
          category: 'attraction',
          lat: 37.28,
          lng: 127.01,
        ),
      );
      expect(tester.widget<Icon>(find.byType(Icon)).color, Colors.white);
    });

    testWidgets('restaurant pin icon is restaurantInk (기존 유지)', (tester) async {
      await _pumpFallback(
        tester,
        const KakaoMapPlace(
          id: 'p2',
          name: 'P',
          category: 'restaurant',
          lat: 37.28,
          lng: 127.01,
        ),
      );
      expect(
        tester.widget<Icon>(find.byType(Icon)).color,
        LalaVisualColors.restaurantInk,
      );
    });
  });
}

Future<void> _pumpFallback(WidgetTester tester, KakaoMapPlace place) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 800,
          child: KakaoMapFallbackView(
            message: '',
            language: 'ko',
            centerLat: 37.28,
            centerLng: 127.01,
            places: [place],
          ),
        ),
      ),
    ),
  );
  // Single non-cluster marker's Icon is the assertion target; settle one frame.
  await tester.pump();
}

LalaPlace _place(String id) {
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
    distanceM: 100,
    source: 'db',
    upstreamSource: 'tour_api',
  );
}
