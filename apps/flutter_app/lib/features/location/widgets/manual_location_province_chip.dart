import 'package:flutter/material.dart';

import '../../../app/lala_visual_tokens.dart';

/// 수동 지역 선택 시트의 시/도 필터 칩(C3 추출 — main.dart 의 _ManualLocationProvinceChip).
class ManualLocationProvinceChip extends StatelessWidget {
  const ManualLocationProvinceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : LalaVisualColors.ink,
          fontWeight: FontWeight.w900,
        ),
      ),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onSelected(),
      selectedColor: LalaVisualColors.primaryBlue,
      backgroundColor: LalaVisualColors.card,
      side: BorderSide(
        color: selected ? LalaVisualColors.primaryBlue : LalaVisualColors.line,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
