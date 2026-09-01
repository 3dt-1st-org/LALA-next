// 이슈 #120 §9: DocentExperienceController 단위 테스트.
// 가짜 백엔드/가짜 플레이어만 사용 — 네트워크, 실 오디오 기기, 라이브 provider 호출 없음.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_controller.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_state.dart';
import 'package:lala_next_app/features/docent/playback/docent_audio_player.dart';

/// 오프라인 백엔드 스텁: 모든 응답을 Completer 로 통제해 stale-response 경합을
/// 실제처럼 재현한다. 요청 카운터로 프리페치/fan-out 계약을 검증한다.
class _ScriptedBackend implements LalaBackend {
  _ScriptedBackend(this.config);

  /// 컨트롤러가 언어별 config 을 팩토리로 전달한다 — 스텁도 그 언어를 반영한다.
  LalaAppConfig config;

  bool liveSpeech = true;
  String scriptText = '행궁동 로컬 도슨트 스크립트입니다.';
  Uint8List audioBytes = Uint8List.fromList([1, 2, 3, 4]);
  bool failReadiness = false;
  bool failScript = false;
  bool failAudio = false;
  bool emptyAudio = false;

  int readinessRequests = 0;
  int scriptRequests = 0;
  int audioRequests = 0;
  int closeCount = 0;

  /// 테스트가 응답 시점을 통제하기 위한 게이트(null = 즉시 응답).
  Completer<void>? readinessGate;
  Completer<void>? scriptGate;
  Completer<void>? audioGate;

  @override
  Future<LalaEnvelope<LalaReadiness>> getReadiness() async {
    readinessRequests += 1;
    await (readinessGate?.future ?? Future<void>.value());
    if (failReadiness) {
      throw const LalaApiException(
        code: 'UPSTREAM_TIMEOUT',
        message: 'Readiness route timed out.',
        statusCode: 504,
        retryable: true,
        requestId: 'scripted-readiness',
      );
    }
    return _envelope(
      LalaReadiness(
        status: 'ok',
        checks: {'live_speech': liveSpeech ? 'enabled' : 'disabled'},
        mode: LalaRuntimeMode(
          overall: 'ok',
          data: 'db-backed',
          ai: 'disabled',
          speech: liveSpeech ? 'live-azure' : 'disabled',
          worker: 'dry-run',
        ),
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaDocentScript>> createDocentScript({
    required LalaPlace place,
    LalaWeather? weather,
    String mode = 'brief',
  }) async {
    scriptRequests += 1;
    await (scriptGate?.future ?? Future<void>.value());
    if (failScript) {
      throw const LalaApiException(
        code: 'DOCENT_SCRIPT_UNAVAILABLE',
        message: 'Docent script route failed.',
        statusCode: 503,
        retryable: true,
        requestId: 'scripted-script',
      );
    }
    // 스텁은 요청 언어를 따른다: en 요청에 한국어 스크립트를 돌려주면
    // usableDocentScript 가 (정확히) 폐기하기 때문이다.
    final text =
        config.lang == 'ko' ? scriptText : 'Local docent script for the visit.';
    return _envelope(
      LalaDocentScript(
        placeId: place.placeId,
        category: place.category,
        language: config.lang,
        mode: mode,
        script: text,
        source: 'rule_based_curation',
        requestHash: 'a' * 64,
        cacheKey: 'docent_script:test',
        generatedAt: '2026-09-01T00:00:00+00:00',
      ),
    );
  }

  @override
  Future<LalaAudioResponse> createDocentAudio({required String script}) async {
    audioRequests += 1;
    await (audioGate?.future ?? Future<void>.value());
    if (failAudio) {
      throw const LalaApiException(
        code: 'DOCENT_AUDIO_UNAVAILABLE',
        message: 'Docent audio route failed.',
        statusCode: 503,
        retryable: true,
        requestId: 'scripted-audio',
      );
    }
    return LalaAudioResponse(
      bytes: emptyAudio ? Uint8List(0) : audioBytes,
      requestId: 'scripted-audio',
      contentType: 'audio/mpeg',
      requestHash: null,
      cacheKey: null,
    );
  }

  @override
  void close() => closeCount += 1;

  // 아래 엔드포인트는 이 컨트롤러 경로에서 호출되지 않는다(카운터로 폭립 검증).
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

/// 오프라인 플레이어 스텁: 재생 상태는 테스트가 emit 으로 구동한다.
class _FakePlayer implements DocentAudioPlayer {
  final ValueNotifier<DocentPlaybackState> _state = ValueNotifier(
    DocentPlaybackState.idle,
  );
  final List<Uint8List> playedBytes = [];
  int pauseCount = 0;
  int resumeCount = 0;
  int stopCount = 0;
  bool disposed = false;

  void emit(DocentPlaybackState next) => _state.value = next;

  @override
  ValueListenable<DocentPlaybackState> get state => _state;

  @override
  Future<void> play(Uint8List bytes) async {
    playedBytes.add(Uint8List.fromList(bytes));
    _state.value = DocentPlaybackState.loading;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    _state.value = DocentPlaybackState.paused;
  }

  @override
  Future<void> resume() async {
    resumeCount++;
    _state.value = DocentPlaybackState.playing;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    _state.value = DocentPlaybackState.idle;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    _state.dispose();
  }
}

LalaEnvelope<T> _envelope<T>(T data) {
  return LalaEnvelope<T>(
    ok: true,
    data: data,
    meta: const {'request_id': 'test-request-id'},
    error: null,
    statusCode: 200,
    requestId: 'test-request-id',
  );
}

LalaPlace _place(String id, {String category = 'attraction'}) {
  return LalaPlace(
    placeId: id,
    name: '$id 이름',
    category: category,
    lat: 37.2636,
    lng: 127.0286,
    address: '테스트 주소',
    distanceM: 120,
    source: 'db',
  );
}

const LalaAppConfig _config = LalaAppConfig(baseUri: 'http://api.test');

class _Harness {
  _Harness()
    : backend = _ScriptedBackend(_config),
      player = _FakePlayer() {
    controller = DocentExperienceController(
      backendFactory: (config) {
        backend.config = config;
        return backend;
      },
      baseConfig: _config,
      player: player,
      languageReader: () => language,
    );
  }

  var language = 'ko';
  final _ScriptedBackend backend;
  final _FakePlayer player;
  late final DocentExperienceController controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('명시적 play 전에 백엔드 호출/생성이 없다(프리페치 금지)', () {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    expect(harness.backend.readinessRequests, 0);
    expect(harness.backend.scriptRequests, 0);
    expect(harness.backend.audioRequests, 0);
    expect(harness.controller.currentState.phase, DocentExperiencePhase.idle);
    expect(harness.controller.currentState.visible, isFalse);
  });

  test('readiness 음성 비활성이면 script/audio 엔드포인트를 부르지 않는다', () async {
    final harness = _Harness()..backend.liveSpeech = false;
    addTearDown(harness.controller.dispose);

    await harness.controller.playPlace(_place('p1'));

    expect(harness.backend.readinessRequests, 1);
    expect(harness.backend.scriptRequests, 0);
    expect(harness.backend.audioRequests, 0);
    expect(harness.controller.currentState.phase, DocentExperiencePhase.unavailable);
    expect(
      harness.controller.currentState.safeMessage,
      '음성 도슨트를 사용할 수 없어요',
    );
  });

  test('readiness 도달 실패도 정직한 unavailable 상태다', () async {
    final harness = _Harness()..backend.failReadiness = true;
    addTearDown(harness.controller.dispose);

    await harness.controller.playPlace(_place('p1'));

    expect(harness.controller.currentState.phase, DocentExperiencePhase.unavailable);
    expect(harness.backend.scriptRequests, 0);
  });

  test('한 장소 happy path: 준비 → 재생 → 일시정지 → 재개 → 정지', () async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);
    final listener = <DocentExperiencePhase>[];
    harness.controller.state.addListener(() {
      listener.add(harness.controller.currentState.phase);
    });

    await harness.controller.playPlace(_place('p1'));
    expect(harness.controller.currentState.phase, DocentExperiencePhase.ready);
    expect(harness.backend.readinessRequests, 1);
    expect(harness.backend.scriptRequests, 1);
    expect(harness.backend.audioRequests, 1);
    expect(harness.player.playedBytes, hasLength(1));

    harness.player.emit(DocentPlaybackState.playing);
    expect(harness.controller.currentState.phase, DocentExperiencePhase.playing);

    await harness.controller.toggleControl();
    expect(harness.player.pauseCount, 1);
    harness.player.emit(DocentPlaybackState.paused);
    expect(harness.controller.currentState.phase, DocentExperiencePhase.paused);

    await harness.controller.toggleControl();
    expect(harness.player.resumeCount, 1);
    harness.player.emit(DocentPlaybackState.playing);
    expect(harness.controller.currentState.phase, DocentExperiencePhase.playing);

    await harness.controller.stop();
    expect(harness.controller.currentState.phase, DocentExperiencePhase.idle);
    expect(harness.controller.currentState.place, isNull);
    expect(harness.controller.currentState.queue, isEmpty);

    // ready/completed → 재생, playing → pause, paused → resume 전환이 모두 관찰되었다.
    expect(listener, contains(DocentExperiencePhase.ready));
    expect(listener, containsAllInOrder(<DocentExperiencePhase>[
      DocentExperiencePhase.playing,
      DocentExperiencePhase.paused,
      DocentExperiencePhase.playing,
    ]));
  });

  test('스크립트 실패/오디오 실패는 안전한 failed 상태를 쓴다(원시 오류 미노출)',
      () async {
    final scriptFail = _Harness()..backend.failScript = true;
    addTearDown(scriptFail.controller.dispose);
    await scriptFail.controller.playPlace(_place('p1'));
    expect(scriptFail.controller.currentState.phase, DocentExperiencePhase.failed);
    expect(
      scriptFail.controller.currentState.safeMessage,
      contains('도슨트 스크립트를 준비하지 못했어요'),
    );
    expect(
      scriptFail.controller.currentState.safeMessage,
      isNot(contains('Docent script route failed')),
    );
    expect(scriptFail.backend.audioRequests, 0);

    final audioFail = _Harness()..backend.failAudio = true;
    addTearDown(audioFail.controller.dispose);
    await audioFail.controller.playPlace(_place('p1'));
    expect(audioFail.controller.currentState.phase, DocentExperiencePhase.failed);
    expect(
      audioFail.controller.currentState.safeMessage,
      contains('도슨트 음성을 준비하지 못했어요'),
    );

    final emptyAudio = _Harness()..backend.emptyAudio = true;
    addTearDown(emptyAudio.controller.dispose);
    await emptyAudio.controller.playPlace(_place('p1'));
    expect(emptyAudio.controller.currentState.phase, DocentExperiencePhase.failed);
    expect(emptyAudio.player.playedBytes, isEmpty);
  });

  test('준비 중 반복 탭은 추가 요청을 만들지 않는다', () async {
    final harness = _Harness()
      ..backend.readinessGate = Completer<void>()
      ..backend.scriptGate = Completer<void>();
    addTearDown(harness.controller.dispose);

    final first = harness.controller.playPlace(_place('p1'));
    final second = harness.controller.playPlace(_place('p1'));
    // 마이크태스크를 흘려 첫 요청이 readiness 게이트에 도달하게 한다.
    await Future<void>.delayed(Duration.zero);
    // 첫 요청이 readiness 게이트에 걸린 동안 두 번째 탭은 무시된다.
    expect(harness.backend.readinessRequests, 1);
    harness.backend.readinessGate!.complete();
    await Future<void>.delayed(Duration.zero);
    harness.backend.scriptGate!.complete();
    await Future<void>.delayed(Duration.zero);
    await first;
    await second;
    expect(harness.backend.scriptRequests, 1);
    expect(harness.backend.audioRequests, lessThanOrEqualTo(1));
  });

  test('새 장소 요청은 이전 재생을 먼저 정지한다', () async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await harness.controller.playPlace(_place('p1'));
    harness.player.emit(DocentPlaybackState.playing);
    final stopsBefore = harness.player.stopCount;

    await harness.controller.playPlace(_place('p2'));

    expect(harness.player.stopCount, greaterThan(stopsBefore));
    expect(harness.controller.currentState.place?.placeId, 'p2');
    expect(harness.controller.currentState.phase, DocentExperiencePhase.ready);
    expect(harness.player.playedBytes.last, harness.backend.audioBytes);
  });

  test('늦은 stale 응답은 오래된 장소/큐를 부활시킬 수 없다', () async {
    final harness = _Harness()..backend.readinessGate = Completer<void>();
    addTearDown(harness.controller.dispose);

    final slow = harness.controller.playPlace(_place('old'));
    // slow 요청이 readiness 게이트에 걸린 사이 사용자가 다른 장소를 시작한다.
    await Future<void>.delayed(Duration.zero);
    final fast = harness.controller.playPlace(_place('new'));
    await Future<void>.delayed(Duration.zero);
    harness.backend.readinessGate!.complete();

    await slow;
    await fast;
    await Future<void>.delayed(Duration.zero);

    expect(harness.controller.currentState.place?.placeId, 'new');
    expect(harness.controller.currentState.phase, isNot(DocentExperiencePhase.failed));
  });

  test('정지는 진행 중 요청을 취소한다(stale 응답 적용 금지)', () async {
    final harness = _Harness()..backend.readinessGate = Completer<void>();
    addTearDown(harness.controller.dispose);

    final pending = harness.controller.playPlace(_place('p1'));
    await Future<void>.delayed(Duration.zero);
    await harness.controller.stop();
    harness.backend.readinessGate!.complete();
    await pending;
    await Future<void>.delayed(Duration.zero);

    expect(harness.controller.currentState.phase, DocentExperiencePhase.idle);
    expect(harness.controller.currentState.place, isNull);
    expect(harness.backend.scriptRequests, 0);
  });

  group('플랜 큐(한 번에 하나의 슬롯만 생성)', () {
    test('완료 시에만 다음 슬롯으로 진행한다', () async {
      final harness = _Harness();
      addTearDown(harness.controller.dispose);
      final places = [
        _place('q1'),
        _place('q2'),
        _place('q3'),
      ];

      await harness.controller.playQueue(places);
      expect(harness.controller.currentState.queueActive, isTrue);
      expect(harness.controller.currentState.queueIndex, 0);
      expect(harness.controller.currentState.place?.placeId, 'q1');
      // 현재 슬롯 하나만 생성했다(3개 fan-out 금지).
      expect(harness.backend.scriptRequests, 1);
      expect(harness.backend.audioRequests, 1);

      harness.player.emit(DocentPlaybackState.playing);
      harness.player.emit(DocentPlaybackState.done);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(harness.controller.currentState.place?.placeId, 'q2');
      expect(harness.controller.currentState.queueIndex, 1);
      expect(harness.backend.scriptRequests, 2);

      harness.player.emit(DocentPlaybackState.playing);
      harness.player.emit(DocentPlaybackState.done);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      harness.player.emit(DocentPlaybackState.playing);
      harness.player.emit(DocentPlaybackState.done);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(harness.controller.currentState.place?.placeId, 'q3');
      expect(harness.backend.scriptRequests, 3);

      // 마지막 슬롯 완료 → 큐 정리 + completed.
      harness.player.emit(DocentPlaybackState.playing);
      harness.player.emit(DocentPlaybackState.done);
      await Future<void>.delayed(Duration.zero);
      expect(harness.controller.currentState.phase, DocentExperiencePhase.completed);
      expect(harness.controller.currentState.queueActive, isFalse);
      expect(harness.backend.scriptRequests, 3);
    });

    test('인접 중복 placeId 는 큐에서 제거된다', () async {
      final harness = _Harness();
      addTearDown(harness.controller.dispose);

      await harness.controller.playQueue([
        _place('q1'),
        _place('q1'),
        _place('q2'),
      ]);
      expect(
        harness.controller.currentState.queue.map((p) => p.placeId).toList(),
        <String>['q1', 'q2'],
      );
    });

    test('큐 정지는 다음 슬롯 생성을 막는다', () async {
      final harness = _Harness();
      addTearDown(harness.controller.dispose);

      await harness.controller.playQueue([_place('q1'), _place('q2')]);
      harness.player.emit(DocentPlaybackState.playing);
      final scriptsBefore = harness.backend.scriptRequests;
      await harness.controller.stop();
      harness.player.emit(DocentPlaybackState.done);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(harness.backend.scriptRequests, scriptsBefore);
      expect(harness.controller.currentState.phase, DocentExperiencePhase.idle);
      expect(harness.controller.currentState.queue, isEmpty);
    });
  });

  test('캐시 식별에는 언어가 포함된다(같은 장소, 다른 언어 = 새 요청)', () async {
    final harness = _Harness();
    addTearDown(harness.controller.dispose);

    await harness.controller.playPlace(_place('p1'));
    expect(harness.backend.scriptRequests, 1);

    // 같은 언어 재생은 캐시를 쓴다 — 새 script/audio 요청이 없다.
    await harness.controller.playPlace(_place('p1'));
    expect(harness.backend.scriptRequests, 1);
    expect(harness.backend.audioRequests, 1);
    expect(harness.controller.currentState.phase, DocentExperiencePhase.ready);

    // 언어가 바뀌면 조용히 재사용하지 않고 새로 생성한다.
    harness.language = 'en';
    await harness.controller.playPlace(_place('p1'));
    expect(harness.backend.scriptRequests, 2);
    expect(harness.backend.audioRequests, 2);
  });

  test('dispose 는 소유 백엔드/플레이어 리소스를 닫는다', () async {
    final harness = _Harness();
    await harness.controller.playPlace(_place('p1'));

    await harness.controller.dispose();

    expect(harness.backend.closeCount, greaterThanOrEqualTo(1));
    expect(harness.player.disposed, isTrue);
    expect(harness.controller.currentState.phase, DocentExperiencePhase.idle);
  });
}
