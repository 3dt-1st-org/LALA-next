import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';

/// 수동 지역 선택 시트의 빈 상태 안내(C3 추출 — main.dart 의 _ManualLocationEmptyState).
class ManualLocationEmptyState extends StatelessWidget {
  const ManualLocationEmptyState({super.key, required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_off, color: Color(0xFF64748B), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              lalaCopy(language, ko: '검색 결과가 없습니다', en: 'No matching area found'),
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
