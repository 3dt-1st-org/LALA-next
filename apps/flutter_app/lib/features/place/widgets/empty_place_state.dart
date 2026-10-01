import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';

/// 추천 장소 빈 상태(C3 추출 — main.dart 의 _EmptyPlaceState).
class EmptyPlaceState extends StatelessWidget {
  const EmptyPlaceState({
    super.key,
    required this.language,
    this.emptyResultsConfirmed = false,
  });

  final String language;
  final bool emptyResultsConfirmed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        emptyResultsConfirmed
            ? noNearbyPlacesLabel(language)
            : lalaCopyMulti(
                language,
                ko: '이 주변 추천을 준비 중입니다.',
                en: 'Recommendations are still being prepared here.',
                ja: 'この周辺のおすすめを準備中です。',
                zhHans: '正在准备这附近的推荐。',
                zhHant: '正在準備這附近的推薦。',
              ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
