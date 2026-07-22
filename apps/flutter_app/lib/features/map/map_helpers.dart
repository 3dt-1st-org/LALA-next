import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../kakao_map_view.dart';
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
List<KakaoMapPlace> clusterMapPlacesForMap({
  required List<LalaPlace> places,
  required LalaPlace? selected,
  required int mapLevel,
  required String language,
}) {
  final selectedId = selected?.placeId;
  final expandedPinFloor = mapLevel >= 10 ? 36 : 48;
  final selectedMarkers = <KakaoMapPlace>[];
  final expandedMarkers = <KakaoMapPlace>[];
  final buckets = <String, List<LalaPlace>>{};
  final shouldUseClusters = places.length >= 80 && mapLevel >= 10;
  var expandedPinCount = 0;
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

  KakaoMapPlace toMapPlace(LalaPlace place, {bool selected = false}) {
    return KakaoMapPlace(
      id: place.placeId,
      name: placeDisplayName(place, language),
      category: place.category,
      lat: place.lat,
      lng: place.lng,
      selected: selected,
    );
  }

  for (final place in orderedPlaces.take(60)) {
    if (place.placeId == selectedId) {
      selectedMarkers.add(toMapPlace(place, selected: true));
      continue;
    }
    if (!shouldUseClusters) {
      selectedMarkers.add(toMapPlace(place));
      continue;
    }
    if (expandedPinCount < expandedPinFloor) {
      expandedMarkers.add(toMapPlace(place));
      expandedPinCount += 1;
      continue;
    }
    final latBucket = (place.lat * 180).round();
    final lngBucket = (place.lng * 180).round();
    final key = '${place.category}:$latBucket:$lngBucket';
    buckets.putIfAbsent(key, () => <LalaPlace>[]).add(place);
  }

  final clustered = <KakaoMapPlace>[];
  for (final entry in buckets.entries) {
    final group = entry.value;
    if (group.length >= 3) {
      final lat =
          group.fold<double>(0, (sum, place) => sum + place.lat) / group.length;
      final lng =
          group.fold<double>(0, (sum, place) => sum + place.lng) / group.length;
      clustered.add(
        KakaoMapPlace(
          id: 'cluster-${entry.key}',
          name: lalaCopy(
            language,
            ko: '${group.length}곳',
            en: '${group.length} places',
          ),
          category: group.first.category,
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

  return [...clustered, ...expandedMarkers, ...selectedMarkers];
}
