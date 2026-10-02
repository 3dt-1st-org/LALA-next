import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:lala_next_app/home_screen.dart';
import 'package:lala_next_app/manual_location_options.dart';
import 'package:lala_next_app/features/planner/widgets/plan_slot_tile.dart';

void main() {
  for (final language in ['ko', 'en', 'ja', 'zh-Hans', 'zh-Hant']) {
    for (final width in [340.0, 768.0, 1440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('populated home and plan $language $width text $scale', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final search = TextEditingController();
          addTearDown(search.dispose);
          final longName = switch (language) {
            'ko' => '수원화성과 화성행궁 주변 역사 산책길',
            'ja' => '水原華城と華城行宮を巡る歴史散策コース',
            'zh-Hans' => '水原华城与华城行宫周边历史文化步行路线',
            'zh-Hant' => '水原華城與華城行宮周邊歷史文化步行路線',
            _ => 'Suwon Hwaseong Fortress and Haenggung Palace walking trail',
          };
          final places = List.generate(
            6,
            (i) => LalaPlace(
              placeId: 'layout-$i',
              name: '$longName $i',
              nameKo: '수원화성',
              nameEn: '$longName $i',
              category: 'attraction',
              lat: 0,
              lng: 0,
              address: 'Test address',
              distanceM: 1200,
              source: 'db',
            ),
          );
          Widget host(Widget child) => MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(body: child),
            ),
          );
          await tester.pumpWidget(
            host(
              DiscoveryHome(
                searchController: search,
                travelStyles: const [],
                travelMode: 'planned',
                language: language,
                loading: false,
                error: null,
                places: places,
                weather: null,
                dailyPlan: null,
                savedIds: places.take(3).map((p) => p.placeId).toSet(),
                savedPlaces: places.take(3).toList(),
                lat: 0,
                lng: 0,
                region: manualLocationOptions.first,
                onRegion: (_) {},
                onManualRegion: () {},
                onLocate: () {},
                onSave: (_) {},
                onPlace: (_) {},
                onMap: () {},
                onSavedPlaces: () {},
                onPlan: () {},
                onSettings: () {},
                onRefresh: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'populated home');
          await tester.pumpWidget(
            host(
              SingleChildScrollView(
                child: PlanSlotTile(
                  slot: LalaPlanSlot(
                    period: 'lunch',
                    title: 'Lunch',
                    place: places.first,
                    estimatedOpeningHours: '09:00-18:00',
                    travelTimeFromPreviousMinutes: 18,
                  ),
                  language: language,
                  onSelectPlace: (_) {},
                  visitStatus: 'planned',
                  onToggleVisit: () {},
                  onPlayDocent: () {},
                  saved: true,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'populated plan slot');
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
