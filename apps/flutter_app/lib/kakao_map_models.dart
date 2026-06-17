import 'package:flutter/foundation.dart';

@immutable
class KakaoMapPlace {
  const KakaoMapPlace({
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
}

@immutable
class KakaoMapCamera {
  const KakaoMapCamera({
    required this.lat,
    required this.lng,
    required this.level,
  });

  final double lat;
  final double lng;
  final int level;
}
