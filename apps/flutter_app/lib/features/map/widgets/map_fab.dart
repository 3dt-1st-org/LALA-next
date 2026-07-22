import 'package:flutter/material.dart';

/// 지도 플로팅 액션 버튼(음성/내 위치 등)(C3 추출 — main.dart 의 _MapFab).
class MapFab extends StatelessWidget {
  const MapFab({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.active,
    required this.statusLabel,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final bool active;
  final String? statusLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: label,
        child: Badge(
          isLabelVisible: statusLabel != null,
          alignment: Alignment.topRight,
          backgroundColor: active
              ? const Color(0xFFF5C842)
              : const Color(0xFF64748B),
          textColor: active ? const Color(0xFF1A202C) : Colors.white,
          label: statusLabel == null
              ? null
              : Text(
                  statusLabel!,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
          child: IconButton.filled(
            onPressed: onPressed,
            icon: Icon(icon, size: 22),
            style: IconButton.styleFrom(
              fixedSize: const Size.square(46),
              backgroundColor: active
                  ? const Color(0xFF2B6CB0)
                  : const Color(0xFF1A202C).withValues(alpha: 0.82),
              foregroundColor: Colors.white,
              shape: CircleBorder(
                side: BorderSide(
                  color: active
                      ? Colors.white.withValues(alpha: 0.86)
                      : Colors.white.withValues(alpha: 0.22),
                  width: 1.6,
                ),
              ),
              elevation: 8,
            ),
          ),
        ),
      ),
    );
  }
}
