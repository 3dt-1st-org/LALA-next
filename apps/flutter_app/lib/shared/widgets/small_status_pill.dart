import 'package:flutter/material.dart';

/// 작은 상태 필 버튼(C3 추출 — main.dart 의 _SmallStatusPill).
/// Planner/Tour/Weather MapPill 등 여러 feature 에서 공용으로 사용한다.
class SmallStatusPill extends StatelessWidget {
  const SmallStatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
    this.maxWidth = 150,
    this.maxLines = 1,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPressed;
  final double maxWidth;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withValues(alpha: 0.98)
                  : Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 12,
                  offset: Offset(0, 4),
                  color: Color(0x12000000),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: active
                      ? const Color(0xFF2B6CB0)
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
