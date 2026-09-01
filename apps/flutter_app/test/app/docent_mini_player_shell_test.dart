// 이슈 #120 §9: 미니플레이어/쉘/라우팅 위젯 계약.
// - idle 세션에서는 미니플레이어가 완전히 숨는다.
// - 준비/재생/일시정지 중에는 4-탭 하단 바 '위에' 상주한다.
// - 미니플레이어 탭 → 쉘 외부 전체 플레이어 push, 닫으면 탭 상태 유지.
// - 지도 인-바디 시트가 열리면 하단 체인 전체(미니플레이어 포함)를 내준다.
// 가짜 백엔드/플레이어만 사용 — 네트워크·실 오디오 없음.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/app/lala_main_shell.dart';
import 'package:lala_next_app/app/map_sheet_visibility.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_controller.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_state.dart';
import 'package:lala_next_app/features/docent/playback/docent_audio_player.dart';
import 'package:lala_next_app/features/docent/presentation/pages/docent_player_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/shared/widgets/lala_bottom_nav_bar.dart';

/// 즉시 성공하는 최소 백엔드 — readiness/스크립트/오디오만 구현.
class _ReadyBackend implements LalaBackend {
  @override
  Future<LalaAudioResponse> createDocentAudio({required String script}) async {
    return LalaAudioResponse(
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      requestId: 'mini-player-test',
      contentType: 'audio/mpeg',
      requestHash: null,
      cacheKey: null,
    );
  }

  @override
  Future<LalaEnvelope<LalaDocentScript>> createDocentScript({
    required LalaPlace place,
    LalaWeather? weather,
    String mode = 'brief',
  }) async {
    return LalaEnvelope<LalaDocentScript>(
      ok: true,
      data: LalaDocentScript(
        placeId: place.placeId,
        category: place.category,
        language: 'ko',
        mode: mode,
        script: '행궁동 로컬 도슨트 스크립트입니다.',
        source: 'rule_based_curation',
        requestHash: 'a' * 64,
        cacheKey: 'docent_script:test',
        generatedAt: '2026-09-01T00:00:00+00:00',
      ),
      meta: const <String, dynamic>{'request_id': 'mini-player-test'},
      error: null,
      statusCode: 200,
      requestId: 'mini-player-test',
    );
  }

  @override
  Future<LalaEnvelope<LalaReadiness>> getReadiness() async {
    return LalaEnvelope<LalaReadiness>(
      ok: true,
      data: LalaReadiness(
        status: 'ok',
        checks: const <String, String>{'live_speech': 'enabled'},
        mode: LalaRuntimeMode(
          overall: 'ok',
          data: 'db-backed',
          ai: 'disabled',
          speech: 'live-azure',
          worker: 'dry-run',
        ),
      ),
      meta: const <String, dynamic>{'request_id': 'mini-player-test'},
      error: null,
      statusCode: 200,
      requestId: 'mini-player-test',
    );
  }

  @override
  void close() {}

  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getHealth() async {
    throw UnimplementedError();
  }

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async {
    throw UnimplementedError();
  }

  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getLocalSignals({
    String? region,
    String? placeId,
    String? kind,
    String sort = 'recent',
    String? cursor,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getLocalSignalAggregates({
    int weeks = 4,
    int limit = 20,
    String? placeId,
    String? category,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<LalaEnvelope<LalaWeather>> getWeather() async {
    throw UnimplementedError();
  }

  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() async {
    throw UnimplementedError();
  }

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() async {
    throw UnimplementedError();
  }
}

/// 재생 상태를 테스트가 emit 으로 구동하는 가짜 플레이어.
class _EmittingFakePlayer implements DocentAudioPlayer {
  final ValueNotifier<DocentPlaybackState> _state = ValueNotifier(
    DocentPlaybackState.idle,
  );

  @override
  ValueListenable<DocentPlaybackState> get state => _state;

  void emit(DocentPlaybackState next) => _state.value = next;

  @override
  Future<void> play(Uint8List bytes) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    _state.dispose();
  }
}

LalaPlace _place() {
  return LalaPlace(
    placeId: 'mini-p1',
    name: '행궁동 카페거리',
    category: 'culture',
    lat: 37.2636,
    lng: 127.0286,
    address: '테스트 주소',
    distanceM: 120,
    source: 'db',
  );
}

Future<DocentExperienceController> _controllerWithSession(
  _EmittingFakePlayer player,
) async {
  final controller = DocentExperienceController(
    backendFactory: (_) => _ReadyBackend(),
    baseConfig: const LalaAppConfig(baseUri: 'http://api.test'),
    player: player,
  );
  await controller.playPlace(_place());
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    OnboardingState.reset();
    lalaMapSheetActive.value = false;
  });

  Widget buildApp(DocentExperienceController controller) {
    final router = GoRouter(
      initialLocation: LalaRoutePaths.search,
      routes: <RouteBase>[
        StatefulShellRoute.indexedStack(
          builder:
              (
                BuildContext context,
                GoRouterState state,
                StatefulNavigationShell shell,
              ) => LalaMainShell(
                navigationShell: shell,
                docentExperienceController: controller,
              ),
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: LalaRoutePaths.search,
                  builder: (BuildContext context, GoRouterState state) =>
                      const Text('search-body'),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: LalaRoutePaths.mapRoute,
                  builder: (BuildContext context, GoRouterState state) =>
                      const Text('map-body'),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: LalaRoutePaths.docentPlayer,
          builder: (BuildContext context, GoRouterState state) =>
              DocentPlayerPage(controller: controller),
        ),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('idle 세션에서는 미니플레이어가 숨고 하단 바만 있다', (tester) async {
    OnboardingState.selectLanguage('ko');
    OnboardingState.markCompleted();
    final controller = DocentExperienceController(
      backendFactory: (_) => throw StateError('prefetch 금지'),
      baseConfig: const LalaAppConfig(baseUri: ''),
      player: _EmittingFakePlayer(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(buildApp(controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('docent-mini-player')), findsNothing);
    expect(find.byType(LalaBottomNavBar), findsOneWidget);
  });

  testWidgets('재생 중 미니플레이어가 하단 내비게이션 바 위에 상주한다', (tester) async {
    OnboardingState.selectLanguage('ko');
    OnboardingState.markCompleted();
    final player = _EmittingFakePlayer();
    final controller = await _controllerWithSession(player);
    addTearDown(controller.dispose);
    player.emit(DocentPlaybackState.playing);

    await tester.pumpWidget(buildApp(controller));
    await tester.pumpAndSettle();

    final miniFinder = find.byKey(const ValueKey('docent-mini-player'));
    expect(miniFinder, findsOneWidget);
    final miniRect = tester.getRect(miniFinder);
    final navRect = tester.getRect(find.byType(LalaBottomNavBar));
    expect(miniRect.bottom, lessThanOrEqualTo(navRect.top + 1));
    // 상태 캡션은 실제 재생 상태만 표시한다.
    expect(find.text('재생 중'), findsOneWidget);
    expect(controller.currentState.phase, DocentExperiencePhase.playing);
    expect(find.byKey(const ValueKey('docent-mini-artwork')), findsOneWidget);
    // 테스트 장소에는 검증 이미지가 없으므로 정직한 중성 placeholder를 쓴다.
    expect(find.byIcon(Icons.photo_camera_front_outlined), findsOneWidget);
  });

  testWidgets('미니플레이어 탭 → 전체 플레이어 push, 닫으면 탭 상태 유지', (tester) async {
    OnboardingState.selectLanguage('ko');
    OnboardingState.markCompleted();
    final player = _EmittingFakePlayer();
    final controller = await _controllerWithSession(player);
    addTearDown(controller.dispose);
    player.emit(DocentPlaybackState.playing);

    await tester.pumpWidget(buildApp(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('행궁동 카페거리'));
    await tester.pumpAndSettle();
    expect(find.byType(DocentPlayerPage), findsOneWidget);
    // 쉘 밖 풀스크린 — 하단 바가 이 프레임에 함께 있지 않다.
    expect(find.byType(LalaBottomNavBar), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(DocentPlayerPage), findsNothing);
    // 닫아도 여전히 검색 탭.
    expect(find.text('search-body'), findsOneWidget);
    expect(find.byKey(const ValueKey('docent-mini-player')), findsOneWidget);
  });

  testWidgets('지도 인-바디 시트가 열리면 미니플레이어도 하단 바와 함께 숨는다', (tester) async {
    OnboardingState.selectLanguage('ko');
    OnboardingState.markCompleted();
    final player = _EmittingFakePlayer();
    final controller = await _controllerWithSession(player);
    addTearDown(controller.dispose);
    player.emit(DocentPlaybackState.playing);

    await tester.pumpWidget(buildApp(controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('docent-mini-player')), findsOneWidget);

    lalaMapSheetActive.value = true;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('docent-mini-player')), findsNothing);
    expect(find.byType(LalaBottomNavBar), findsNothing);
  });

  testWidgets('320dp 폭 + 200% 텍스트 스케일에서 미니플레이어가 오버플로우 없이 렌더된다', (tester) async {
    OnboardingState.selectLanguage('ko');
    OnboardingState.markCompleted();
    final player = _EmittingFakePlayer();
    final controller = await _controllerWithSession(player);
    addTearDown(controller.dispose);
    player.emit(DocentPlaybackState.playing);

    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: buildApp(controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('docent-mini-player')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
