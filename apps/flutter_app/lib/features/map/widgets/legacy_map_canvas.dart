import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../kakao_map_view.dart';
import '../map_helpers.dart';

/// 카카오맵 캔버스 + 그라데이션 오버레이(C3 추출 — main.dart 의 _LegacyMapCanvas).
class LegacyMapCanvas extends StatelessWidget {
  const LegacyMapCanvas({
    super.key,
    required this.places,
    required this.selectedPlace,
    required this.weather,
    required this.kakaoJavascriptKey,
    required this.language,
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
  final String kakaoJavascriptKey;
  final String language;
  final double? mapFocusLat;
  final double? mapFocusLng;
  final int mapLevel;
  final ValueChanged<String> onSelectPlaceId;
  final ValueChanged<KakaoMapPlace> onSelectCluster;
  final ValueChanged<KakaoMapCamera> onCameraIdle;

  @override
  Widget build(BuildContext context) {
    final selected = selectedPlace;
    final centerLat = mapFocusLat ?? selected?.lat ?? 37.2823;
    final centerLng = mapFocusLng ?? selected?.lng ?? 127.0179;
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
          child: buildKakaoMapView(
            javascriptKey: kakaoJavascriptKey,
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
