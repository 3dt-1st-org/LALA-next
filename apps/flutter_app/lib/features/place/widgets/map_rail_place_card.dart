import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/l10n/place_labels.dart';
import '../place_helpers.dart';
import 'place_image.dart';

/// 지도 레일용 장소 카드.
// 모바일 비주얼 계약(20260728) §13.2 / 01 Map 추천 rail: 사진 중심 compact card.
// card 내용 = 이름 · 지역 · 도보 거리 · category. 선택 시 카테고리색 1px 테두리 하나만.
// 공식 이미지가 없으면 중성 빈 슬롯(임의 사진 금지). freshness 는 LalaPlace 에 필드가
// 없어 honest-empty 로 생략한다(날짜를 발명하지 않는다).
class MapRailPlaceCard extends StatelessWidget {
  const MapRailPlaceCard({
    super.key,
    required this.place,
    required this.language,
    required this.selected,
    required this.compact,
    this.onTap,
  });

  final LalaPlace place;
  final String language;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(place.category);
    final hasImage = hasOfficialPlaceImage(place);
    final name = placeDisplayName(place, language);
    final region = placeRegionLabel(place, language);
    final distance = lalaCopy(
      language,
      ko: '도보 ${place.distanceM}m',
      en: '${place.distanceM}m walk',
    );
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('tour-stop-action-${place.placeId}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Semantics(
          label: name,
          selected: selected,
          button: onTap != null,
          child: Container(
            key: ValueKey('map-rail-place-card-${place.placeId}'),
            width: 148,
            height: 114,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              // 선택 테두리 하나만(카테고리색 1px). 내부 테두리 금지.
              border: Border.all(
                color: selected ? color : const Color(0xFFE2E8F0),
                width: 1,
              ),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        blurRadius: 14,
                        offset: Offset(0, 6),
                        color: Color(0x22000000),
                      ),
                    ]
                  : const [
                      BoxShadow(
                        blurRadius: 10,
                        offset: Offset(0, 4),
                        color: Color(0x14000000),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (hasImage)
                    PlaceImage(
                      key: ValueKey('rail-place-image-${place.placeId}'),
                      place: place,
                      width: 148,
                      height: 114,
                    )
                  else
                    const ColoredBox(color: Color(0xFFEDF2F7)),
                  // category 색 점(좌상단, 카테고리 토큰색 — marker/filter chip 과
                  // 동일 토큰. 라벨 중복을 피하고 사진 중심을 유지하려 텍스트 배지 대신 색 점).
                  Positioned(
                    top: 7,
                    left: 7,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const SizedBox(width: 12, height: 12),
                    ),
                  ),
                  // 이름 + 메타(지역 · 도보 거리) 하단 오버레이.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[Color(0x00FFFFFF), Color(0x66000000)],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 18, 8, 7),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$region · $distance',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                height: 1.15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
