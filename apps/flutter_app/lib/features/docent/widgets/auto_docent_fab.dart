import 'package:flutter/material.dart';

/// 자동 도슨트 트리거 FAB(C3 추출 — main.dart 의 _AutoDocentFab).
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
        : const Color(0xFF1A202C).withValues(alpha: 0.84);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: label,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            fixedSize: const Size.square(74),
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            backgroundColor: backgroundColor,
            foregroundColor: Colors.white,
            elevation: 9,
            shadowColor: const Color(0x33000000),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome, size: 19),
              const SizedBox(height: 3),
              Text(
                statusLabel,
                style: const TextStyle(
                  fontSize: 11,
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
