import 'package:flutter/material.dart';

/// 작은 메타 라벨 칩(C3 추출 — main.dart 의 _TinyMeta).
/// Place/Docent 등 여러 feature 에서 공용으로 사용한다.
class TinyMeta extends StatelessWidget {
  const TinyMeta(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
