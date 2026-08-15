// Wave-1 location/weather: honest default-region disclosure.
//
// When no real current/manual region context exists, place + weather calls fall
// back to a documented default region (Gyeonggi/Suwon). This badge states that
// plainly instead of letting default-region results read as the user's own
// "nearby" recommendations.
import 'package:flutter/material.dart';

import 'package:lala_next_app/shared/l10n/lala_copy.dart';

/// Compact, localized disclosure that the active results are for the default
/// region, not the user's location. Render it only when the active region
/// context is the disclosed default (see RegionContextStore).
class DefaultRegionIndicator extends StatelessWidget {
  const DefaultRegionIndicator({required this.language, super.key});

  final String language;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: Color(0xFF94A3B8),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              lalaCopyMulti(
                language,
                ko: '현재 위치 대신 기본 지역(수원) 추천을 보여드려요',
                en: 'Showing the default region (Suwon), not your location',
                ja: '現在地の代わりに既定の地域（水原）のおすすめを表示しています',
                zhHans: '正在显示默认地区（水原）的推荐，而非您的位置',
                zhHant: '正在顯示預設地區（水原）的推薦，而非您的位置',
              ),
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
