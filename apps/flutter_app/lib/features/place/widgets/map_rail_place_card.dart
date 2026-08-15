import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/l10n/place_labels.dart';
import '../place_helpers.dart';
import 'place_image.dart';
import 'place_reason_freshness.dart';

/// 지도 레일용 장소 카드.
// 모바일 비주얼 계약(20260728) §13.2 / 01 Map 추천 rail: 사진 중심 compact card.
// card 내용 = 이름 · 지역 · 도보 거리 · category(색 점+라벨) · reason · freshness.
// §13.5: category 를 색으로만 전달하지 않는다 — 색 점(좌상단)과 함께 category 라벨을
// 하단 메타 줄(category · 지역 · 도보거리)에 텍스트로 노출한다(새 색/폰트 없이).
// 선택 시 카테고리색 1px 테두리 하나. 공식 이미지가 없으면 중성 빈 슬롯(임의 사진 금지).
// reason/freshness 는 하단 오버레이 1줄(둘 다 null/빈이면 honest 생략, 날짜 발명 금지).
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
    // §13.5: category 라벨 텍스트. CategoryBadge/시맨틱 라벨과 동일 원문(categoryLabel).
    final category = categoryLabel(place.category, language: language);
    final distance = lalaCopyMulti(
      language,
      ko: '도보 ${place.distanceM}m',
      en: '${place.distanceM}m walk',
      ja: '徒歩 ${place.distanceM}m',
      zhHans: '步行 ${place.distanceM}米',
      zhHant: '步行 ${place.distanceM}公尺',
    );
    // V1-RC4: 타일/독/상세와 동일 SSOT 원문. null/빔이면 하단 라인을 honest 생략한다.
    final freshnessText = placeFreshnessText(place);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('tour-stop-action-${place.placeId}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Semantics(
          // V1-RC2: 검색 타일과 동일 SSOT 라벨(장소명/카테고리/거리/지역/reason).
          label: placeCardSemanticsLabel(place, language),
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
                  // category 색 점(좌상단, 카테고리 토큰색 — marker/filter chip 과 동일 토큰).
                  // §13.5: 색은 보조 채널이고 category 텍스트는 하단 메타 줄에 병치(색만으로 전달 금지).
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
                              // V6 §6: 번역 없는 정적 지역명은 영문 폴백을 그대로
                              // 쓰되 '영문 제공' 배지로 폴백을 고지한다(무혼합·무침묵).
                              placeNameUsesEnglishFallback(place, language)
                                  ? '$category · $region · $distance · '
                                        '${englishFallbackDisclosureLabel(language)}'
                                  : '$category · $region · $distance',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                height: 1.15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            // V1-RC2(D-1): per-place reason, 같은 오버레이 스타일(흰색/10px/w600).
                            // place.reason 이 null/빈이면 PlaceReasonLine 이 스스로 렌더하지 않는다.
                            PlaceReasonLine(
                              place: place,
                              topSpacing: 2,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                height: 1.15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            // V1-RC4: per-place 신선도(같은 오버레이 스타일). freshnessText 는
                            // null/빔이면 생략 — 날짜를 발명하지 않는다.
                            if (freshnessText != null) ...<Widget>[
                              const SizedBox(height: 2),
                              Text(
                                freshnessText,
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
