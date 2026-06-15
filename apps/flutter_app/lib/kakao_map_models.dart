import 'package:flutter/foundation.dart';

@immutable
class KakaoMapPlace {
  const KakaoMapPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    this.scorePercent,
    this.selected = false,
  });

  final String id;
  final String name;
  final String category;
  final double lat;
  final double lng;
  final int? scorePercent;
  final bool selected;
}
