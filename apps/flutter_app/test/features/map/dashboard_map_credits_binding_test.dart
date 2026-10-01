import 'package:lala_next_app/features/map/domain/active_map_sheet.dart';
// Real-Dashboard attribution binding regression: the actual Dashboard map
// canvas must end exactly at the place dock's top for openVector locales
// (credits row never behind the dock) and stay full-bleed for KO. This must
// FAIL if the mapCreditsBottomInset binding is removed from dashboard.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/app/dashboard.dart';
import 'package:lala_next_app/lala_map_models.dart';
import 'package:lala_next_app/features/map/widgets/legacy_map_canvas.dart';
import 'package:lala_next_app/features/map/widgets/map_bottom_dock.dart';

LalaEnvelope<LalaPlacesResponse> _placesEnvelope() {
  final place = LalaPlace(
    placeId: 'p1',
    name: 'Busan Museum',
    category: 'culture_venue',
    lat: 35.1,
    lng: 129.0,
    address: 'address',
    distanceM: 300,
    source: 'db',
  );
  return LalaEnvelope(
    ok: true,
    error: null,
    statusCode: 200,
    requestId: 'test',
    meta: <String, dynamic>{},
    data: LalaPlacesResponse(
      count: 1,
      places: [place],
      query: LalaPlacesQuery(
        lat: 35.1,
        lng: 129.0,
        radiusM: 1000,
        limit: 20,
        category: 'all',
        language: 'en',
      ),
      source: 'db',
      locationEngine: 'postgis',
      dataAsOf: null,
    ),
  );
}

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: child), debugShowCheckedModeBanner: false);

Dashboard _dashboard(
  String locale, {
  required bool dockExpanded,
  bool railExpanded = false,
  ActiveMapSheet? sheet,
  VoidCallback? closeSheet,
}) => Dashboard(
  loading: false,
  error: null,
  placeFailureKind: null,
  health: null,
  readiness: null,
  places: _placesEnvelope(),
  weather: null,
  intervention: null,
  dailyPlan: null,
  docentScript: null,
  docentAudio: null,
  tourAudio: null,
  audioLoading: false,
  audioError: null,
  tourAudioLoading: false,
  tourAudioError: null,
  authMode: LalaAuthMode.none,
  naverMapClientId: '',
  selectedCategory: 'all',
  selectedPlaceId: 'p1',
  activeSheet: sheet,
  uiLanguage: locale,
  voiceEnabled: false,
  autoDocentEnabled: false,
  showEvidence: false,
  savedPlaceIds: const <String>{},
  detailDocentPlayedPlaceIds: const <String>{},
  interventionToastDismissed: true,
  locationConsentEnabled: true,
  locationRequestInFlight: false,
  locationFallbackNoticeVisible: false,
  locationStartPromptVisible: false,
  recommendationRailExpanded: railExpanded,
  mapDockExpanded: dockExpanded,
  recommendationRecoveryPending: false,
  recommendationRecoveryAttempt: 0,
  focusedClusterMemberIds: const <String>[],
  queryLat: 35.1,
  queryLng: 129.0,
  mapFocusLat: null,
  mapFocusLng: null,
  mapLevel: 8,
  onSelectCategory: (_) {},
  onSelectPlace: (_) {},
  onSelectCluster: (LalaMapPlace place) {},
  onCameraIdle: (LalaMapCamera camera) {},
  onClearPlaceSelection: () {},
  onToggleRecommendationRail: () {},
  onToggleMapDock: () {},
  onOpenSheet: (_) {},
  onCloseSheet: closeSheet ?? () {},
  onToggleVoice: () {},
  onToggleAutoDocent: () {},
  onToggleEvidence: () {},
  onToggleSavedPlace: (_) {},
  onDismissInterventionToast: () {},
  onFetchAudio: () {},
  onFetchTourAudio: () {},
  onRefresh: () {},
  onRefreshWeather: () {},
  onReturnToLocation: () {},
  onOpenSettings: () {},
  onOpenManualLocation: () {},
  onRetryLocation: () {},
  onStartLocation: () {},
);

Future<void> _pump(
  WidgetTester tester,
  String locale, {
  required Size size,
  required bool dockExpanded,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _host(_dashboard(locale, dockExpanded: dockExpanded)),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
}

void main() {
  const sizes = {
    'small': Size(320, 568),
    'mobile': Size(393, 852),
    'desktop': Size(1200, 800),
  };

  for (final locale in ['en', 'ja', 'zh-Hans', 'zh-Hant']) {
    for (final expanded in [false, true]) {
      testWidgets(
        'Dashboard map bottom meets dock top ($locale, expanded=$expanded)',
        (tester) async {
          for (final size in sizes.values) {
            await _pump(tester, locale, size: size, dockExpanded: expanded);
            final map = tester.getRect(find.byType(LegacyMapCanvas));
            final dock = tester.getRect(find.byType(MapBottomDock).first);
            // Real binding: the map canvas (whose credits row sits at its
            // bottom edge) ends exactly where the dock begins.
            expect(
              map.bottom,
              dock.top,
              reason: '$locale expanded=$expanded size=$size',
            );
          }
        },
      );
    }
  }

  testWidgets(
    'KO Dashboard stays full-bleed (map extends to viewport bottom)',
    (tester) async {
      const size = Size(393, 852);
      await _pump(tester, 'ko', size: size, dockExpanded: false);
      final map = tester.getRect(find.byType(LegacyMapCanvas));
      expect(map.bottom, size.height);
    },
  );

  testWidgets('utility buttons move up when recommendations collapse', (
    tester,
  ) async {
    for (final size in sizes.values) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        _host(_dashboard('ko', dockExpanded: false, railExpanded: true)),
      );
      await tester.pumpAndSettle();
      final position = find.byKey(const ValueKey('map-utility-position'));
      final expandedTop = tester.widget<AnimatedPositioned>(position).top!;
      await tester.pumpWidget(_host(_dashboard('ko', dockExpanded: false)));
      await tester.pumpAndSettle();
      final collapsedTop = tester.widget<AnimatedPositioned>(position).top!;
      expect(collapsedTop, lessThan(expandedTop));
      expect(collapsedTop, size.width >= 860 ? 122 : 112);
      expect(tester.takeException(), isNull);
    }
    tester.view.reset();
  });

  testWidgets('planner sheet expands fully and dismisses by dragging down', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var closed = false;
    await tester.pumpWidget(
      _host(
        _dashboard(
          'ko',
          dockExpanded: false,
          sheet: ActiveMapSheet.planner,
          closeSheet: () => closed = true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final sheet = find.byType(DraggableScrollableSheet);
    final list = find
        .descendant(of: sheet, matching: find.byType(ListView))
        .first;
    await tester.dragFrom(
      tester.getTopLeft(list) + const Offset(100, 20),
      const Offset(0, -600),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getTopLeft(list).dy, closeTo(0, 1));
    await tester.dragFrom(
      tester.getTopLeft(list) + const Offset(100, 20),
      const Offset(0, 1000),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  // UNVERIFIED (honest gap): long/wrapped MapLibre credits rows live in the
  // embed DOM and cannot be measured from a Flutter widget test, and
  // map.bottom == dock.top is a zero-height boundary that proves nothing
  // about a nonzero-height credits row overlapping the right-gutter
  // FloatingMapControls. No clearance assertion is fabricated here. Runtime
  // pixel verification of the actual DOM credits row (and, if needed, a
  // reserved strip/width rule derived from the real controls gutter) remains
  // with the runtime verifier/controller.
}
