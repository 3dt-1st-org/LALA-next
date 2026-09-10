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

Dashboard _dashboard(String locale, {required bool dockExpanded}) => Dashboard(
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
  activeSheet: null,
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
  recommendationRailExpanded: false,
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
  onCloseSheet: () {},
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

  // UNVERIFIED (honest gap): long/wrapped MapLibre credits rows live in the
  // embed DOM and cannot be measured from a Flutter widget test, and
  // map.bottom == dock.top is a zero-height boundary that proves nothing
  // about a nonzero-height credits row overlapping the right-gutter
  // FloatingMapControls. No clearance assertion is fabricated here. Runtime
  // pixel verification of the actual DOM credits row (and, if needed, a
  // reserved strip/width rule derived from the real controls gutter) remains
  // with the runtime verifier/controller.
}
