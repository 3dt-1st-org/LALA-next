import 'package:flutter/material.dart';

/// 공공데이터 근거 칩(C3 추출 — main.dart 의 _ProofChip).
class ProofChip extends StatelessWidget {
  const ProofChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.check_circle, size: 17),
      label: Text(label),
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFD7E3F5)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w800),
    );
  }
}
