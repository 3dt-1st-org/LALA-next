import 'package:flutter/material.dart';

/// 공용 한 줄 메타 텍스트(C3 추출 — main.dart 의 _InlineMeta).
class InlineMeta extends StatelessWidget {
  const InlineMeta(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: const Color(0xFF64748B),
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
