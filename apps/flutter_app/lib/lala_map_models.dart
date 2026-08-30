import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
class LalaMapPlace {
  const LalaMapPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    this.clusterCount,
    this.clusterMemberIds = const <String>[],
    this.selected = false,
  });

  final String id;
  final String name;
  final String category;
  final double lat;
  final double lng;
  final int? clusterCount;
  final List<String> clusterMemberIds;
  final bool selected;

  bool get isCluster => (clusterCount ?? 0) > 1;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LalaMapPlace &&
            other.id == id &&
            other.name == name &&
            other.category == category &&
            other.lat == lat &&
            other.lng == lng &&
            other.clusterCount == clusterCount &&
            listEquals(other.clusterMemberIds, clusterMemberIds) &&
            other.selected == selected;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    category,
    lat,
    lng,
    clusterCount,
    Object.hashAll(clusterMemberIds),
    selected,
  );
}

const int lalaMapMinimumLevel = 2;
const int lalaMapMaximumLevel = 10;

/// LALA keeps the former level contract: a larger level means a wider view.
/// NAVER Maps uses the opposite zoom direction, so all provider conversion is
/// isolated here instead of leaking into clustering and backend query logic.
int lalaMapLevelToNaverZoom(int level) {
  final normalized = level.clamp(lalaMapMinimumLevel, lalaMapMaximumLevel);
  return 19 - normalized;
}

int naverZoomToLalaMapLevel(num zoom) {
  final level = 19 - zoom.round();
  return level.clamp(lalaMapMinimumLevel, lalaMapMaximumLevel);
}

// V1 bounds-query (D4): the viewport rectangle (SW/NE) sourced from the map's
// own getBounds(). Optional on LalaMapCamera - null means center+radius fallback.
@immutable
class LalaMapBounds {
  const LalaMapBounds({
    required this.swLat,
    required this.swLng,
    required this.neLat,
    required this.neLng,
  });

  final double swLat;
  final double swLng;
  final double neLat;
  final double neLng;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LalaMapBounds &&
            other.swLat == swLat &&
            other.swLng == swLng &&
            other.neLat == neLat &&
            other.neLng == neLng;
  }

  @override
  int get hashCode => Object.hash(swLat, swLng, neLat, neLng);
}

@immutable
class LalaMapCamera {
  const LalaMapCamera({
    required this.lat,
    required this.lng,
    required this.level,
    this.bounds,
  });

  final double lat;
  final double lng;
  final int level;

  // V1 bounds-query (D4): optional viewport rectangle; null → center+radius
  // fallback (state B2) so callers without bounds behave identically to today.
  final LalaMapBounds? bounds;
}

bool sameLalaMapPlaces(List<LalaMapPlace> a, List<LalaMapPlace> b) {
  return listEquals(a, b);
}

double? _payloadAsDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '');
}

int? _payloadAsInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '');
}

/// Decodes a provider-neutral `cameraIdle` bridge payload into a
/// [LalaMapCamera].
///
/// V1 bounds-query (D4): the SSOT decode shared by the native and web bridges.
/// Accepts either a JSON string (web DOM event `detail`) or an already-decoded
/// `Map` (native JS-channel message). Parses the optional viewport rectangle
/// (`sw_lat`/`sw_lng`/`ne_lat`/`ne_lng`): bounds are set only when ALL four are
/// present, else null → center+radius fallback (state B2). Returns null when the
/// payload is not a camera-idle message or lacks lat/lng/level.
LalaMapCamera? decodeLalaMapCameraIdlePayload(Object? payload) {
  Object? decoded = payload;
  if (payload is String) {
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return null;
    }
  }
  if (decoded is! Map) {
    return null;
  }
  if (decoded['type'] != null && decoded['type'] != 'cameraIdle') {
    return null;
  }
  final lat = _payloadAsDouble(decoded['lat']);
  final lng = _payloadAsDouble(decoded['lng']);
  final level = _payloadAsInt(decoded['level']);
  if (lat == null || lng == null || level == null) {
    return null;
  }
  final swLat = _payloadAsDouble(decoded['sw_lat']);
  final swLng = _payloadAsDouble(decoded['sw_lng']);
  final neLat = _payloadAsDouble(decoded['ne_lat']);
  final neLng = _payloadAsDouble(decoded['ne_lng']);
  final LalaMapBounds? bounds =
      (swLat != null && swLng != null && neLat != null && neLng != null)
      ? LalaMapBounds(swLat: swLat, swLng: swLng, neLat: neLat, neLng: neLng)
      : null;
  return LalaMapCamera(lat: lat, lng: lng, level: level, bounds: bounds);
}
