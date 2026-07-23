import 'package:flutter/material.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';

/// 자동 도슨트 토글 컨트롤.
// 모바일 비주얼 계약(00-ground-truth §6): 컨트롤 스택은 44dp 타겟. 대형 중앙 다크 컨트롤
// 없이 ON/OFF 가 색상+상태 텍스트로 구분되도록 44dp 타겟으로 축소.
class AutoDocentFab extends StatelessWidget {
  const AutoDocentFab({
    super.key,
    required this.tooltip,
    required this.label,
    required this.active,
    required this.statusLabel,
    required this.onPressed,
  });

  final String tooltip;
  final String label;
  final bool active;
  final String statusLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = active
        ? LalaVisualColors.primaryBlue
        : LalaVisualColors.ink.withValues(alpha: 0.84);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: label,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            // 44dp 최소 타겟. 74dp 대형 중앙 컨트롤을 쓰지 않는다.
            minimumSize: const Size.square(LalaVisualTokens.iconTarget),
            fixedSize: const Size.square(LalaVisualTokens.iconTarget),
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            backgroundColor: backgroundColor,
            foregroundColor: Colors.white,
            elevation: 6,
            shadowColor: const Color(0x33000000),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.auto_awesome, size: 16),
              const SizedBox(height: 2),
              Text(
                statusLabel,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
