import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';

import '../../docent/widgets/auto_docent_fab.dart';
import 'map_fab.dart';

/// 지도 플로팅 컨트롤 행(음성 토글 + 자동 도슨트 + 내 위치)(C3 추출 — main.dart 의 _FloatingMapControls).
class FloatingMapControls extends StatelessWidget {
  const FloatingMapControls({
    super.key,
    required this.voiceEnabled,
    required this.autoDocentEnabled,
    required this.language,
    required this.onToggleVoice,
    required this.onToggleAutoDocent,
    required this.onReturnToLocation,
  });

  final bool voiceEnabled;
  final bool autoDocentEnabled;
  final String language;
  final VoidCallback onToggleVoice;
  final VoidCallback onToggleAutoDocent;
  final VoidCallback onReturnToLocation;

  @override
  Widget build(BuildContext context) {
    // 모바일 비주얼 계약(00-ground-truth §6): 컨트롤 스택은 우측 세로 44dp 타겟, 8dp 간격.
    // V6: ko 이외 로케일은 현지화 라벨(ON/OFF 상태문은 라틴 약자 유지).
    final isKo = normalizeLalaLanguage(language) == 'ko';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MapFab(
          key: const ValueKey('voice-toggle'),
          tooltip: isKo
              ? (voiceEnabled ? '음성 끄기' : '음성 켜기')
              : lalaCopyMulti(
                  language,
                  ko: '음성',
                  en: voiceEnabled ? 'Mute voice' : 'Enable voice',
                  ja: voiceEnabled ? '音声をオフ' : '音声をオン',
                  zhHans: voiceEnabled ? '关闭语音' : '开启语音',
                  zhHant: voiceEnabled ? '關閉語音' : '開啟語音',
                ),
          icon: voiceEnabled ? Icons.volume_up : Icons.volume_off,
          label: isKo
              ? (voiceEnabled ? '음성 켜짐' : '음성 꺼짐')
              : lalaCopyMulti(
                  language,
                  ko: '음성',
                  en: voiceEnabled ? 'Voice on' : 'Voice off',
                  ja: voiceEnabled ? '音声オン' : '音声オフ',
                  zhHans: voiceEnabled ? '语音开' : '语音关',
                  zhHant: voiceEnabled ? '語音開' : '語音關',
                ),
          active: voiceEnabled,
          statusLabel: isKo ? (voiceEnabled ? '켬' : '끔') : (voiceEnabled ? 'ON' : 'OFF'),
          onPressed: onToggleVoice,
        ),
        const SizedBox(height: 8),
        AutoDocentFab(
          key: const ValueKey('auto-docent-toggle'),
          tooltip: isKo
              ? (autoDocentEnabled ? '자동 도슨트 끄기' : '자동 도슨트 켜기')
              : lalaCopyMulti(
                  language,
                  ko: '자동 도슨트',
                  en: autoDocentEnabled ? 'Auto guide off' : 'Auto guide on',
                  ja: autoDocentEnabled ? '自動ガイドをオフ' : '自動ガイドをオン',
                  zhHans: autoDocentEnabled ? '关闭自动讲解' : '开启自动讲解',
                  zhHant: autoDocentEnabled ? '關閉自動講解' : '開啟自動講解',
                ),
          label: isKo
              ? (autoDocentEnabled ? '자동 켜짐' : '자동 꺼짐')
              : lalaCopyMulti(
                  language,
                  ko: '자동',
                  en: autoDocentEnabled ? 'Auto on' : 'Auto off',
                  ja: autoDocentEnabled ? '自動オン' : '自動オフ',
                  zhHans: autoDocentEnabled ? '自动开' : '自动关',
                  zhHant: autoDocentEnabled ? '自動開' : '自動關',
                ),
          active: autoDocentEnabled,
          statusLabel: isKo
              ? (autoDocentEnabled ? '켬' : '끔')
              : (autoDocentEnabled ? 'ON' : 'OFF'),
          onPressed: onToggleAutoDocent,
        ),
        const SizedBox(height: 8),
        MapFab(
          key: const ValueKey('location-refresh'),
          tooltip: lalaCopyMulti(
            language,
            ko: '내 위치',
            en: 'My location',
            ja: '現在地',
            zhHans: '我的位置',
            zhHant: '我的位置',
          ),
          icon: Icons.my_location,
          label: lalaCopyMulti(
            language,
            ko: '내 위치',
            en: 'My location',
            ja: '現在地',
            zhHans: '我的位置',
            zhHant: '我的位置',
          ),
          active: true,
          statusLabel: null,
          onPressed: onReturnToLocation,
        ),
      ],
    );
  }
}
