import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/l10n/place_labels.dart';
import '../docent_helpers.dart';
import '../playback/docent_audio_player.dart';
import '../playback/docent_playback_controller.dart';

/// 상세 패널 도슨트 소제목/요약 카드(C3 추출 — main.dart 의 _DocentSubtitle).
class DocentSubtitle extends StatelessWidget {
  const DocentSubtitle({
    super.key,
    required this.place,
    required this.language,
    required this.script,
    required this.action,
    required this.audioLoading,
    required this.audioError,
    required this.docentAudio,
    required this.canFetchAudio,
    required this.onFetchAudio,
    this.onAddToPlan,
    this.playbackController,
  });

  final LalaPlace? place;
  final String language;
  final String? script;
  final String? action;
  final bool audioLoading;
  final String? audioError;
  final LalaAudioResponse? docentAudio;
  final bool canFetchAudio;
  final VoidCallback onFetchAudio;
  final VoidCallback? onAddToPlan;
  // V4-B: optional playback wiring. When null the widget renders exactly as
  // before (fetch-only); when provided it shows ▶/⏸ or an honest unavailable
  // line — see docs/planning/v4-rag-docent-speech-qa-contract.md §V4-B.
  final DocentPlaybackController? playbackController;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final body = docentBody(place: place, script: script, language: language);
    final summary = docentSummary(
      place: place,
      language: language,
      script: script,
      action: action,
    );
    final actionLabel = docentActionLabel(
      place: place,
      action: action,
      language: language,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(16),
            border: const Border(
              left: BorderSide(color: Color(0xFF2B6CB0), width: 4),
            ),
            boxShadow: const [
              BoxShadow(
                blurRadius: 24,
                offset: Offset(0, 8),
                color: Color(0x24121F2D),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.record_voice_over_outlined,
                      color: Color(0xFF2B6CB0),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place == null
                              ? lalaCopyMulti(
                                  language,
                                  ko: '로컬 도슨트',
                                  en: 'Local docent',
                                  ja: 'ローカルガイド',
                                  zhHans: '本地讲解',
                                  zhHant: '在地導覽',
                                )
                              : lalaCopyMulti(
                                  language,
                                  ko: '${placeDisplayName(place!, language)} 도슨트',
                                  en: '${placeDisplayName(place!, language)} docent',
                                  ja: '${placeDisplayName(place!, language)} ガイド',
                                  zhHans: '${placeDisplayName(place!, language)} 讲解',
                                  zhHant: '${placeDisplayName(place!, language)} 導覽',
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (docentAudio != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        audioBytesLabel(docentAudio!.bytes.length, language),
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  body,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              if (playbackController != null) ...[
                const SizedBox(height: 10),
                _DocentPlaybackRow(
                  controller: playbackController!,
                  language: language,
                ),
              ],
              if (actionLabel != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.route_outlined,
                      size: 15,
                      color: Color(0xFF2B6CB0),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        actionLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (audioError != null) ...[
                const SizedBox(height: 8),
                Text(
                  audioError!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.error,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (canFetchAudio || audioLoading) ...[
              Expanded(
                child: FilledButton.icon(
                  onPressed: canFetchAudio ? onFetchAudio : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: audioLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.volume_up),
                  label: Text(
                    audioLoading
                        ? lalaCopy(language, ko: '음성 생성 중', en: 'Preparing audio')
                        : lalaCopy(language, ko: '정보 더 듣기', en: 'Listen'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            if (onAddToPlan != null)
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add_circle_outline),
                  label: Text(lalaCopy(language, ko: '하루 일정 보기', en: 'View plan')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2B6CB0),
                    side: const BorderSide(color: Color(0xFF2B6CB0)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: onAddToPlan,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// V4-B playback row rendered from a [DocentPlaybackController]. Shows ▶/⏸ when
/// real bytes are available behind a live speech gate, else an honest
/// unavailable line. Reuses docent slate tokens already in this file (no new
/// color tokens). Tap targets are ≥44dp and every control carries a KO/EN
/// `Semantics` label; state changes announce via a live region.
class _DocentPlaybackRow extends StatelessWidget {
  const _DocentPlaybackRow({required this.controller, required this.language});

  final DocentPlaybackController controller;
  final String language;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DocentPlaybackState>(
      valueListenable: controller.state,
      builder: (context, state, _) {
        if (!controller.isAvailable) {
          // B2/B3: speech off OR no real bytes → honest unavailable, no control.
          return Semantics(
            liveRegion: true,
            label: lalaCopy(
              language,
              ko: '음성을 사용할 수 없어요',
              en: 'Voice guide unavailable',
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.volume_off_outlined,
                  size: 16,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lalaCopy(
                      language,
                      ko: '음성을 사용할 수 없어요',
                      en: 'Voice guide unavailable',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        final isPlaying = state == DocentPlaybackState.playing;
        final isPaused = state == DocentPlaybackState.paused;
        final isLoading = state == DocentPlaybackState.loading;
        final toggleLabel = isPlaying
            ? lalaCopy(language, ko: '일시정지', en: 'Pause')
            : lalaCopy(language, ko: '재생', en: 'Play');
        return Row(
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
                          color: const Color(0xFF2B6CB0),
                        ),
                  padding: EdgeInsets.zero,
                  tooltip: toggleLabel,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.scriptText ??
                        lalaCopyMulti(
                          language,
                          ko: '도슨트 음성',
                          en: 'Docent audio',
                          ja: 'ガイド音声',
                          zhHans: '讲解语音',
                          zhHant: '導覽語音',
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _docentStateCaption(state, language),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
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
                      color: Color(0xFF2B6CB0),
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

String _docentStateCaption(DocentPlaybackState state, String language) {
  return switch (state) {
    DocentPlaybackState.idle => lalaCopy(language, ko: '재생 가능', en: 'Ready'),
    DocentPlaybackState.loading => lalaCopy(
      language,
      ko: '불러오는 중',
      en: 'Loading',
    ),
    DocentPlaybackState.playing => lalaCopy(language, ko: '재생 중', en: 'Playing'),
    DocentPlaybackState.paused => lalaCopy(
      language,
      ko: '일시정지됨',
      en: 'Paused',
    ),
    DocentPlaybackState.done => lalaCopy(language, ko: '재생 완료', en: 'Finished'),
    DocentPlaybackState.error => lalaCopy(
      language,
      ko: '재생 오류',
      en: 'Playback error',
    ),
  };
}
