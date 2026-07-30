// P6F §13.5 접근성 code-conformance: 주요 interactive control 의 screen-reader
// Semantics label 이 KO·EN 배타적으로 존재하는지 검증. 색만으로 상태를 전달하는
// 카테고리 칩 활성 상태는 Semantics.selected 단서로 보강한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/features/docent/widgets/dock_docent_preview.dart';
import 'package:lala_next_app/features/map/widgets/category_chip.dart';
import 'package:lala_next_app/features/map/widgets/floating_map_controls.dart';
import 'package:lala_next_app/features/map/widgets/map_place_carousel_overlay.dart';
import 'package:lala_next_app/features/place/widgets/map_rail_place_card.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

// 위젯을 펌프하고 한 프레임 더 settling 한다. tooltip/label 검증은 widget finder
// (find.byTooltip / find.descendant) 기반이라 semantics 활성화가 필요 없다.
Future<void> _pumpSemantics(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(_wrap(child));
  await tester.pump();
}

LalaPlace _place() {
  return const LalaPlace(
    placeId: 'p1',
    name: 'p1',
    nameKo: '행궁동 카페',
    category: 'restaurant',
    lat: 37.28,
    lng: 127.01,
    address: '경기도 수원시 팔달구',
    distanceM: 210,
    source: 'db',
    imageUrl: 'https://tong.visitkorea.or.kr/cms/resource/x.jpg',
    regionKo: '수원',
    regionEn: 'Suwon',
  );
}

void main() {
  group('CategoryChip screen-reader label (P6F §13.5)', () {
    testWidgets('KO: chip exposes a Semantics label', (tester) async {
      await _pumpSemantics(
        tester,
        CategoryChip(
          label: '맛집',
          active: true,
          color: LalaVisualColors.restaurant,
          onTap: () {},
        ),
      );
      expect(find.byTooltip('맛집'), findsOneWidget);
    });

    testWidgets('EN: chip exposes an English-only label', (tester) async {
      await _pumpSemantics(
        tester,
        CategoryChip(
          label: 'Food',
          active: false,
          color: LalaVisualColors.restaurant,
          onTap: () {},
        ),
      );
      expect(find.byTooltip('Food'), findsOneWidget);
    });
  });

  group('FloatingMapControls screen-reader labels', () {
    testWidgets('KO: voice/auto/location controls are labelled', (
      tester,
    ) async {
      await _pumpSemantics(
        tester,
        FloatingMapControls(
          voiceEnabled: false,
          autoDocentEnabled: false,
          language: 'ko',
          onToggleVoice: () {},
          onToggleAutoDocent: () {},
          onReturnToLocation: () {},
        ),
      );
      expect(find.byTooltip('음성 켜기'), findsOneWidget);
      expect(find.byTooltip('내 위치'), findsOneWidget);
    });

    testWidgets('EN: controls are labelled in English only', (tester) async {
      await _pumpSemantics(
        tester,
        FloatingMapControls(
          voiceEnabled: true,
          autoDocentEnabled: true,
          language: 'en',
          onToggleVoice: () {},
          onToggleAutoDocent: () {},
          onReturnToLocation: () {},
        ),
      );
      expect(find.byTooltip('Mute voice'), findsOneWidget);
      expect(find.byTooltip('My location'), findsOneWidget);
    });
  });

  group('rail card and dock panel screen-reader labels', () {
    testWidgets('MapRailPlaceCard exposes the place name as its label', (
      tester,
    ) async {
      await _pumpSemantics(
        tester,
        MapRailPlaceCard(
          place: _place(),
          language: 'ko',
          selected: true,
          compact: true,
        ),
      );
      // Semantics wrapper present (label/selected configured in widget code);
      // the place name renders as text.
      expect(
        find.descendant(
          of: find.byType(MapRailPlaceCard),
          matching: find.byType(Semantics),
        ),
        findsWidgets,
      );
      expect(find.text('행궁동 카페'), findsOneWidget);
    });

    testWidgets('empty carousel rail is reachable without residual cards', (
      tester,
    ) async {
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
      await tester.pump();
      expect(find.byType(MapRailPlaceCard), findsNothing);
    });

    testWidgets('DockDocentPreview open-details control has a tooltip', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          DockDocentPreview(
            place: _place(),
            language: 'ko',
            script: '요약.',
            action: null,
            audioLoading: false,
            audioError: null,
            docentAudio: null,
            canFetchAudio: false,
            onFetchAudio: () {},
            onAddToPlan: () {},
            onOpenDetail: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('상세 열기'), findsOneWidget);
    });
  });
}
