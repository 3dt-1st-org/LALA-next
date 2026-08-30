import 'dart:math' as math;

import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../lala_map_view.dart';
import '../../shared/l10n/lala_copy.dart';
import '../../shared/l10n/place_labels.dart';

/// 지도 레일/하이라이트용 대표 장소 선택(C3 추출 — main.dart 의 _featuredPlace).
/// 수원화성/화성행궁 우선, 그 외 가장 가까운 5km 이내 장소, 최후 첫 장소.
LalaPlace? featuredPlace(List<LalaPlace> places) {
  if (places.isEmpty) {
    return null;
  }

  final suwonPlaces = places.where((place) => place.distanceM <= 5000).toList()
    ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
  for (final place in suwonPlaces) {
    final name = '${place.nameKo ?? ''} ${place.name}';
    if (name.contains('화성행궁') || name.contains('수원화성')) {
      return place;
    }
  }
  if (suwonPlaces.isNotEmpty) {
    return suwonPlaces.first;
  }

  return places.first;
}

/// 추천 레일 정렬: 대표 장소 우선 후 나머지, 상위 8개(C3 추출 — main.dart 의 _railPlaces).
List<LalaPlace> railPlaces(List<LalaPlace> places) {
  if (places.isEmpty) {
    return const <LalaPlace>[];
  }
  final featured = featuredPlace(places);
  if (featured == null) {
    return places.take(8).toList();
  }
  return [
    featured,
    ...places.where((place) => place.placeId != featured.placeId),
  ].take(8).toList();
}

int _selectedPlaceSortValue(String placeId, String? selectedId) {
  if (selectedId == null) {
    return 1;
  }
  return placeId == selectedId ? 0 : 1;
}

/// 지도 마커 클러스터링(C3 추출 — main.dart 의 clusterMapPlacesForMap).
/// LegacyMapCanvas(프로덕션)이 사용하므로 map feature 공개 API.
/// test/widget_test.dart 는 main.dart re-export 로 그대로 접근.
List<LalaMapPlace> clusterMapPlacesForMap({
  required List<LalaPlace> places,
  required LalaPlace? selected,
  required int mapLevel,
  required String language,
}) {
  final selectedId = selected?.placeId;
  final selectedMarkers = <LalaMapPlace>[];
  final buckets = <String, List<LalaPlace>>{};
  // The places endpoint is capped at 60. A prior count gate of 80 was therefore
  // unreachable in production, leaving a full response as dozens of overlapping
  // iOS pins. Treat 24+ visible candidates as dense (while sparse results such as
  // eight nearby places remain individual), or cluster at the existing far-zoom
  // boundary. The adaptive 4x4/3x3 geographic grid bounds the marker set to
  // 16/9 cells plus the selected individual pin; every cluster contains real
  // member ids and uses their geographic centroid.
  const clusterCountThreshold = 24;
  const clusterFarLevel = 10;
  final shouldUseClusters =
      places.length >= clusterCountThreshold || mapLevel >= clusterFarLevel;
  final orderedPlaces = [...places]
    ..sort((a, b) {
      final selectedCompare = _selectedPlaceSortValue(
        a.placeId,
        selectedId,
      ).compareTo(_selectedPlaceSortValue(b.placeId, selectedId));
      if (selectedCompare != 0) {
        return selectedCompare;
      }
      final distanceCompare = a.distanceM.compareTo(b.distanceM);
      if (distanceCompare != 0) {
        return distanceCompare;
      }
      return placeDisplayName(
        a,
        language,
      ).compareTo(placeDisplayName(b, language));
    });

  LalaMapPlace toMapPlace(LalaPlace place, {bool selected = false}) {
    return LalaMapPlace(
      id: place.placeId,
      name: placeDisplayName(place, language),
      category: place.category,
      lat: place.lat,
      lng: place.lng,
      selected: selected,
    );
  }

  final visiblePlaces = orderedPlaces.take(60).toList(growable: false);
  if (!shouldUseClusters) {
    return visiblePlaces
        .map(
          (place) => toMapPlace(place, selected: place.placeId == selectedId),
        )
        .toList(growable: false);
  }

  final clusterCandidates = visiblePlaces
      .where((place) => place.placeId != selectedId)
      .toList(growable: false);
  for (final place in visiblePlaces) {
    if (place.placeId == selectedId) {
      selectedMarkers.add(toMapPlace(place, selected: true));
    }
  }

  if (clusterCandidates.isEmpty) {
    return selectedMarkers;
  }

  final minLat = clusterCandidates.map((place) => place.lat).reduce(math.min);
  final maxLat = clusterCandidates.map((place) => place.lat).reduce(math.max);
  final minLng = clusterCandidates.map((place) => place.lng).reduce(math.min);
  final maxLng = clusterCandidates.map((place) => place.lng).reduce(math.max);
  final gridAxis = mapLevel >= clusterFarLevel ? 3 : 4;

  int cellIndex(double value, double min, double max) {
    final span = max - min;
    if (span.abs() < 0.000001) {
      return 0;
    }
    final scaled = ((value - min) / span * gridAxis).floor();
    return math.max(0, math.min(gridAxis - 1, scaled));
  }

  for (final place in clusterCandidates) {
    final latCell = cellIndex(place.lat, minLat, maxLat);
    final lngCell = cellIndex(place.lng, minLng, maxLng);
    final key = '$latCell:$lngCell';
    buckets.putIfAbsent(key, () => <LalaPlace>[]).add(place);
  }

  final clustered = <LalaMapPlace>[];
  for (final entry in buckets.entries) {
    final group = entry.value;
    if (group.length >= 2) {
      final lat =
          group.fold<double>(0, (sum, place) => sum + place.lat) / group.length;
      final lng =
          group.fold<double>(0, (sum, place) => sum + place.lng) / group.length;
      final categoryCounts = <String, int>{};
      for (final place in group) {
        categoryCounts.update(
          place.category,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      final categories = categoryCounts.keys.toList()
        ..sort((a, b) {
          final countCompare = categoryCounts[b]!.compareTo(categoryCounts[a]!);
          return countCompare != 0 ? countCompare : a.compareTo(b);
        });
      clustered.add(
        LalaMapPlace(
          id: 'cluster-${entry.key}',
          name: lalaCopy(
            language,
            ko: '${group.length}곳',
            en: '${group.length} places',
          ),
          category: categories.first,
          lat: lat,
          lng: lng,
          clusterCount: group.length,
          clusterMemberIds: group
              .map((place) => place.placeId)
              .toList(growable: false),
        ),
      );
    } else {
      clustered.addAll(group.map(toMapPlace));
    }
  }

  return [...clustered, ...selectedMarkers];
}
