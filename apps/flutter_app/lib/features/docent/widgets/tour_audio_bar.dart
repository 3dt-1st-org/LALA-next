import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../playback/docent_audio_player.dart';
import '../playback/docent_playback_controller.dart';

/// 투어 도슨트 오디오 바(C3 추출 — main.dart 의 _TourAudioBar).
class TourAudioBar extends StatelessWidget {
  const TourAudioBar({
    super.key,
    required this.language,
    required this.audio,
    required this.loading,
    required this.error,
    required this.onFetchAudio,
    this.playbackController,
  });

  final String language;
  final LalaAudioResponse? audio;
  final bool loading;
  final String? error;
  final VoidCallback onFetchAudio;
  // V4-B: optional playback wiring. When null the bar renders exactly as before
  // (fetch-only); when provided it surfaces ▶/⏸ when real bytes exist behind a
  // live speech gate, else an honest unavailable line — see
  // docs/planning/v4-rag-docent-speech-qa-contract.md §V4-B.
  final DocentPlaybackController? playbackController;

  @override
  Widget build(BuildContext context) {
    final hasAudio = audio != null;
    // V4-B: when a controller is wired it owns the honest-unavailable +
    // play/pause decision. When null, the bar renders exactly as before.
    final controller = playbackController;
    final wired = controller != null;
    final speechOff = wired && !controller.liveSpeechEnabled;
    final canPlay = wired && controller.isAvailable;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF5C842)),
      ),
      child: Row(
        children: [
          Icon(
            canPlay
                ? Icons.graphic_eq
                : speechOff
                ? Icons.volume_off_outlined
                : (hasAudio
                      ? Icons.graphic_eq
                      : Icons.volume_up_outlined),
            color: const Color(0xFFC87F11),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  speechOff
                      ? lalaCopy(
                          language,
                          ko: '음성을 사용할 수 없어요',
                          en: 'Voice guide unavailable',
                        )
                      : hasAudio
                      ? lalaCopy(language, ko: '투어 음성 준비됨', en: 'Tour audio ready')
                      : lalaCopy(
                          language,
                          ko: '도슨트 음성으로 듣기',
                          en: 'Listen as a docent audio guide',
                        ),
                  style: const TextStyle(
                    color: Color(0xFF744210),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (speechOff) ...[
                  const SizedBox(height: 3),
                  Text(
                    lalaCopy(
                      language,
                      ko: '음성을 사용할 수 없어요',
                      en: 'Voice guide unavailable',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ] else if (error != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ] else if (hasAudio) ...[
                  const SizedBox(height: 3),
                  Text(
                    lalaCopy(
                      language,
                      ko: '오디오 캐시 ${audio!.bytes.length}바이트',
                      en: '${audio!.bytes.length} bytes cached',
                    ),
                    style: const TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (canPlay)
            _TourPlaybackToggle(controller: controller, language: language)
          else if (!speechOff)
            FilledButton.icon(
              onPressed: loading ? null : onFetchAudio,
              icon: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(hasAudio ? Icons.replay : Icons.play_arrow),
              label: Text(
                loading
                    ? lalaCopy(language, ko: '변환 중', en: 'Converting')
                    : hasAudio
                    ? lalaCopy(language, ko: '다시 준비', en: 'Prepare again')
                    : lalaCopy(language, ko: '오디오 준비', en: 'Prepare audio'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC87F11),
                foregroundColor: Colors.white,
              ),
            ),
          // speechOff → no control rendered (B2: no fetch when speech off).
        ],
      ),
    );
  }
}

/// V4-B ▶/⏸ toggle for the tour audio bar. Tap target ≥44dp, KO/EN Semantics
/// label, live-region state caption. Reuses tour amber tokens already in this
/// file (no new color tokens).
class _TourPlaybackToggle extends StatelessWidget {
  const _TourPlaybackToggle({required this.controller, required this.language});

  final DocentPlaybackController controller;
  final String language;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DocentPlaybackState>(
      valueListenable: controller.state,
      builder: (context, state, _) {
        final isPlaying = state == DocentPlaybackState.playing;
        final isPaused = state == DocentPlaybackState.paused;
        final isLoading = state == DocentPlaybackState.loading;
        final toggleLabel = isPlaying
            ? lalaCopy(language, ko: '일시정지', en: 'Pause')
            : lalaCopy(language, ko: '재생', en: 'Play');
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Semantics(
                label: toggleLabel,
                button: true,
                child: IconButton(
                  onPressed: controller.togglePlay,
                  icon: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: const Color(0xFFC87F11),
                        ),
                  padding: EdgeInsets.zero,
                  tooltip: toggleLabel,
                ),
              ),
            ),
            if (isPlaying || isPaused)
              SizedBox(
                width: 44,
                height: 44,
                child: Semantics(
                  label: lalaCopy(language, ko: '정지', en: 'Stop'),
                  button: true,
                  child: IconButton(
                    onPressed: controller.stop,
                    icon: const Icon(
                      Icons.stop_rounded,
                      color: Color(0xFFC87F11),
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: lalaCopy(language, ko: '정지', en: 'Stop'),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
