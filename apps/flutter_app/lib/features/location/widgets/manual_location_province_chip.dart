import 'package:flutter/material.dart';

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
          color: selected ? Colors.white : const Color(0xFF111827),
          fontWeight: FontWeight.w900,
        ),
      ),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onSelected(),
      selectedColor: const Color(0xFF111827),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: selected ? const Color(0xFF111827) : const Color(0xFFE2E8F0),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
