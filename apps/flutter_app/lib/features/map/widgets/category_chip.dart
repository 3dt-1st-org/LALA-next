import 'package:flutter/material.dart';

import '../../../app/lala_visual_tokens.dart';

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
    this.width,
  });

  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        // P6F §13.5: screen-reader label + selected state as a non-color cue
        // (활성 상태가 색으로만 전달되지 않도록 Semantics.selected 사용).
        child: Tooltip(
          message: label,
          child: Semantics(
            button: true,
            label: label,
            selected: active,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onTap,
              child: Container(
                width: width,
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 7),
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
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        color: active
                            ? (color == LalaVisualColors.restaurant
                                  ? LalaVisualColors.restaurantInk
                                  : Colors.white)
                            : const Color(0xFF0F172A),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
