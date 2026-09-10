// round2 §3 + 런타임 C-2 수정: 미니플레이어 상태 캡션/노출 계약 —
// 전체 플레이어와 같은 copy SSOT 에서 실제 컨트롤러 단계를 그대로 따라가되,
// 큐 없는 unavailable 세션은 미니플레이어 전체를 숨긴다(고스트 스트립 금지).
// 큐 진행 중 unavailable 은 정지(=큐 취소) 탈출구 때문에 그대로 노출한다.
// 가짜 백엔드/플레이어만 사용 — 네트워크·실 오디오 없음.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_controller.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_state.dart';
import 'package:lala_next_app/features/docent/experience/docent_mini_player.dart';
import 'package:lala_next_app/features/docent/playback/docent_audio_player.dart';

class _MiniBackend implements LalaBackend {
  _MiniBackend(this._gate, {required this.speechEnabled});

  final Completer<void> _gate;
  bool speechEnabled;

  /// true 면 usableDocentScript 가 폐기시키는 빈 스크립트을 돌려준다(failed 유도).
  bool emptyScript = false;

  @override
  Future<LalaEnvelope<LalaReadiness>> getReadiness() async {
    await _gate.future;
    return LalaEnvelope<LalaReadiness>(
      ok: true,
      data: LalaReadiness(
        status: 'ok',
        checks: <String, String>{
          'live_speech': speechEnabled ? 'enabled' : 'disabled',
        },
        mode: LalaRuntimeMode(
          overall: 'ok',
          data: 'db-backed',
          ai: 'disabled',
          speech: speechEnabled ? 'live-azure' : 'off',
          worker: 'dry-run',
        ),
      ),
      meta: const <String, dynamic>{'request_id': 'mini-backend'},
      error: null,
      statusCode: 200,
      requestId: 'mini-backend',
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
        script: emptyScript ? '' : '행궁동 로컬 도슨트 스크립트입니다.',
        source: 'rule_based_curation',
        requestHash: 'c' * 64,
        cacheKey: 'docent_script:mini',
        generatedAt: null,
        groundingSources: const <String>[],
      ),
      meta: const <String, dynamic>{'request_id': 'mini-backend'},
      error: null,
      statusCode: 200,
      requestId: 'mini-backend',
    );
  }

  @override
  Future<LalaAudioResponse> createDocentAudio({required String script}) async {
    return LalaAudioResponse(
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      requestId: 'mini-backend',
      contentType: 'audio/mpeg',
      requestHash: null,
      cacheKey: null,
    );
  }

  @override
  void close() {}

  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getHealth() {
    throw UnimplementedError();
  }

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() {
    throw UnimplementedError();
  }

  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getLocalSignals({
    String? region,
    String? placeId,
    String? kind,
    String sort = 'recent',
    String? cursor,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getLocalSignalAggregates({
    int weeks = 4,
    int limit = 20,
    String? placeId,
    String? category,
    String? region,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<LalaEnvelope<LalaWeather>> getWeather() {
    throw UnimplementedError();
  }

  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() {
    throw UnimplementedError();
  }

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({String? selectedPlaceId, LalaPlanPreferenceContext? preferenceContext}) {
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

LalaPlace _place(String id) {
  return LalaPlace(
    placeId: id,
    name: '행궁동 카페거리',
    category: 'culture',
    lat: 37.2636,
    lng: 127.0286,
    address: '테스트 주소',
    distanceM: 120,
    source: 'db',
  );
}

Future<void> _pumpMini(WidgetTester tester, DocentExperienceController controller) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DocentMiniPlayer(
          controller: controller,
          language: 'ko',
          onOpenPlayer: () {},
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('준비 캡션은 실제 단계를 따르고, 큐 없는 unavailable 은 스트립 자체를 숨긴다', (tester) async {
    final gate = Completer<void>();
    final backend = _MiniBackend(gate, speechEnabled: false);
    final controller = DocentExperienceController(
      backendFactory: (_) => backend,
      baseConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      player: _EmittingFakePlayer(),
      languageReader: () => 'ko',
    );
    addTearDown(controller.dispose);
    unawaited(controller.playPlace(_place('mini-p1')));
    await tester.pump();

    await _pumpMini(tester, controller);

    // 준비 중: 실제 1단계 캡션 + 스피너(재생 유혹 없음).
    expect(find.byKey(const ValueKey('docent-mini-player')), findsOneWidget);
    expect(find.text('음성 사용 가능 여부 확인 중'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();

    // unavailable 단일 장소: 재생할 세션이 없으므로 미니플레이어/재시도/정지
    // 모두 만들지 않는다 — 안내·재시도는 전체 플레이어 페이지의 자리다.
    expect(controller.currentState.phase, DocentExperiencePhase.unavailable);
    expect(controller.currentState.queueActive, isFalse);
    expect(find.byKey(const ValueKey('docent-mini-player')), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);
    expect(find.text('음성 도슨트를 사용할 수 없어요'), findsNothing);
  });

  testWidgets('큐 진행 중 unavailable 은 스트립이 남고 정지로 큐를 취소한다', (tester) async {
    final gate = Completer<void>()..complete();
    final backend = _MiniBackend(gate, speechEnabled: false);
    final controller = DocentExperienceController(
      backendFactory: (_) => backend,
      baseConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      player: _EmittingFakePlayer(),
      languageReader: () => 'ko',
    );
    addTearDown(controller.dispose);
    unawaited(
      controller.playQueue(<LalaPlace>[_place('mini-p1'), _place('mini-p2')]),
    );
    await tester.pump();

    await _pumpMini(tester, controller);
    await tester.pumpAndSettle();

    // 큐는 진행 중이다 — 취소 탈출구(정지)와 재시도가 그대로 노출된다.
    expect(controller.currentState.phase, DocentExperiencePhase.unavailable);
    expect(controller.currentState.queueActive, isTrue);
    expect(find.byKey(const ValueKey('docent-mini-player')), findsOneWidget);
    expect(find.textContaining('1/2'), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pumpAndSettle();

    // 정지 = 큐 취소: 세션이 비워지고 스트립도 사라진다(활성 큐 잔류 금지).
    expect(controller.currentState.phase, DocentExperiencePhase.idle);
    expect(controller.currentState.queueActive, isFalse);
    expect(find.byKey(const ValueKey('docent-mini-player')), findsNothing);
  });

  testWidgets('실패한 단일 장소 세션은 재시도 계약 그대로 스트립에 남는다', (tester) async {
    final gate = Completer<void>()..complete();
    final backend = _MiniBackend(gate, speechEnabled: true)..emptyScript = true;
    final controller = DocentExperienceController(
      backendFactory: (_) => backend,
      baseConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      player: _EmittingFakePlayer(),
      languageReader: () => 'ko',
    );
    addTearDown(controller.dispose);
    unawaited(controller.playPlace(_place('mini-p1')));
    await tester.pump();

    await _pumpMini(tester, controller);
    await tester.pumpAndSettle();

    // failed 는 실제 세션이 존재하는 재시도 가능 상태 — 숨기지 않는다.
    expect(controller.currentState.phase, DocentExperiencePhase.failed);
    expect(find.byKey(const ValueKey('docent-mini-player')), findsOneWidget);
    expect(
      find.text('도슨트 스크립트를 준비하지 못했어요. 잠시 후 다시 시도해 주세요.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

    // 재시도는 표시만 바꾸는 게 아니라 실제 재준비로 이어진다.
    backend.emptyScript = false;
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();
    expect(controller.currentState.phase, DocentExperiencePhase.ready);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('ready/playing 캡션과 컨트롤은 기존 계약 그대로 동작한다', (tester) async {
    final gate = Completer<void>()..complete();
    final backend = _MiniBackend(gate, speechEnabled: true);
    final player = _EmittingFakePlayer();
    final controller = DocentExperienceController(
      backendFactory: (_) => backend,
      baseConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      player: player,
      languageReader: () => 'ko',
    );
    addTearDown(controller.dispose);
    unawaited(controller.playPlace(_place('mini-p1')));
    await tester.pump();

    await _pumpMini(tester, controller);
    await tester.pumpAndSettle();

    expect(controller.currentState.phase, DocentExperiencePhase.ready);
    expect(find.text('재생 준비됨'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

    player.emit(DocentPlaybackState.playing);
    await tester.pumpAndSettle();

    expect(controller.currentState.phase, DocentExperiencePhase.playing);
    expect(find.text('재생 중'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });
}
