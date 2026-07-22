import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/l10n/place_labels.dart';
import '../docent_helpers.dart';

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
                              ? lalaCopy(
                                  language,
                                  ko: '로컬 도슨트',
                                  en: 'Local docent',
                                )
                              : lalaCopy(
                                  language,
                                  ko: '${placeDisplayName(place!, language)} 도슨트',
                                  en: '${placeDisplayName(place!, language)} docent',
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
