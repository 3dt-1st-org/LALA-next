// 이슈 #120 §6.2: 4-탭 하단 내비게이션 바 위에 상주하는 도슨트 미니플레이어.
// 재생 상태는 컨트롤러의 실제 단계만 그대로 표시한다 — duration/seek/챕터 같은
// 지원되지 않는 정보는 만들지 않는다(§6.3 준수). 색은 tour_audio_bar 의
// 기존 앰버 토큰 계열을 그대로 재사용한다(새 토큰 금지).
import 'package:flutter/material.dart';

import '../../../shared/l10n/place_labels.dart';
import 'docent_experience_controller.dart';
import 'docent_experience_copy.dart';
import 'docent_experience_state.dart';

class DocentMiniPlayer extends StatelessWidget {
  const DocentMiniPlayer({
    super.key,
    required this.controller,
    required this.language,
    required this.onOpenPlayer,
  });

  final DocentExperienceController controller;
  final String language;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DocentExperienceState>(
      valueListenable: controller.state,
      builder: (BuildContext context, DocentExperienceState state, Widget? _) {
        // idle 세션은 미니플레이어를 완전히 숨긴다(§9 위젯 계약).
        final place = state.place;
        if (!state.visible || place == null) {
          return const SizedBox.shrink();
        }
        final queuePrefix = state.queueActive
            ? '${docentMiniQueueProgress(state.queueIndex, state.queue.length)} · '
            : '';
        final caption =
            state.safeMessage ??
            docentExperiencePhaseLabel(state.phase, language);
        return Container(
          key: const ValueKey('docent-mini-player'),
          margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          padding: const EdgeInsets.fromLTRB(6, 4, 2, 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF5C842)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Semantics(
                  label: docentOpenPlayerSemanticLabel(language),
                  button: true,
                  child: InkWell(
                    onTap: onOpenPlayer,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      child: Row(
                        children: <Widget>[
                          _DocentMiniPhaseIcon(phase: state.phase),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  placeDisplayName(place, language),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF744210),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    '$queuePrefix$caption',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF92400E),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _DocentMiniControlButton(
                phase: state.phase,
                language: language,
                onPressed: controller.toggleControl,
              ),
              SizedBox(
                width: 44,
                height: 44,
                child: Semantics(
                  label: docentStopSemanticLabel(language),
                  button: true,
                  child: IconButton(
                    onPressed: controller.stop,
                    icon: const Icon(
                      Icons.stop_rounded,
                      color: Color(0xFFC87F11),
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: docentStopSemanticLabel(language),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 단계 아이콘 — 실제 단계만 반영(준비 중 스피너, 재생 파형, 완료 체크 등).
class _DocentMiniPhaseIcon extends StatelessWidget {
  const _DocentMiniPhaseIcon({required this.phase});

  final DocentExperiencePhase phase;

  @override
  Widget build(BuildContext context) {
    switch (phase) {
      case DocentExperiencePhase.checkingReadiness:
      case DocentExperiencePhase.preparingScript:
      case DocentExperiencePhase.preparingAudio:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case DocentExperiencePhase.ready:
      case DocentExperiencePhase.playing:
      case DocentExperiencePhase.paused:
        return const Icon(
          Icons.graphic_eq,
          size: 20,
          color: Color(0xFFC87F11),
        );
      case DocentExperiencePhase.completed:
        return const Icon(
          Icons.check_circle_outline,
          size: 20,
          color: Color(0xFFC87F11),
        );
      case DocentExperiencePhase.unavailable:
        return const Icon(
          Icons.volume_off_outlined,
          size: 20,
          color: Color(0xFFC87F11),
        );
      case DocentExperiencePhase.failed:
        return const Icon(
          Icons.error_outline,
          size: 20,
          color: Color(0xFFC87F11),
        );
      case DocentExperiencePhase.idle:
        return const SizedBox.shrink();
    }
  }
}

/// 재생/일시정지/재시도 단일 토글 — 준비 중에는 비활성 스피너.
/// 재생 위치 이동(seek)은 DocentAudioPlayer 가 지원하지 않으므로 아예 제공하지 않는다.
class _DocentMiniControlButton extends StatelessWidget {
  const _DocentMiniControlButton({
    required this.phase,
    required this.language,
    required this.onPressed,
  });

  final DocentExperiencePhase phase;
  final String language;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    if (phase == DocentExperiencePhase.checkingReadiness ||
        phase == DocentExperiencePhase.preparingScript ||
        phase == DocentExperiencePhase.preparingAudio ||
        phase == DocentExperiencePhase.idle) {
      return const SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final isPlaying = phase == DocentExperiencePhase.playing;
    final isRetry =
        phase == DocentExperiencePhase.unavailable ||
        phase == DocentExperiencePhase.failed;
    final label = isRetry
        ? docentRetrySemanticLabel(language)
        : isPlaying
        ? docentPauseSemanticLabel(language)
        : docentPlaySemanticLabel(language);
    return SizedBox(
      width: 44,
      height: 44,
      child: Semantics(
        label: label,
        button: true,
        child: IconButton(
          onPressed: () => onPressed(),
          icon: Icon(
            isRetry
                ? Icons.refresh_rounded
                : isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            color: const Color(0xFFC87F11),
          ),
          padding: EdgeInsets.zero,
          tooltip: label,
        ),
      ),
    );
  }
}
