// 이슈 #120 §4: 앱 루트 도슨트 경험 상태 모델.
// 지도/검색/플랜 어디에서 시작했든 단 하나의 재생 세션만을 기술한다.
// 큐는 메모리 전용(재시작 시 소멸) — 스크립트/오디오 원본은 절대 디스크에 쓰지 않는다.
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

/// 사용자 시작 play 요청부터 재생 완료까지의 경험 단계(이슈 #120 §4.1 상태 다이어그램).
enum DocentExperiencePhase {
  idle,
  checkingReadiness,
  preparingScript,
  preparingAudio,
  ready,
  playing,
  paused,
  completed,
  unavailable,
  failed,
}

class DocentExperienceState {
  const DocentExperienceState({
    this.place,
    this.script,
    this.phase = DocentExperiencePhase.idle,
    this.queue = const <LalaPlace>[],
    this.queueIndex = -1,
    this.safeMessage,
  });

  final LalaPlace? place;
  final LalaDocentScript? script;
  final DocentExperiencePhase phase;
  final List<LalaPlace> queue;
  final int queueIndex;

  /// 사용자에게 노출 가능한 지역화된 안전 메시지(원시 exception 미노출 계약).
  final String? safeMessage;

  /// 플랜 큐 재생이 세션을 소유 중인지(플랜 탭 Play-all → Stop 전환 판단).
  bool get queueActive => queue.isNotEmpty;

  /// 미니플레이어 노출 여부 — idle 에서만 숨긴다(나머지 단계는 정직한 상태 표시).
  bool get visible => phase != DocentExperiencePhase.idle;

  /// 준비/재생 계열 단계(중복 탭 무시 판단에 사용).
  bool get preparing =>
      phase == DocentExperiencePhase.checkingReadiness ||
      phase == DocentExperiencePhase.preparingScript ||
      phase == DocentExperiencePhase.preparingAudio;

  DocentExperienceState copyWith({
    LalaPlace? place,
    bool clearPlace = false,
    LalaDocentScript? script,
    bool clearScript = false,
    DocentExperiencePhase? phase,
    List<LalaPlace>? queue,
    int? queueIndex,
    String? safeMessage,
    bool clearSafeMessage = false,
  }) {
    return DocentExperienceState(
      place: clearPlace ? null : (place ?? this.place),
      script: clearScript ? null : (script ?? this.script),
      phase: phase ?? this.phase,
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
      safeMessage: clearSafeMessage ? null : (safeMessage ?? this.safeMessage),
    );
  }
}
