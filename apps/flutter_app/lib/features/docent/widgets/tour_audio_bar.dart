import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';

/// 투어 도슨트 오디오 바(C3 추출 — main.dart 의 _TourAudioBar).
class TourAudioBar extends StatelessWidget {
  const TourAudioBar({
    super.key,
    required this.language,
    required this.audio,
    required this.loading,
    required this.error,
    required this.onFetchAudio,
  });

  final String language;
  final LalaAudioResponse? audio;
  final bool loading;
  final String? error;
  final VoidCallback onFetchAudio;

  @override
  Widget build(BuildContext context) {
    final hasAudio = audio != null;
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
            hasAudio ? Icons.graphic_eq : Icons.volume_up_outlined,
            color: const Color(0xFFC87F11),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasAudio
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
                if (error != null) ...[
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
        ],
      ),
    );
  }
}
