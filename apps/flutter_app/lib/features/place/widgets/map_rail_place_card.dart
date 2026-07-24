import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/place_labels.dart';
import '../place_helpers.dart';
import 'place_image.dart';

/// 지도 레일용 장소 카드.
// 모바일 비주얼 계약 remediation C2: 컴팩트 모바일에서 148 x 114 photo-forward 카드.
// 공식 이미지가 카드를 채우고 이름만 오버레이. 선택 시 1px 카테고리색 테두리 하나만.
// 두 번째 내부 테두리·다중색 띠·점수/근거는 없다. 이미지가 없으면 중성 빈 슬롯.
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
                  // 이름 오버레이(하단 그라디언트). 메타 밀도를 줄여 지도가 주 시면.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Color(0x00FFFFFF),
                            Color(0x66000000),
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 14, 8, 7),
                        child: Text(
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
