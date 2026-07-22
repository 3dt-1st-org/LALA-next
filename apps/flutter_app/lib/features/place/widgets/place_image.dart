import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../place_helpers.dart';

/// 장소 이미지(C3 추출 — main.dart 의 _PlaceImage).
class PlaceImage extends StatelessWidget {
  const PlaceImage({
    super.key,
    required this.place,
    required this.width,
    required this.height,
  });

  final LalaPlace place;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final imageUri = normalizedPlaceImageUri(place.imageUrl);
    if (imageUri != null) {
      return Image.network(
        imageUri.toString(),
        width: width,
        height: height,
        fit: BoxFit.cover,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }
    return const SizedBox.shrink();
  }
}
