import 'package:flutter/material.dart';

/// 자동 도슨트 트리거 FAB — 컴팩트 48px. 비활성은 흰색(대형 흑색 원형 ❌).
/// 반짝임 아이콘 + 작은 ON/OFF 상태.
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
        ? const Color(0xFF2B6CB0)
        : Colors.white;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: label,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            minimumSize: Size.zero,
            fixedSize: const Size.square(48),
            shape: const CircleBorder(
              side: BorderSide(color: Color(0xFFE2E8F0), width: 1.4),
            ),
            padding: EdgeInsets.zero,
            backgroundColor: backgroundColor,
            foregroundColor: active ? Colors.white : const Color(0xFF1A202C),
            elevation: 6,
            shadowColor: const Color(0x22000000),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.auto_awesome, size: 17),
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
