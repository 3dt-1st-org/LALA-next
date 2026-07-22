import 'package:flutter/material.dart';

/// 수동 지역 선택 시트의 섹션 라벨(C3 추출 — main.dart 의 _ManualLocationSectionLabel).
class ManualLocationSectionLabel extends StatelessWidget {
  const ManualLocationSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF64748B),
        fontSize: 13,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}
