import 'package:flutter/material.dart';

/// 지도 상단 카테고리 필터 칩.
// 모바일 비주얼 계약 remediation C1: 360..430dp 에서 5개 칩 + 44dp 설정 아이콘이
// 모두 잘림 없이 보이도록 컴팩트 고정 폭으로 한다(초기 스크롤 위치에 의존하지 않는다).
class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: active ? color : Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 12,
                  offset: Offset(0, 4),
                  color: Color(0x12000000),
                ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                color: active
                    ? (color == const Color(0xFFF5C842)
                          ? const Color(0xFF1A202C)
                          : Colors.white)
                    : const Color(0xFF0F172A),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
