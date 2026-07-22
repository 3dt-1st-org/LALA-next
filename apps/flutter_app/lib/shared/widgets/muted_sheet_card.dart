import 'package:flutter/material.dart';

/// 공용 둥탁 시트 카드(C3 추출 — main.dart 의 _MutedSheetCard).
/// 여러 시트(Place/Planner/Tour/Docent 등)에서 빈 상태/안내 카드로 사용한다.
class MutedSheetCard extends StatelessWidget {
  const MutedSheetCard({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF64748B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
