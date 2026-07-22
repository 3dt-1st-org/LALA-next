import 'package:flutter/material.dart';

/// 지도 라운드 버튼(설정 진입 등)(C3 추출 — main.dart 의 _MapRoundButton).
class MapRoundButton extends StatelessWidget {
  const MapRoundButton({
    super.key,
    this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final Key? buttonKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Listener(
          key: buttonKey,
          behavior: HitTestBehavior.opaque,
          onPointerUp: (_) => onPressed(),
          child: Material(
            color: Colors.white.withValues(alpha: 0.95),
            elevation: 7,
            shadowColor: const Color(0x22000000),
            shape: const CircleBorder(
              side: BorderSide(color: Color(0xFFE2E8F0), width: 1.4),
            ),
            child: SizedBox.square(
              dimension: 46,
              child: Icon(icon, size: 22, color: const Color(0xFF1A202C)),
            ),
          ),
        ),
      ),
    );
  }
}
