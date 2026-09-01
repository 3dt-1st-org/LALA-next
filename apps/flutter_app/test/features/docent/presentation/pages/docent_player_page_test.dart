// 이슈 #120 §9: 전체 화면 도슨트 플레이어 위젯 계약.
// - source/생성시각/grounding 칩은 실제 스크립트 필드가 있을 때만 렌더(없으면 생략).
// - grounding 은 bounded 지역화 라벨 — 원시 내부 식별자를 노출하지 않는다.
// - 한국어 이름 유틸리티는 nameKo 가 실제로 있을 때만 노출(주소도 실제 있을 때만).
// - 정지는 세션 종료 — 이전 화면으로 pop 되어 빈 Scaffold 에 갇히지 않는다.
// - seek/진행바/시간 표시를 제공하지 않는다(플레이어 미지원 — §6.3).
// - 단일 언어 스크립트만 전문으로 보여준다.
// 가짜 백엔드/플레이어만 사용 — 네트워크·실 오디오 없음.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_controller.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_state.dart';
import 'package:lala_next_app/features/docent/playback/docent_audio_player.dart';
import 'package:lala_next_app/features/docent/presentation/pages/docent_player_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';

/// 스크립트 필드를 테스트가 지정하는 최소 백엔드.
class _ScriptedBackend implements LalaBackend {
  _ScriptedBackend({
    this.script = '행궁동 로컬 도슨트 스크립트입니다.',
    this.generatedAt,
    this.groundingSources,
  });

  String script = '행궁동 로컬 도슨트 스크립트입니다.';
  String? generatedAt;
  List<String>? groundingSources;

  @override
  Future<LalaAudioResponse> createDocentAudio({required String script}) async {
    return LalaAudioResponse(
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      requestId: 'player-page-test',
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
        script: script,
        source: 'rule_based_curation',
        requestHash: 'a' * 64,
        cacheKey: 'docent_script:test',
        generatedAt: generatedAt,
        groundingSources: groundingSources ?? const <String>[],
      ),
      meta: const <String, dynamic>{'request_id': 'player-page-test'},
      error: null,
      statusCode: 200,
      requestId: 'player-page-test',
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
      meta: const <String, dynamic>{'request_id': 'player-page-test'},
      error: null,
      statusCode: 200,
      requestId: 'player-page-test',
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

class _RecordingFakePlayer implements DocentAudioPlayer {
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

LalaPlace _place({
  String? nameKo,
  String name = '행궁동 카페거리',
  String address = '테스트 주소',
}) {
  return LalaPlace(
    placeId: 'player-p1',
    name: name,
    category: 'culture',
    lat: 37.2636,
    lng: 127.0286,
    address: address,
    distanceM: 120,
    source: 'db',
    nameKo: nameKo,
  );
}

Future<DocentExperienceController> _readyController({
  required _ScriptedBackend backend,
  required _RecordingFakePlayer player,
  required LalaPlace place,
}) async {
  final controller = DocentExperienceController(
    backendFactory: (_) => backend,
    baseConfig: const LalaAppConfig(baseUri: 'http://api.test'),
    player: player,
    languageReader: () => 'ko',
  );
  await controller.playPlace(place);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(OnboardingState.reset);

  Widget wrapApp(Widget child) => MaterialApp(home: child);

  testWidgets('source/생성시각/grounding 칩은 실제 필드가 있을 때만 렌더된다', (tester) async {
    OnboardingState.selectLanguage('ko');
    final backend = _ScriptedBackend(
      generatedAt: '2026-09-01T00:00:00+00:00',
      // 실제 source_type 도메인 + 알 수 없는 값 하나(bounded 라벨 수렴 확인).
      groundingSources: const <String>[
        'place_profile',
        'culture_event',
        'community_post',
        'internal_legacy_code',
      ],
    );
    final player = _RecordingFakePlayer();
    final controller = await _readyController(
      backend: backend,
      player: player,
      place: _place(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(wrapApp(DocentPlayerPage(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('LALA 큐레이션'), findsOneWidget);
    expect(find.text('2026.09.01 생성'), findsOneWidget);
    // grounding 은 bounded 지역화 라벨 — 원시 식별자를 노출하지 않는다.
    expect(find.text('장소 프로필'), findsOneWidget);
    expect(find.text('문화 행사 정보'), findsOneWidget);
    expect(find.text('커뮤니티 게시물'), findsOneWidget);
    expect(find.text('참고 자료'), findsOneWidget);
    expect(find.textContaining('internal_legacy_code'), findsNothing);
    // 스크립트 전문은 단일 언어 원문 그대로(리스트 하단 — 스크롤해 확인).
    await tester.scrollUntilVisible(find.text('행궁동 로컬 도슨트 스크립트입니다.'), 120);
    expect(find.text('행궁동 로컬 도슨트 스크립트입니다.'), findsOneWidget);
  });

  testWidgets('generatedAt/grounding 가 없으면 칩을 만들지 않는다(honest 생략)', (
    tester,
  ) async {
    OnboardingState.selectLanguage('ko');
    final backend = _ScriptedBackend();
    final player = _RecordingFakePlayer();
    final controller = await _readyController(
      backend: backend,
      player: player,
      place: _place(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(wrapApp(DocentPlayerPage(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('LALA 큐레이션'), findsOneWidget);
    expect(find.textContaining('생성'), findsNothing);
    expect(find.text('공식 출처'), findsNothing);
    expect(find.text('장소 프로필'), findsNothing);
  });

  testWidgets('파싱 불가능한 generatedAt 은 날짜 라벨로 노출하지 않는다', (tester) async {
    OnboardingState.selectLanguage('ko');
    final backend = _ScriptedBackend(generatedAt: 'not-a-timestamp');
    final player = _RecordingFakePlayer();
    final controller = await _readyController(
      backend: backend,
      player: player,
      place: _place(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(wrapApp(DocentPlayerPage(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('LALA 큐레이션'), findsOneWidget);
    expect(find.textContaining('not-a-timestamp'), findsNothing);
    expect(find.textContaining('생성'), findsNothing);
  });

  testWidgets('nameKo 가 있으면 운전기사 유틸리티가 한국어 이름을 보여준다', (tester) async {
    OnboardingState.selectLanguage('en');
    final backend = _ScriptedBackend(script: 'Local docent script in English.');
    final player = _RecordingFakePlayer();
    final controller = DocentExperienceController(
      backendFactory: (_) => backend,
      baseConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      player: player,
      languageReader: () => 'en',
    );
    await controller.playPlace(
      _place(name: 'Haenggung-dong Cafe Street', nameKo: '행궁동 카페거리'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(wrapApp(DocentPlayerPage(controller: controller)));
    await tester.pumpAndSettle();

    final driverButton = find.byKey(
      const ValueKey('docent-driver-name-button'),
    );
    expect(driverButton, findsOneWidget);
    await tester.tap(driverButton);
    await tester.pumpAndSettle();
    // 시트에는 한국어 원문을 그대로 크게 — 번역/변형 금지.
    expect(find.text('행궁동 카페거리'), findsOneWidget);
    expect(find.text('Korean name'), findsOneWidget);
    // 실제 주소가 있으면 기사님 시트에 함께 노출한다.
    expect(find.text('테스트 주소'), findsOneWidget);
  });

  testWidgets('주소가 없는 장소의 기사님 시트는 주소 줄을 만들지 않는다', (tester) async {
    OnboardingState.selectLanguage('en');
    final backend = _ScriptedBackend(script: 'Local docent script in English.');
    final player = _RecordingFakePlayer();
    final controller = DocentExperienceController(
      backendFactory: (_) => backend,
      baseConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      player: player,
      languageReader: () => 'en',
    );
    await controller.playPlace(
      _place(
        name: 'Haenggung-dong Cafe Street',
        nameKo: '행궁동 카페거리',
        address: '',
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(wrapApp(DocentPlayerPage(controller: controller)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('docent-driver-name-button')));
    await tester.pumpAndSettle();

    expect(find.text('행궁동 카페거리'), findsOneWidget);
    expect(find.text('테스트 주소'), findsNothing);
  });

  testWidgets('정지 버튼은 세션을 끝내고 이전 화면으로 pop 한다(빈 Scaffold 잔류 금지)', (
    tester,
  ) async {
    OnboardingState.selectLanguage('ko');
    final backend = _ScriptedBackend();
    final player = _RecordingFakePlayer();
    final controller = await _readyController(
      backend: backend,
      player: player,
      place: _place(),
    );
    addTearDown(controller.dispose);

    // push 패턴(쉘 밖 전체 플레이어)을 미러: origin 버튼이 /docent-player 로 push.
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) => Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => context.push('/docent-player'),
              child: const Text('open-player'),
            ),
          ),
        ),
        GoRoute(
          path: '/docent-player',
          builder: (BuildContext context, GoRouterState state) =>
              DocentPlayerPage(controller: controller),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open-player'));
    await tester.pumpAndSettle();
    expect(find.byType(DocentPlayerPage), findsOneWidget);

    // 재생 카드는 화면 하단(이미지·헤더 아래)에 있다 — 스크롤해 노출 후 탭.
    final stopIcon = find.byIcon(Icons.stop_rounded);
    await tester.scrollUntilVisible(stopIcon, 200);
    await tester.ensureVisible(stopIcon);
    await tester.pumpAndSettle();
    await tester.tap(stopIcon);
    await tester.pumpAndSettle();

    // 정지 = 세션 종료: 이전 화면으로 돌아가고 컨트롤러는 idle.
    expect(find.byType(DocentPlayerPage), findsNothing);
    expect(find.text('open-player'), findsOneWidget);
    expect(controller.currentState.phase, DocentExperiencePhase.idle);
    expect(controller.currentState.place, isNull);
  });

  testWidgets('nameKo 가 없으면 운전기사 유틸리티를 만들지 않는다', (tester) async {
    OnboardingState.selectLanguage('ko');
    final backend = _ScriptedBackend();
    final player = _RecordingFakePlayer();
    final controller = await _readyController(
      backend: backend,
      player: player,
      place: _place(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(wrapApp(DocentPlayerPage(controller: controller)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('docent-driver-name-button')),
      findsNothing,
    );
  });

  testWidgets('seek 슬라이더/진행 시간 표시를 제공하지 않는다', (tester) async {
    OnboardingState.selectLanguage('ko');
    final backend = _ScriptedBackend();
    final player = _RecordingFakePlayer();
    final controller = await _readyController(
      backend: backend,
      player: player,
      place: _place(),
    );
    addTearDown(controller.dispose);
    player.emit(DocentPlaybackState.playing);

    await tester.pumpWidget(wrapApp(DocentPlayerPage(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    // 남은 시간/총 시간 형태의 텍스트도 없다.
    expect(find.textContaining('00:'), findsNothing);
    // 재생 상태 캡션은 실제 단계 하나만.
    expect(find.text('재생 중'), findsOneWidget);
  });

  testWidgets('320dp 폭 + 200% 텍스트 스케일에서 오버플로우 없이 렌더된다', (tester) async {
    OnboardingState.selectLanguage('ko');
    final backend = _ScriptedBackend(
      generatedAt: '2026-09-01T00:00:00+00:00',
      groundingSources: const <String>[
        'place_profile',
        'culture_event',
        'weather_context',
      ],
    );
    final player = _RecordingFakePlayer();
    final controller = await _readyController(
      backend: backend,
      player: player,
      place: _place(nameKo: '행궁동 카페거리'),
    );
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: wrapApp(DocentPlayerPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('행궁동 로컬 도슨트 스크립트입니다.'), 120);
    // 스크롤 후에도 오버플로우 예외는 없다.
    expect(tester.takeException(), isNull);
    expect(find.text('행궁동 로컬 도슨트 스크립트입니다.'), findsOneWidget);
  });
}
