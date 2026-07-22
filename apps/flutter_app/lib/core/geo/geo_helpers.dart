// C3 최종: main.dart 에서 이관. 본문 불변(이동만).
// 지도 이동에 따른 장소/날씨 재조회 정책 + 거리 계산 + 1회 재시도 헬퍼.
import 'dart:math' as math;

bool shouldReloadPlacesForMapMove({
  required bool hasAnyPlaces,
  required double? lastFetchLat,
  required double? lastFetchLng,
  required double currentLat,
  required double currentLng,
  double thresholdMeters = 250,
}) {
  if (!hasAnyPlaces || lastFetchLat == null || lastFetchLng == null) {
    return true;
  }
  return distanceMeters(lastFetchLat, lastFetchLng, currentLat, currentLng) >=
      thresholdMeters;
}

Future<T> loadWithSingleRetry<T>(
  Future<T> Function() loader, {
  required bool shouldRetry,
  Duration retryDelay = const Duration(milliseconds: 600),
}) async {
  try {
    return await loader();
  } on Object {
    if (!shouldRetry) {
      rethrow;
    }
    await Future<void>.delayed(retryDelay);
    return await loader();
  }
}

bool shouldReloadWeatherForMapMove({
  required bool force,
  required bool hasWeather,
  required DateTime? lastFetchAt,
  required double? lastFetchLat,
  required double? lastFetchLng,
  required double currentLat,
  required double currentLng,
  Duration maxAge = const Duration(minutes: 10),
  double thresholdMeters = 10000,
  DateTime? now,
}) {
  if (force || !hasWeather || lastFetchAt == null) {
    return true;
  }
  if (lastFetchLat == null || lastFetchLng == null) {
    return true;
  }
  final effectiveNow = now ?? DateTime.now();
  if (effectiveNow.difference(lastFetchAt) >= maxAge) {
    return true;
  }
  return distanceMeters(lastFetchLat, lastFetchLng, currentLat, currentLng) >=
      thresholdMeters;
}

double distanceMeters(
  double fromLat,
  double fromLng,
  double toLat,
  double toLng,
) {
  const earthRadiusMeters = 6371000.0;
  final fromLatRadians = fromLat * math.pi / 180;
  final toLatRadians = toLat * math.pi / 180;
  final deltaLat = (toLat - fromLat) * math.pi / 180;
  final deltaLng = (toLng - fromLng) * math.pi / 180;
  final haversine =
      math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(fromLatRadians) *
          math.cos(toLatRadians) *
          math.sin(deltaLng / 2) *
          math.sin(deltaLng / 2);
  final centralAngle =
      2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  return earthRadiusMeters * centralAngle;
}
