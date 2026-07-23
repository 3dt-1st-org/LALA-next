import 'package:flutter/material.dart';

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MapFab(
          key: const ValueKey('voice-toggle'),
          tooltip: language == 'en'
              ? (voiceEnabled ? 'Mute voice' : 'Enable voice')
              : (voiceEnabled ? '음성 끄기' : '음성 켜기'),
          icon: voiceEnabled ? Icons.volume_up : Icons.volume_off,
          label: language == 'en'
              ? (voiceEnabled ? 'Voice on' : 'Voice off')
              : (voiceEnabled ? '음성 켜짐' : '음성 꺼짐'),
          active: voiceEnabled,
          statusLabel: language == 'en'
              ? (voiceEnabled ? 'ON' : 'OFF')
              : (voiceEnabled ? '켬' : '끔'),
          onPressed: onToggleVoice,
        ),
        const SizedBox(height: 8),
        AutoDocentFab(
          key: const ValueKey('auto-docent-toggle'),
          tooltip: language == 'en'
              ? (autoDocentEnabled ? 'Auto guide off' : 'Auto guide on')
              : (autoDocentEnabled ? '자동 도슨트 끄기' : '자동 도슨트 켜기'),
          label: language == 'en'
              ? (autoDocentEnabled ? 'Auto on' : 'Auto off')
              : (autoDocentEnabled ? '자동 켜짐' : '자동 꺼짐'),
          active: autoDocentEnabled,
          statusLabel: language == 'en'
              ? (autoDocentEnabled ? 'ON' : 'OFF')
              : (autoDocentEnabled ? '켬' : '끔'),
          onPressed: onToggleAutoDocent,
        ),
        const SizedBox(height: 8),
        MapFab(
          key: const ValueKey('location-refresh'),
          tooltip: language == 'en' ? 'My location' : '내 위치',
          icon: Icons.my_location,
          label: language == 'en' ? 'My location' : '내 위치',
          active: true,
          statusLabel: null,
          onPressed: onReturnToLocation,
        ),
      ],
    );
  }
}
