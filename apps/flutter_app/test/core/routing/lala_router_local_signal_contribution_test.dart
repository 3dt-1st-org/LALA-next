// Router-level contract for the S-31 Local Signals contribution route.
//
// Proves the two restoration paths of `/local-signals/contribute`:
//  - normal S-31 navigation makes the browser-facing route the stable
//    contribution path (never a synthesized `aggregate-unknown` detail id)
//    and carries the coarse region context in-memory via GoRouter extra
//  - a direct URL / web refresh (extra absent) rebuilds contribute mode
//    without attempting a fake signal fetch, and closing from that restored
//    state returns to the Local Signals tab instead of popping an empty
//    navigator
// The URL itself never carries coordinates, region codes, or place ids.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/routing/lala_router.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/core/state/plan_context_store.dart';
import 'package:lala_next_app/core/state/selected_place_store.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_controller.dart';
import 'package:lala_next_app/features/local_signals/presentation/pages/local_signal_detail_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/manual_location_options.dart';

import '../../features/docent/inert_docent_audio_player.dart';

void main() {
  setUp(() {
    OnboardingState.detachPersistence();
    RegionContextStore.detachPersistence();
    OnboardingState.reset();
    RegionContextStore.clear();
    SelectedPlaceStore.clear();
    PlanContextStore.clear();
    OnboardingState.markCompleted();
    OnboardingState.selectLanguage('ko');
  });
  tearDown(() {
    OnboardingState.detachPersistence();
    RegionContextStore.detachPersistence();
    OnboardingState.reset();
    RegionContextStore.clear();
    SelectedPlaceStore.clear();
    PlanContextStore.clear();
  });

  testWidgets(
    'S-31 share entry lands on the dedicated contribution route with region context',
    (tester) async {
      await RegionContextStore.setAndFlush(RegionContext.manual(_busanOption));
      final backend = _RoutingSignalsBackend();
      final router = _router(backend);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      router.go(LalaRoutePaths.localSignals);
      await tester.pumpAndSettle();
      final shareEntry = find.byKey(
        const ValueKey('local-signals-share-experience'),
      );
      // The entry can sit below the fold of the shell viewport.
      await tester.ensureVisible(shareEntry);
      await tester.pumpAndSettle();
      await tester.tap(shareEntry, warnIfMissed: true);
      await tester.pumpAndSettle();

      // The browser-facing route (what a web refresh would reload) is the
      // stable contribution path — not `/local-signals` with a pushed page
      // on top, and not the synthesized `aggregate-unknown` detail id.
      expect(
        router.routeInformationProvider.value.uri.toString(),
        LalaRoutePaths.localSignalContribution,
      );
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        LalaRoutePaths.localSignalContribution,
      );
      final location = router.routeInformationProvider.value.uri.toString();
      expect(location.contains('aggregate'), isFalse);
      expect(location.contains(RegExp(r'lat|lng|coord|region|place')), isFalse);
      // Contribute mode renders through the real auth gate (no session is
      // simulated), and the manual coarse region survived via extra.
      expect(
        find.byKey(const ValueKey('local-signal-auth-connect')),
        findsOneWidget,
      );
      final page = tester.widget<LocalSignalDetailPage>(
        find.byType(LocalSignalDetailPage),
      );
      expect(page.arguments?.contribution, isTrue);
      expect(page.arguments?.contributeRegion?.code, 'busan-haeundae');
    },
  );

  testWidgets(
    'direct contribution URL without extra rebuilds contribute mode (no fake fetch)',
    (tester) async {
      final router = _router(_RoutingSignalsBackend());
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // A deep link / web refresh parses the location without GoRouter extra;
      // router.go with no extra produces the same builder input.
      router.go(LalaRoutePaths.localSignalContribution);
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.toString(),
        LalaRoutePaths.localSignalContribution,
      );
      // Contribution mode restored: auth gate visible, no signal-load spinner
      // or load-failure copy from a fabricated signal id fetch.
      expect(
        find.byKey(const ValueKey('local-signal-auth-connect')),
        findsOneWidget,
      );
      expect(find.text('이 로컬 신호를 불러오지 못했어요.'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final page = tester.widget<LocalSignalDetailPage>(
        find.byType(LocalSignalDetailPage),
      );
      expect(page.arguments?.contribution, isTrue);
      // No in-memory context on a cold URL: the composer falls back to the
      // honest "no region context" copy rather than inventing one.
      expect(page.arguments?.contributeRegion, isNull);

      // Closing the restored page must not pop an empty navigator: the
      // contribution route is the only match, so the exit returns to the
      // Local Signals tab.
      await tester.tap(
        find.byKey(const ValueKey('local-signal-detail-back')),
        warnIfMissed: true,
      );
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.toString(),
        LalaRoutePaths.localSignals,
      );
      expect(find.byType(LocalSignalDetailPage), findsNothing);
    },
  );
}

GoRouter _router(_RoutingSignalsBackend backend) {
  return createLalaRouter(
    backendFactory: (_) => backend,
    initialConfig: const LalaAppConfig(baseUri: 'http://api.test'),
    locationProvider: _DeniedLocationProvider(),
    recommendationRecoveryDelays: const <Duration>[Duration(seconds: 1)],
    authControllerFactory: createLalaAuthController,
    docentExperienceController: DocentExperienceController(
      backendFactory: (_) => backend,
      baseConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      player: InertDocentAudioPlayer(),
    ),
  );
}

const ManualLocationOption _busanOption = ManualLocationOption(
  id: 'busan-haeundae',
  provinceId: 'busan',
  provinceKo: '부산광역시',
  provinceEn: 'Busan',
  labelKo: '해운대구',
  labelEn: 'Haeundae-gu',
  lat: 35.16,
  lng: 129.16,
);

class _DeniedLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() async {
    return const LalaLocationResult.denied();
  }
}

/// Read-only backend for the contribution routing test: a loaded Local
/// Signals feed (so the S-31 share entry is visible) plus the minimal map-tab
/// reads so the initial shell settles without retry timers.
class _RoutingSignalsBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getHealth() async =>
      _rawEnvelope(<String, dynamic>{'status': 'ok'});

  @override
  Future<LalaEnvelope<LalaReadiness>> getReadiness() async => _envelope(
    LalaReadiness(
      status: 'ok',
      checks: const <String, String>{'db': 'configured'},
      mode: const LalaRuntimeMode(
        overall: 'ok',
        data: 'db-backed',
        ai: 'disabled',
        speech: 'disabled',
        worker: 'dry-run',
      ),
    ),
  );

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async => _envelope(
    LalaPlacesResponse(
      count: 0,
      places: const <LalaPlace>[],
      query: const LalaPlacesQuery(
        lat: 37.2636,
        lng: 127.0286,
        radiusM: 3000,
        limit: 60,
        category: 'all',
        language: 'ko',
      ),
      source: 'db',
      locationEngine: 'postgis',
    ),
  );

  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() async => _envelope(
    const LalaIntervention(
      center: LalaCoordinate(lat: 37.2636, lng: 127.0286),
      radiusM: 3000,
      shouldIntervene: false,
      reason: 'ok',
      recommendedAction: '',
      source: 'db',
    ),
  );

  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getLocalSignals({
    String? region,
    String? placeId,
    String? kind,
    String sort = 'recent',
    String? cursor,
  }) async {
    return _rawEnvelope(<String, dynamic>{
      'items': <Map<String, dynamic>>[],
      'next_cursor': null,
      'has_more': false,
    });
  }

  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getLocalSignalAggregates({
    int weeks = 4,
    int limit = 20,
    String? placeId,
    String? category,
  }) async {
    // Aggregates are best-effort; honest-unavailable keeps the feed usable.
    return Future<LalaEnvelope<Map<String, dynamic>>>.error(
      const LalaApiException(
        code: 'LOCAL_SIGNALS_DISABLED',
        message: 'aggregates disabled',
        statusCode: 503,
        retryable: false,
      ),
    );
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used in contribution routing test');
}

LalaEnvelope<Map<String, dynamic>> _rawEnvelope(Map<String, dynamic> data) {
  return LalaEnvelope<Map<String, dynamic>>(
    ok: true,
    data: data,
    meta: const <String, dynamic>{},
    error: null,
    statusCode: 200,
    requestId: null,
  );
}

LalaEnvelope<T> _envelope<T>(T data) {
  return LalaEnvelope<T>(
    ok: true,
    data: data,
    meta: const <String, dynamic>{},
    error: null,
    statusCode: 200,
    requestId: null,
  );
}
