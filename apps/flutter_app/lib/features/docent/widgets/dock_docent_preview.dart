import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/l10n/place_labels.dart';
import '../../../shared/widgets/inline_icon_text.dart';
import '../docent_helpers.dart';

/// 독 하단 도슨트 미리보기(C3 추출 — main.dart 의 _DockDocentPreview).
class DockDocentPreview extends StatelessWidget {
  const DockDocentPreview({
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
    required this.onAddToPlan,
    required this.onOpenDetail,
  });

  final LalaPlace place;
  final String language;
  final String? script;
  final String? action;
  final bool audioLoading;
  final String? audioError;
  final LalaAudioResponse? docentAudio;
  final bool canFetchAudio;
  final VoidCallback onFetchAudio;
  final VoidCallback onAddToPlan;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
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
    final showListenButton = canFetchAudio || audioLoading;
    return DecoratedBox(
      key: const ValueKey('dock-docent-preview'),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.record_voice_over_outlined,
                    color: Color(0xFF2B6CB0),
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lalaCopy(
                          language,
                          ko: '${placeDisplayName(place, language)} 도슨트',
                          en: '${placeDisplayName(place, language)} docent',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
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
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (docentAudio != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
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
            const SizedBox(height: 8),
            Text(
              body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111827),
                height: 1.38,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 6),
              InlineIconText(icon: Icons.route_outlined, label: actionLabel),
            ],
            if (audioError != null) ...[
              const SizedBox(height: 6),
              Text(
                audioError!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (showListenButton) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: canFetchAudio ? onFetchAudio : null,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      icon: audioLoading
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.volume_up, size: 18),
                      label: Text(
                        audioLoading
                            ? lalaCopy(language, ko: '음성 생성 중', en: 'Preparing')
                            : lalaCopy(language, ko: '정보 더 듣기', en: 'Listen'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onAddToPlan,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: Text(
                      lalaCopy(language, ko: '하루 일정 보기', en: 'View plan'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2B6CB0),
                      side: const BorderSide(color: Color(0xFF2B6CB0)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton.filledTonal(
                    tooltip: lalaCopy(language, ko: '상세 열기', en: 'Open details'),
                    onPressed: onOpenDetail,
                    icon: const Icon(Icons.keyboard_arrow_up),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF2B6CB0),
                      side: const BorderSide(color: Color(0xFFD7E3F5)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
