import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../place_helpers.dart';
import 'place_image.dart';

/// 추천 카드용 장소 썸네일(C3 추출 — main.dart 의 _PlaceThumb).
class PlaceThumb extends StatelessWidget {
  const PlaceThumb({super.key, required this.place});

  final LalaPlace place;

  @override
  Widget build(BuildContext context) {
    if (!hasOfficialPlaceImage(place)) {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: PlaceImage(place: place, width: 76, height: 76),
    );
  }
}
