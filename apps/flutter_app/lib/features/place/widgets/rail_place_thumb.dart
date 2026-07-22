import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'place_image.dart';

/// 레일 카드용 장소 썸네일(C3 추출 — main.dart 의 _RailPlaceThumb).
class RailPlaceThumb extends StatelessWidget {
  const RailPlaceThumb({super.key, required this.place, required this.compact});

  final LalaPlace place;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dimension = compact ? 72.0 : 86.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        key: ValueKey('rail-place-thumb-${place.placeId}'),
        width: dimension,
        height: dimension,
        child: PlaceImage(place: place, width: dimension, height: dimension),
      ),
    );
  }
}
