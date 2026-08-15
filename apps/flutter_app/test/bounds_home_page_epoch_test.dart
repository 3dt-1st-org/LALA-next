// V1 bounds-query (Lane B) — D5 response-ordering + D4 bounds-threading tests.
//
// D5: a fake backend with completer-controlled getPlaces returns results
// OUT-OF-ORDER. Two _refresh dispatches are driven directly via a test seam;
// the newer result is applied, the stale earlier one is discarded by the
// monotonic request-epoch guard (D5 response-ordering).
//
// D4: a camera-idle carrying viewport bounds is simulated; the bounds thread
// through _currentConfig() into the backend's LalaAppConfig (D4).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/app/lala_app.dart';
import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/features/home/home_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/kakao_map_models.dart';

LalaEnvelope<T> _envelope<T>(T data) => LalaEnvelope<T>(
  ok: true,
  data: data,
  meta: const {'request_id': 'bounds-test'},
  error: null,
  statusCode: 200,
  requestId: 'bounds-test',
);

LalaPlace _placeNamed(String id, String name) => LalaPlace(
  placeId: id,
  name: name,
  nameKo: name,
  nameEn: name,
  category: 'attraction',
  lat: 37.28,
  lng: 127.01,
  address: 'addr',
  regionKo: '수원',
  regionEn: 'Suwon',
  distanceM: 100,
  source: 'db',
  upstreamSource: 'tour_api',
  score: const LalaPlaceScore(
    finalScore: 0.8,
    formulaVersion: 'local-value-v2',
    components: LalaPlaceScoreComponents(
      localSpendingScore: 0.8,
      smallMerchantFitScore: 0.7,
      demandDispersionScore: 0.7,
      weatherFitScore: 0.7,
      reviewQualityScore: null,
      cultureRelevanceScore: 0.8,
      accessibilityFitScore: 0.6,
    ),
    dataBasis: 'analytics.place_score_snapshots',
    features: <String, dynamic>{},
  ),
);

LalaPlacesResponse _placesResponse(String id, String name) =>
    LalaPlacesResponse(
      count: 1,
      places: [_placeNamed(id, name)],
      query: LalaPlacesQuery(
        lat: 37.28,
        lng: 127.01,
        radiusM: 3000,
        limit: 60,
        category: 'all',
        language: 'ko',
      ),
      source: 'db',
      locationEngine: 'db',
    );

/// Minimal fake: only getPlaces is test-controlled (per-backend completer).
/// Every other endpoint throws — `_refresh`'s loadOptional catches each with
/// reportError disabled, so they neither pollute the error surface nor block
/// the refresh. This isolates the places await as the sole race gate.
class _EpochBackend implements LalaBackend {
  _EpochBackend(this.config);

  final LalaAppConfig config;
  final Completer<LalaEnvelope<LalaPlacesResponse>> placesCompleter =
      Completer<LalaEnvelope<LalaPlacesResponse>>();

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() =>
      placesCompleter.future;

  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getHealth() =>
      throw StateError('disabled');
  @override
  Future<LalaEnvelope<LalaReadiness>> getReadiness() =>
      throw StateError('disabled');
  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getLocalSignals({
    String? region,
    String? placeId,
    String? kind,
    String sort = 'recent',
    String? cursor,
  }) => throw StateError('disabled');
  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getLocalSignalAggregates({
    int weeks = 4,
    int limit = 20,
    String? placeId,
    String? category,
  }) => throw StateError('disabled');
  @override
  Future<LalaEnvelope<LalaWeather>> getWeather() =>
      throw StateError('disabled');
  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() =>
      throw StateError('disabled');
  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() =>
      throw StateError('disabled');
  @override
  Future<LalaEnvelope<LalaDocentScript>> createDocentScript({
    required LalaPlace place,
    LalaWeather? weather,
    String mode = 'brief',
  }) => throw StateError('disabled');
  @override
  Future<LalaAudioResponse> createDocentAudio({required String script}) =>
      throw StateError('disabled');
  @override
  void close() {}
}

/// Immediate-resolve location provider: avoids the 2 s initial-location
/// fallback timer so no Timer is left pending at teardown.
class _ImmediateLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() => Future.value(
    const LalaLocationResult.found(LalaLocation(lat: 37.28, lng: 127.01)),
  );
}

LalaAuthController _disabledAuthController(LalaAppAuthDependencies _) {
  // config.enabled is false → controller stays disabled, never fires the
  // busy→signedIn transition that would trigger an auth-driven refresh.
  return LalaAuthController(
    config: const LalaAuthConfig(
      endpoint: '',
      appId: '',
      apiAudience: '',
      redirectUri: '',
    ),
    gateway: _DisabledAuthGateway(),
    accountApi: _DisabledAccountApi(),
  );
}

class _DisabledAuthGateway implements LalaAuthGateway {
  @override
  Future<bool> get isAuthenticated async => false;
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<String?> accessToken(String resource) async => null;
}

class _DisabledAccountApi implements LalaAccountApi {
  @override
  Future<LalaMe> getMe() => throw StateError('disabled');
  @override
  Future<void> deleteMe({required String confirmation}) async {}
}

Widget _app({required LalaBackendFactory backendFactory}) {
  OnboardingState.selectLanguage('ko');
  OnboardingState.markCompleted();
  // Use LalaApp (MaterialApp.router + theme) so the Dashboard renders places
  // identically to the production/widget_test harness.
  return LalaApp(
    backendFactory: backendFactory,
    initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
    locationProvider: _ImmediateLocationProvider(),
    recommendationRecoveryDelays: const <Duration>[Duration(hours: 1)],
    authControllerFactory: _disabledAuthController,
  );
}

/// Pump until the initial (location-driven) refresh has created its backend,
/// then resolve it so the app reaches a "places loaded" state before the
/// bounds-driven refreshes are driven. Bounded pumps are used (no
/// pumpAndSettle) because the home page's recovery/timer machinery can keep
/// the frame loop alive.
Future<void> _primeInitialRefresh(
  WidgetTester tester,
  List<_EpochBackend> backends,
) async {
  // Let initState + postFrame + immediate-location resolution start refresh #0.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  // refresh #0's backend is the 2nd created (index 0 = initState, 1 = refresh).
  expect(backends.length, greaterThanOrEqualTo(2));
  backends[1].placesCompleter.complete(
    _envelope(_placesResponse('initial', '초기 장소')),
  );
  // Flush the post-places microtasks (dailyPlan/weather/docent all throw →
  // caught by loadOptional) without requiring a fully idle frame loop.
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
}

/// Bounded flush replacing pumpAndSettle (which hangs on the home page's
/// lingering timer/recovery machinery).
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  testWidgets(
    'D5 response-ordering: a stale earlier places result is discarded when a '
    'newer query has fired',
    (tester) async {
      final backends = <_EpochBackend>[];
      await tester.pumpWidget(
        _app(
          backendFactory: (config) {
            final backend = _EpochBackend(config);
            backends.add(backend);
            return backend;
          },
        ),
      );
      await _primeInitialRefresh(tester, backends);

      // Descendant context so the seam's findAncestorStateOfType resolves.
      final context = tester.element(
        find.descendant(
          of: find.byType(LalaHomePage),
          matching: find.byType(Scaffold),
        ),
      );

      // Dispatch refresh #1, then refresh #2 BEFORE #1 resolves — two
      // overlapping queries. Each gets its own backend/epoch.
      LalaHomePage.simulateRefreshForTesting(context);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 5));
      LalaHomePage.simulateRefreshForTesting(context);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 5));

      // The last two backends are the two overlapping refreshes. The newest
      // (last) wins; the prior (second-to-last) is stale.
      expect(
        backends.length,
        4,
        reason: 'init + initial-refresh + two simulated',
      );
      final freshBackend = backends.last;
      final staleBackend = backends[backends.length - 2];

      // Resolve the NEWER result first, then flush so its refresh applies.
      freshBackend.placesCompleter.complete(
        _envelope(_placesResponse('fresh-b', 'FRESH-PLACE-B')),
      );
      await _flush(tester);

      // The NEWER candidate set is the one held in state (request-epoch guard:
      // the latest dispatch's result applies). Verified via the state seam
      // rather than text-finding, which is fragile to dashboard layout.
      var places = LalaHomePage.placesStateForTesting(context);
      expect(places.count, 1);
      expect(places.firstName, 'FRESH-PLACE-B');
      expect(places.loading, isFalse);

      // Now resolve the STALE (earlier) result — it must NOT overwrite the
      // newer candidate set already in state.
      staleBackend.placesCompleter.complete(
        _envelope(_placesResponse('stale-a', 'STALE-PLACE-A')),
      );
      await _flush(tester);

      places = LalaHomePage.placesStateForTesting(context);
      expect(places.count, 1);
      // The stale result was discarded; the newer name is still in state.
      expect(places.firstName, 'FRESH-PLACE-B');
      expect(places.firstName, isNot('STALE-PLACE-A'));

      // Resolve the remaining (init-state) backend completer so no future is
      // left dangling mid-frame at teardown.
      backends[0].placesCompleter.complete(
        _envelope(_placesResponse('init', 'INIT')),
      );
      await _flush(tester);
    },
  );

  testWidgets(
    'D4 bounds threading: camera-idle bounds reach the backend config',
    (tester) async {
      final recordedConfigs = <LalaAppConfig>[];
      final backends = <_EpochBackend>[];
      await tester.pumpWidget(
        _app(
          backendFactory: (config) {
            recordedConfigs.add(config);
            final backend = _EpochBackend(config);
            backends.add(backend);
            return backend;
          },
        ),
      );
      await _primeInitialRefresh(tester, backends);

      final context = tester.element(
        find.descendant(
          of: find.byType(LalaHomePage),
          matching: find.byType(Scaffold),
        ),
      );
      LalaHomePage.simulateCameraIdleForTesting(
        context,
        const KakaoMapCamera(
          lat: 37.28,
          lng: 127.01,
          level: 4,
          bounds: KakaoMapBounds(
            swLat: 37.0,
            swLng: 126.0,
            neLat: 38.0,
            neLng: 128.0,
          ),
        ),
      );
      // Advance past the 450 ms debounce so the bounds-driven refresh fires.
      await tester.pump(const Duration(milliseconds: 460));
      await tester.pump();

      // The config handed to the backend for the bounds-driven refresh carries
      // the viewport rectangle (D4). Lane A wires the client forwarding.
      final boundsConfig = recordedConfigs.lastWhere(
        (c) => c.bounds != null,
        orElse: () => const LalaAppConfig(baseUri: ''),
      );
      expect(boundsConfig.bounds, isNotNull);
      expect(boundsConfig.bounds!.swLat, 37.0);
      expect(boundsConfig.bounds!.neLng, 128.0);

      // Resolve the suspended refresh so no Timer/future is pending at teardown.
      backends.last.placesCompleter.complete(
        _envelope(_placesResponse('bounds-p', 'BOUNDS 장소')),
      );
      await _flush(tester);
      // Also resolve the init-state backend completer (never awaited, but kept
      // dangling) for a clean clock.
      backends[0].placesCompleter.complete(
        _envelope(_placesResponse('init', 'INIT')),
      );
      await _flush(tester);
    },
  );
}
