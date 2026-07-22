import 'package:flutter/material.dart';

/// 맛집 투어 태그 칩(C3 추출 — main.dart 의 _TourTag).
/// 투어 시트 상단에서 각 투어 후보 장소로 바로 이동하는 칩.
class TourTag extends StatelessWidget {
  const TourTag({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.restaurant_menu, size: 16),
      label: Text(label, overflow: TextOverflow.ellipsis),
      onPressed: onPressed,
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFF5C842)),
      labelStyle: const TextStyle(
        color: Color(0xFF744210),
        fontWeight: FontWeight.w900,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}
