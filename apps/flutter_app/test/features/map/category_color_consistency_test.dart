// P6B (P6A §2.3): chip · rail card · marker 가 동일 LalaVisualColors 카테고리 토큰을
// 사용하는지, 그리고 빈 viewport 결과에 잔류 marker 가 없는지 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/features/map/map_helpers.dart';
import 'package:lala_next_app/features/map/widgets/category_chip.dart';
import 'package:lala_next_app/features/place/place_helpers.dart';
import 'package:lala_next_app/features/place/widgets/category_badge.dart';

const _cases = <(String, Color)>[
  ('attraction', LalaVisualColors.attraction),
  ('restaurant', LalaVisualColors.restaurant),
  ('event', LalaVisualColors.event),
  ('culture_venue', LalaVisualColors.culture),
];

void main() {
  group('categoryColor SSOT (chip/card/marker 동일 토큰)', () {
    test(
      'categoryColor() returns the LalaVisualColors token for each category',
      () {
        for (final (category, token) in _cases) {
          expect(categoryColor(category), token, reason: category);
        }
        expect(categoryColor('unknown'), LalaVisualColors.ink);
      },
    );

    test(
      'categoryColorHex() matches the token hex (JS marker path drift guard)',
      () {
        expect(categoryColorHex('attraction'), '#C53030');
        expect(categoryColorHex('restaurant'), '#F5C842');
        expect(categoryColorHex('event'), '#2B6CB0');
        expect(categoryColorHex('culture_venue'), '#0F766E');
        expect(categoryColorHex('unknown'), '#1A202C');
      },
    );

    test(
      'categoryOnTextColor() is restaurantInk for restaurant, white otherwise',
      () {
        expect(
          categoryOnTextColor('restaurant'),
          LalaVisualColors.restaurantInk,
        );
        for (final category in [
          'attraction',
          'event',
          'culture_venue',
          'unknown',
        ]) {
          expect(categoryOnTextColor(category), Colors.white, reason: category);
        }
      },
    );
  });

  group('CategoryBadge (card surface) uses the token', () {
    for (final (category, token) in _cases) {
      testWidgets(
        '$category badge fill == token and on-text color matches resolver',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(body: CategoryBadge(category: category)),
            ),
          );
          final container = tester.widget<Container>(find.byType(Container));
          final decoration = container.decoration as BoxDecoration;
          expect(decoration.color, token);
          final text = tester.widget<Text>(find.byType(Text));
          expect(text.style?.color, categoryOnTextColor(category));
        },
      );
    }
  });

  group('CategoryChip on-fill text is token-driven (no raw hex)', () {
    testWidgets('restaurant chip active text uses restaurantInk', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CategoryChip(
              label: '맛집',
              active: true,
              color: categoryColor('restaurant'),
              onTap: () {},
            ),
          ),
        ),
      );
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.style?.color, LalaVisualColors.restaurantInk);
    });

    testWidgets('attraction chip active text uses white', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CategoryChip(
              label: '명소',
              active: true,
              color: categoryColor('attraction'),
              onTap: () {},
            ),
          ),
        ),
      );
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.style?.color, Colors.white);
    });
  });

  group('viewport honesty (P6A §03 Map)', () {
    test('empty viewport result leaves no residual markers', () {
      final markers = clusterMapPlacesForMap(
        places: const <LalaPlace>[],
        selected: null,
        mapLevel: 10,
        language: 'ko',
      );
      expect(markers, isEmpty);
    });

    test(
      'selected place is flagged and stays individual (marker↔card binding)',
      () {
        final place = LalaPlace(
          placeId: 'sel-1',
          name: 'sel',
          nameKo: '셀렉',
          category: 'attraction',
          lat: 37.28,
          lng: 127.01,
          address: '경기도 수원시',
          regionKo: '수원',
          regionEn: 'Suwon',
          distanceM: 100,
          source: 'db',
          upstreamSource: 'tour_api',
        );
        final markers = clusterMapPlacesForMap(
          places: [place],
          selected: place,
          mapLevel: 10,
          language: 'ko',
        );
        final selected = markers.where((m) => m.id == place.placeId);
        expect(selected, isNotEmpty);
        expect(selected.every((m) => m.selected), isTrue);
        expect(selected.every((m) => !m.isCluster), isTrue);
      },
    );
  });
}
