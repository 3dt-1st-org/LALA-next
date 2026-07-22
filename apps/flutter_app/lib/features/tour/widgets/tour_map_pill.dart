import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/widgets/small_status_pill.dart';

/// 맛집 투어 진입 필(C3 추출 — main.dart 의 _TourMapPill).
/// 지도에서 맛집 투어 시트를 여는 버튼이다.
class TourMapPill extends StatelessWidget {
  const TourMapPill({
    super.key,
    required this.places,
    required this.language,
    required this.onPressed,
  });

  final List<LalaPlace> places;
  final String language;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SmallStatusPill(
      key: const ValueKey('tour-pill-hit-target'),
      icon: Icons.restaurant_menu,
      label: lalaCopy(language, ko: '맛집 투어', en: 'Food tour'),
      active: places.isNotEmpty,
      onPressed: onPressed,
    );
  }
}
