// P6D (P6A §13.2 / 01 Map 추천 rail): 사진 중심 compact 카드 계약 준수 회귀.
// card 내용(이름/지역/도보거리/category 색), honest no-image, selected 단일 토큰색
// 테두리, card 선택 콜백, 빈 viewport -> honest empty(잔류 card 없음).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/map/widgets/map_place_carousel_overlay.dart';
import 'package:lala_next_app/features/place/widgets/empty_place_state.dart';
import 'package:lala_next_app/features/place/widgets/map_rail_place_card.dart';
import 'package:lala_next_app/features/place/widgets/place_image.dart';

LalaPlace _place({
  String id = 'p1',
  String category = 'restaurant',
  String? imageUrl,
  int distanceM = 210,
  String? regionKo = '수원',
}) {
  return LalaPlace(
    placeId: id,
    name: id,
    nameKo: '행궁동 카페',
    category: category,
    lat: 37.28,
    lng: 127.01,
    address: '경기도 수원시 팔달구',
    distanceM: distanceM,
    source: 'db',
    upstreamSource: 'tour_api',
    imageUrl: imageUrl,
    regionKo: regionKo,
    regionEn: 'Suwon',
  );
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('MapRailPlaceCard content (P6A §13.2)', () {
    testWidgets(
      'displays name, region and walk distance; category color dot present',
      (tester) async {
        final place = _place(
          imageUrl: 'https://tong.visitkorea.or.kr/cms/resource/synthetic.jpg',
        );
        await tester.pumpWidget(
          _wrap(
            MapRailPlaceCard(
              place: place,
              language: 'ko',
              selected: false,
              compact: true,
            ),
          ),
        );

        expect(find.text('행궁동 카페'), findsOneWidget); // name
        expect(
          find.text('수원 · 도보 210m'),
          findsOneWidget,
        ); // region · walk distance
        // category color dot (decorated circle in the category token color)
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                (w.decoration as BoxDecoration).shape == BoxShape.circle,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('English copy is exclusive (no Korean alongside)', (
      tester,
    ) async {
      final place = _place(
        imageUrl: 'https://tong.visitkorea.or.kr/cms/resource/x.jpg',
      );
      await tester.pumpWidget(
        _wrap(
          MapRailPlaceCard(
            place: place,
            language: 'en',
            selected: false,
            compact: true,
          ),
        ),
      );
      expect(find.text('Suwon · 210m walk'), findsOneWidget);
      expect(find.textContaining('도보'), findsNothing);
    });

    testWidgets(
      'without an official image shows an honest empty slot, no random photo',
      (tester) async {
        final place = _place(imageUrl: null);
        await tester.pumpWidget(
          _wrap(
            MapRailPlaceCard(
              place: place,
              language: 'ko',
              selected: false,
              compact: true,
            ),
          ),
        );
        expect(
          find.byType(PlaceImage),
          findsNothing,
        ); // no image widget rendered
        expect(
          find.text('행궁동 카페'),
          findsOneWidget,
        ); // card still renders honestly
      },
    );
  });

  group('MapRailPlaceCard selection (P6A §2.3 / §03)', () {
    testWidgets('selected card has a single 1px token-color border', (
      tester,
    ) async {
      final place = _place(category: 'attraction');
      await tester.pumpWidget(
        _wrap(
          MapRailPlaceCard(
            place: place,
            language: 'ko',
            selected: true,
            compact: true,
          ),
        ),
      );
      final container = tester.widget<Container>(
        find.byKey(const ValueKey('map-rail-place-card-p1')),
      );
      final decoration = container.decoration as BoxDecoration;
      final border = decoration.border as Border;
      // attraction token color (#C53030), single uniform 1px border
      expect(border.top.color, const Color(0xFFC53030));
      expect(border.top.width, 1);
      expect(border.bottom.width, 1);
    });

    testWidgets('card tap fires selection (card -> marker binding)', (
      tester,
    ) async {
      final place = _place();
      LalaPlace? tapped;
      await tester.pumpWidget(
        _wrap(
          MapRailPlaceCard(
            place: place,
            language: 'ko',
            selected: false,
            compact: true,
            onTap: () => tapped = place,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('tour-stop-action-p1')));
      expect(tapped, place);
    });
  });

  group('MapPlaceCarouselOverlay empty viewport honesty', () {
    testWidgets(
      'empty expanded rail shows honest empty state and no residual cards',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            MapPlaceCarouselOverlay(
              places: const <LalaPlace>[],
              source: null,
              language: 'ko',
              selectedPlaceId: null,
              explicitSelectedPlaceId: null,
              expanded: true,
              compact: true,
              onSelectPlace: (_) {},
              onReselectSelectedPlace: () {},
              onToggleExpanded: () {},
            ),
          ),
        );
        expect(find.byType(EmptyPlaceState), findsOneWidget);
        expect(
          find.byType(MapRailPlaceCard),
          findsNothing,
        ); // no residual cards
      },
    );

    testWidgets('loaded rail renders cards for real viewport results only', (
      tester,
    ) async {
      final places = <LalaPlace>[
        _place(
          id: 'a',
          imageUrl: 'https://tong.visitkorea.or.kr/cms/resource/a.jpg',
        ),
        _place(
          id: 'b',
          imageUrl: 'https://tong.visitkorea.or.kr/cms/resource/b.jpg',
        ),
      ];
      await tester.pumpWidget(
        _wrap(
          MapPlaceCarouselOverlay(
            places: places,
            source: 'db',
            language: 'ko',
            selectedPlaceId: 'a',
            explicitSelectedPlaceId: null,
            expanded: true,
            compact: true,
            onSelectPlace: (_) {},
            onReselectSelectedPlace: () {},
            onToggleExpanded: () {},
          ),
        ),
      );
      expect(find.byType(MapRailPlaceCard), findsNWidgets(2));
      expect(find.byType(EmptyPlaceState), findsNothing);
    });
  });
}
