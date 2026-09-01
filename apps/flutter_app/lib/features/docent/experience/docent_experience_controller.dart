// 이슈 #120 §4: 앱 루트 단일 도슨트 경험 소유자.
// 지도 레일/검색 결과/플랜 슬롯 어디에서 재생을 시작해도 이 컨트롤러 하나만이
// 오디오 플레이어와 큐를 소유한다(두 표면이 동시에 재생할 수 없다).
// 네트워크/플랫폼 오디오 없이 단위 테스트 가능해야 한다(§4 주입 계약).
import 'package:flutter/foundation.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../core/backend/lala_backend.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/l10n/lala_copy.dart' show apiRequestLanguage;
import '../../home/home_view_helpers.dart' show isLiveSpeechEnabled;
import '../../onboarding/onboarding_state.dart';
import '../docent_helpers.dart';
import '../playback/docent_audio_player.dart';
import 'docent_experience_copy.dart';
import 'docent_experience_state.dart';

/// 준비 완료 세션(스크립트 + 실제 오디오 바이트). 메모리 캐시 전용 값.
class _PreparedDocent {
  const _PreparedDocent({required this.script, required this.audio});

  final LalaDocentScript script;
  final LalaAudioResponse audio;
}

/// 앱 루트 도슨트 경험 컨트롤러(이슈 #120 §4).
///
/// - 명시적 사용자 play 액션 전에 어떤 백엔드 호출도 하지 않는다(프리페치 금지).
/// - readiness 가 음성 사용 불가면 스크립트/오디오 엔드포인트를 부르지 않는다.
/// - 늦은 비동기 응답은 revision token 로 폐기된다(오래된 장소/큐 부활 금지).
/// - 큐는 현재 슬롯 하나만 생성한다(4개 동시 fan-out 금지).
/// - 캐시 키는 placeId + API 언어 — 언어가 바뀌면 조용히 재사용하지 않는다.
class DocentExperienceController {
  DocentExperienceController({
    required this.backendFactory,
    required this.baseConfig,
    DocentAudioPlayer? player,
    String Function()? languageReader,
  }) : _player = player ?? AudioplayersDocentAudioPlayer(),
       _languageReader = languageReader ?? (() => OnboardingState.language) {
    _player.state.addListener(_onPlayerStateChanged);
  }

  final LalaBackendFactory backendFactory;
  final LalaAppConfig baseConfig;
  final DocentAudioPlayer _player;
  final String Function() _languageReader;

  final ValueNotifier<DocentExperienceState> _state = ValueNotifier(
    const DocentExperienceState(),
  );

  /// 백엔드는 첫 재생 요청까지 생성하지 않는다(생성 자체가 프리페치가 되지 않게).
  LalaBackend? _backend;
  String? _backendLanguage;

  /// 현재 세션이 소유한 준비 완료 오디오(재개/재생에 사용).
  _PreparedDocent? _prepared;

  /// 메모리 전용 캐시. 키 = 'placeId:apiLanguage'. 재시작 시 소멸(§4).
  final Map<String, _PreparedDocent> _cache = <String, _PreparedDocent>{};

  /// Monotonic revision. 새 요청/정지마다 증가하고, 오래된 async 연속은 폐기된다.
  int _revision = 0;

  bool _disposed = false;

  ValueListenable<DocentExperienceState> get state => _state;

  DocentExperienceState get currentState => _state.value;

  /// 사용자가 단일 장소 재생을 명시적으로 요청(맵 레일/검색 타일/플랜 슬롯).
  /// 준비 중인 '같은 대상'의 반복 탭만 무시한다(§4.1 규칙) — 다른 장소 요청은
  /// 진행 중 준비를 대체한다. 준비가 사용자의 새 선택을 가로채지 않게 하기 위함.
  Future<void> playPlace(LalaPlace place) {
    final current = _state.value;
    if (current.preparing &&
        !current.queueActive &&
        current.place?.placeId == place.placeId) {
      return Future<void>.value();
    }
    return _prepare(
      place,
      queue: const <LalaPlace>[],
      queueIndex: -1,
    );
  }

  /// 플랜 '전체 도슨트 듣기'. 보이는 슬롯 순서 그대로, 인접 중복 placeId 는 제거.
  /// 현재 슬롯만 생성하고 완료 시에만 다음 슬롯으로 진행한다.
  Future<void> playQueue(List<LalaPlace> stops) {
    if (_state.value.preparing) {
      return Future<void>.value();
    }
    final deduped = <LalaPlace>[];
    for (final stop in stops) {
      if (deduped.isNotEmpty && deduped.last.placeId == stop.placeId) {
        continue;
      }
      deduped.add(stop);
    }
    if (deduped.isEmpty) {
      return Future<void>.value();
    }
    final current = _state.value;
    if (current.preparing &&
        current.queueActive &&
        _samePlaceIds(current.queue, deduped)) {
      return Future<void>.value();
    }
    return _prepare(deduped.first, queue: deduped, queueIndex: 0);
  }

  bool _samePlaceIds(List<LalaPlace> a, List<LalaPlace> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i].placeId != b[i].placeId) {
        return false;
      }
    }
    return true;
  }

  /// 미니플레이어/플레이어의 단일 컨트롤: 재생↔일시정지, 준비 완료 후 재생,
  /// unavailable/failed 에서는 재시도로 연결된다.
  Future<void> toggleControl() {
    final current = _state.value;
    switch (current.phase) {
      case DocentExperiencePhase.playing:
        return _player.pause();
      case DocentExperiencePhase.paused:
        return _player.resume();
      case DocentExperiencePhase.ready:
      case DocentExperiencePhase.completed:
        final bytes = _prepared?.audio.bytes;
        if (bytes != null && bytes.isNotEmpty) {
          return _player.play(bytes);
        }
        return Future<void>.value();
      case DocentExperiencePhase.unavailable:
      case DocentExperiencePhase.failed:
        return retry();
      case DocentExperiencePhase.idle:
      case DocentExperiencePhase.checkingReadiness:
      case DocentExperiencePhase.preparingScript:
      case DocentExperiencePhase.preparingAudio:
        // 준비 중 반복 탭 무시 + idle 은 재생할 것이 없다.
        return Future<void>.value();
    }
  }

  /// unavailable/failed → 현재 장소 재준비(§4.1 재시도 전환).
  Future<void> retry() {
    final current = _state.value;
    final place = current.place;
    if (place == null || current.preparing) {
      return Future<void>.value();
    }
    return _prepare(
      place,
      queue: current.queue,
      queueIndex: current.queueIndex,
    );
  }

  /// 정지 + 큐 취소. 대기 중 생성을 막고 세션을 idle 로 비운다.
  Future<void> stop() async {
    _revision++;
    _prepared = null;
    _state.value = const DocentExperienceState();
    try {
      await _player.stop();
    } on Object {
      // 정지는 이미 상태를 비웠다 — 플레이어 오류를 여기서 되살리지 않는다.
    }
  }

  /// 소유 리소스(백엔드/플레이어)를 결정적으로 정리한다.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _revision++;
    _cache.clear();
    _prepared = null;
    _state.value = const DocentExperienceState();
    _player.state.removeListener(_onPlayerStateChanged);
    _backend?.close();
    _backend = null;
    await _player.dispose();
    _state.dispose();
  }

  Future<void> _prepare(
    LalaPlace place, {
    required List<LalaPlace> queue,
    required int queueIndex,
  }) async {
    final revision = ++_revision;
    _prepared = null;
    // 이전 재생을 먼저 멈추고(§4.1) stop 은 fire-and-forget 으로 걸어 둔 채
    // phase 를 동기적으로 checkingReadiness 로 올린다 — await 없이 연타된 두 번째
    // 탭이 preparing 가드를 통과하지 못하게 한다.
    final previousStop = _player.stop();
    // 언어는 사용자가 재생을 요청한 시점에 읽는다(§4 주입 계약).
    final language = _languageReader();
    _state.value = DocentExperienceState(
      place: place,
      phase: DocentExperiencePhase.checkingReadiness,
      queue: queue,
      queueIndex: queueIndex,
    );
    try {
      await previousStop;
    } on Object {
      // 이전 세션 정리 실패는 새 준비를 막지 않는다.
    }
    if (_stale(revision)) {
      return;
    }
    try {
      final backend = _backendFor(language);
      final LalaEnvelope<LalaReadiness> readiness;
      try {
        readiness = await backend.getReadiness();
      } on Object {
        // readiness 도달 실패는 정직한 unavailable 상태다(§4.1 규칙).
        if (!_stale(revision)) {
          _state.value = _state.value.copyWith(
            phase: DocentExperiencePhase.unavailable,
            safeMessage: speechUnavailableMessage(language),
          );
        }
        return;
      }
      if (_stale(revision)) {
        return;
      }
      if (!isLiveSpeechEnabled(readiness.data)) {
        _state.value = _state.value.copyWith(
          phase: DocentExperiencePhase.unavailable,
          safeMessage: speechUnavailableMessage(language),
        );
        return;
      }

      _state.value = _state.value.copyWith(
        phase: DocentExperiencePhase.preparingScript,
      );

      final cacheKey = '${place.placeId}:${apiRequestLanguage(language)}';
      final cached = _cache[cacheKey];
      final _PreparedDocent prepared;
      if (cached != null) {
        prepared = cached;
      } else {
        final scriptEnvelope = await backend.createDocentScript(place: place);
        if (_stale(revision)) {
          return;
        }
        final script = scriptEnvelope.data;
        final scriptText = usableDocentScript(script?.script, language);
        if (script == null || scriptText == null || scriptText.isEmpty) {
          _state.value = _state.value.copyWith(
            phase: DocentExperiencePhase.failed,
            safeMessage: docentScriptFailureMessage(language),
          );
          return;
        }
        _state.value = _state.value.copyWith(
          phase: DocentExperiencePhase.preparingAudio,
          script: script,
        );
        final audio = await backend.createDocentAudio(script: scriptText);
        if (_stale(revision)) {
          return;
        }
        // 빈 바이트 = 실제 재생 가능한 것이 없다 — 절대 가짜로 재생하지 않는다.
        if (audio.bytes.isEmpty) {
          _state.value = _state.value.copyWith(
            phase: DocentExperiencePhase.failed,
            safeMessage: docentAudioFailureMessageLocalized(language),
          );
          return;
        }
        prepared = _PreparedDocent(script: script, audio: audio);
        _cache[cacheKey] = prepared;
      }

      if (_stale(revision)) {
        return;
      }
      _prepared = prepared;
      _state.value = _state.value.copyWith(
        place: place,
        script: prepared.script,
        phase: DocentExperiencePhase.ready,
        clearSafeMessage: true,
      );
      await _player.play(prepared.audio.bytes);
    } on Object {
      if (_stale(revision)) {
        return;
      }
      // 원시 오류 본문을 노출하지 않고 bounded 문구로 수렴(§4.1 규칙).
      final message = _state.value.phase == DocentExperiencePhase.preparingAudio
          ? docentAudioFailureMessageLocalized(language)
          : docentScriptFailureMessage(language);
      _state.value = _state.value.copyWith(
        phase: DocentExperiencePhase.failed,
        safeMessage: message,
      );
    }
  }

  /// 요청 언어가 바뀌면 백엔드를 재구성한다(언어별 config 이외는 불변).
  LalaBackend _backendFor(String language) {
    if (_backend == null || _backendLanguage != language) {
      _backend?.close();
      _backend = backendFactory(baseConfig.copyWith(lang: language));
      _backendLanguage = language;
    }
    return _backend!;
  }

  bool _stale(int revision) => _disposed || revision != _revision;

  void _onPlayerStateChanged() {
    if (_disposed) {
      return;
    }
    final playback = _player.state.value;
    final current = _state.value;
    switch (playback) {
      case DocentPlaybackState.playing:
        // ready/completed 에서 시작한 재생만 experience playing 으로 반영한다.
        if (current.phase == DocentExperiencePhase.ready ||
            current.phase == DocentExperiencePhase.playing ||
            current.phase == DocentExperiencePhase.paused ||
            current.phase == DocentExperiencePhase.completed) {
          _state.value = current.copyWith(
            phase: DocentExperiencePhase.playing,
          );
        }
      case DocentPlaybackState.paused:
        if (current.phase == DocentExperiencePhase.playing) {
          _state.value = current.copyWith(phase: DocentExperiencePhase.paused);
        }
      case DocentPlaybackState.done:
        if (current.phase == DocentExperiencePhase.playing ||
            current.phase == DocentExperiencePhase.paused) {
          _onPlaybackCompleted();
        }
      case DocentPlaybackState.error:
        if (current.phase == DocentExperiencePhase.ready ||
            current.phase == DocentExperiencePhase.playing ||
            current.phase == DocentExperiencePhase.paused ||
            current.phase == DocentExperiencePhase.completed) {
          _state.value = current.copyWith(
            phase: DocentExperiencePhase.failed,
            safeMessage: docentAudioFailureMessageLocalized(
              _languageReader(),
            ),
          );
        }
      case DocentPlaybackState.idle:
      case DocentPlaybackState.loading:
        // 경험 단계는 컨트롤러 자체 preparing/stop 흐름이 주도한다.
        break;
    }
  }

  /// 재생 완료: 큐에 다음 슬롯이 있으면 그 슬롯만 새로 준비하고,
  /// 큐가 끝났으면 큐를 비우고 completed 로 마무리한다(§4.1 다이어그램).
  void _onPlaybackCompleted() {
    final current = _state.value;
    if (current.queueActive && current.queueIndex < current.queue.length - 1) {
      final nextIndex = current.queueIndex + 1;
      final next = current.queue[nextIndex];
      // fire-and-forget: 완료 리스너는 동기 컨텍스트에서 반환해야 한다.
      _prepare(next, queue: current.queue, queueIndex: nextIndex);
      return;
    }
    _state.value = current.copyWith(
      phase: DocentExperiencePhase.completed,
      queue: const <LalaPlace>[],
      queueIndex: -1,
    );
  }
}
