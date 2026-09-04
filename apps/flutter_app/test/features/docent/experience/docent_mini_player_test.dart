// round2 §3: 미니플레이어 상태 캡션 계약 — 전체 플레이어와 같은 copy SSOT 에서
// 실제 컨트롤러 단계를 그대로 따라간다(단계 구분 캡션 + live region).
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
        script: '행궁동 로컬 도슨트 스크립트입니다.',
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
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() {
    throw UnimplementedError();
  }
}

class _IdleFakePlayer implements DocentAudioPlayer {
  final ValueNotifier<DocentPlaybackState> _state = ValueNotifier(
    DocentPlaybackState.idle,
  );

  @override
  ValueListenable<DocentPlaybackState> get state => _state;

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('미니플레이어 캡션은 실제 준비 단계와 unavailable 을 그대로 따라간다', (tester) async {
    final gate = Completer<void>();
    final backend = _MiniBackend(gate, speechEnabled: false);
    final player = _IdleFakePlayer();
    final controller = DocentExperienceController(
      backendFactory: (_) => backend,
      baseConfig: const LalaAppConfig(baseUri: 'http://api.test'),
      player: player,
      languageReader: () => 'ko',
    );
    addTearDown(controller.dispose);
    unawaited(controller.playPlace(_place()));
    await tester.pump();

    await tester.pumpWidget(
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

    // 준비 중: 실제 1단계 캡션 + 스피너(재생 유혹 없음).
    expect(find.byKey(const ValueKey('docent-mini-player')), findsOneWidget);
    expect(find.text('음성 사용 가능 여부 확인 중'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();

    // unavailable: 정직한 문구 + 재시도 토글(전체 플레이어와 동일 시맨틱).
    expect(controller.currentState.phase, DocentExperiencePhase.unavailable);
    expect(find.text('음성 도슨트를 사용할 수 없어요'), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });
}
