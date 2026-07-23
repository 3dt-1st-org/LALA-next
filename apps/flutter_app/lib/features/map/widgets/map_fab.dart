import 'package:flutter/material.dart';

import '../../../app/lala_metrics.dart';

/// 지도 플로팅 액션 버튼(음성/내 위치 등) — 컴팩트 44px, 비활성은 흰색(흑색 ❌).
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
              : const Color(0xFF94A3B8),
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
            icon: Icon(icon, size: 20),
            style: IconButton.styleFrom(
              fixedSize: const Size.square(LalaMetrics.mapControlSize),
              backgroundColor: active
                  ? const Color(0xFF2B6CB0)
                  : Colors.white,
              foregroundColor: active
                  ? Colors.white
                  : const Color(0xFF1A202C),
              shape: CircleBorder(
                side: BorderSide(
                  color: active
                      ? const Color(0xFF2B6CB0)
                      : const Color(0xFFE2E8F0),
                  width: 1.4,
                ),
              ),
              elevation: 6,
            ),
          ),
        ),
      ),
    );
  }
}
