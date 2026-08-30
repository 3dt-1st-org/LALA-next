import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../lala_map_view.dart';
import '../map_helpers.dart';

/// 네이버 지도 캔버스 + 그라데이션 오버레이(C3 추출 - main.dart 의 _LegacyMapCanvas).
class LegacyMapCanvas extends StatelessWidget {
  const LegacyMapCanvas({
    super.key,
    required this.places,
    required this.selectedPlace,
    required this.weather,
    required this.naverMapClientId,
    required this.language,
    required this.fallbackCenterLat,
    required this.fallbackCenterLng,
    required this.mapFocusLat,
    required this.mapFocusLng,
    required this.mapLevel,
    required this.onSelectPlaceId,
    required this.onSelectCluster,
    required this.onCameraIdle,
  });

  final List<LalaPlace> places;
  final LalaPlace? selectedPlace;
  final LalaWeather? weather;
  final String naverMapClientId;
  final String language;
  final double fallbackCenterLat;
  final double fallbackCenterLng;
  final double? mapFocusLat;
  final double? mapFocusLng;
  final int mapLevel;
  final ValueChanged<String> onSelectPlaceId;
  final ValueChanged<LalaMapPlace> onSelectCluster;
  final ValueChanged<LalaMapCamera> onCameraIdle;

  @override
  Widget build(BuildContext context) {
    final selected = selectedPlace;
    final centerLat = mapFocusLat ?? selected?.lat ?? fallbackCenterLat;
    final centerLng = mapFocusLng ?? selected?.lng ?? fallbackCenterLng;
    final mapPlaces = clusterMapPlacesForMap(
      places: places,
      selected: selected,
      mapLevel: mapLevel,
      language: language,
    );

    void handleMapFeatureTap(String featureId) {
      for (final marker in mapPlaces) {
        if (marker.id == featureId) {
          if (marker.isCluster) {
            onSelectCluster(marker);
            return;
          }
          break;
        }
      }
      onSelectPlaceId(featureId);
    }

    return Stack(
      children: [
        Positioned.fill(
          child: buildLalaMapView(
            clientId: naverMapClientId,
            language: language,
            centerLat: centerLat,
            centerLng: centerLng,
            level: mapLevel,
            places: mapPlaces,
            onPlaceTap: handleMapFeatureTap,
            onCameraIdle: onCameraIdle,
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.18),
                    Colors.white.withValues(alpha: 0.02),
                    Colors.white.withValues(alpha: 0.26),
                  ],
                  stops: const [0, 0.46, 1],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
