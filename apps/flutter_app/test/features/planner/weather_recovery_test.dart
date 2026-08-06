import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/planner/widgets/weather_recovery_banner.dart';
import 'package:lala_next_app/features/planner/widgets/plan_slot_tile.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('WeatherRecoveryBanner', () {
    testWidgets('restored KO', (tester) async {
      await tester.pumpWidget(
        _wrap(const WeatherRecoveryBanner.restored(language: 'ko')),
      );
      expect(find.text('이전 일정을 복원했어요.'), findsOneWidget);
      expect(find.byIcon(Icons.history), findsOneWidget);
    });

    testWidgets('restored EN exclusive', (tester) async {
      await tester.pumpWidget(
        _wrap(const WeatherRecoveryBanner.restored(language: 'en')),
      );
      expect(find.text('Restored your previous plan.'), findsOneWidget);
      expect(find.text('이전 일정을 복원했어요.'), findsNothing);
    });

    testWidgets('swapped KO with detail', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const WeatherRecoveryBanner.swapped(
            language: 'ko',
            swapDetail: '야외 공원 -> 실내 미술관',
          ),
        ),
      );
      expect(find.text('날씨를 고려해 일정을 조정했어요.'), findsOneWidget);
      expect(find.text('야외 공원 -> 실내 미술관'), findsOneWidget);
    });

    testWidgets('swapped EN', (tester) async {
      await tester.pumpWidget(
        _wrap(const WeatherRecoveryBanner.swapped(language: 'en')),
      );
      expect(find.text('Adjusted your plan for the weather.'), findsOneWidget);
    });
  });

  group('PlanSlotTile swapReason', () {
    testWidgets('shows badge when swapReason set', (tester) async {
      final slot = LalaPlanSlot(
        period: 'afternoon',
        title: '오후',
        place: LalaPlace(
          placeId: 'p1',
          name: '미술관',
          category: 'culture_venue',
          lat: 37.5,
          lng: 127.0,
          address: '서울',
          distanceM: 100,
          source: 'db',
        ),
      );
      await tester.pumpWidget(
        _wrap(
          PlanSlotTile(
            slot: slot,
            language: 'ko',
            onSelectPlace: (_) {},
            swapReason: '날씨로 인해 야외에서 실내로 변경',
          ),
        ),
      );
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
      expect(find.text('날씨로 인해 야외에서 실내로 변경'), findsOneWidget);
    });

    testWidgets('no badge when swapReason null', (tester) async {
      final slot = LalaPlanSlot(
        period: 'morning',
        title: '오전',
        place: LalaPlace(
          placeId: 'p2',
          name: '공원',
          category: 'attraction',
          lat: 37.5,
          lng: 127.0,
          address: '서울',
          distanceM: 200,
          source: 'db',
        ),
      );
      await tester.pumpWidget(
        _wrap(PlanSlotTile(slot: slot, language: 'ko', onSelectPlace: (_) {})),
      );
      expect(find.byIcon(Icons.swap_horiz), findsNothing);
    });
  });
}
