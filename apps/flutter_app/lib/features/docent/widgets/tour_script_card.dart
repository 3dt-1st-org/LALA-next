import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/widgets/tiny_meta.dart';

/// 투어 도슨트 스크립트 카드(C3 추출 — main.dart 의 _TourScriptCard).
class TourScriptCard extends StatelessWidget {
  const TourScriptCard({
    super.key,
    required this.script,
    required this.sourceLabel,
    required this.language,
  });

  final String script;
  final String sourceLabel;
  final String language;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 16,
            offset: Offset(0, 7),
            color: Color(0x10000000),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.record_voice_over_outlined,
                size: 19,
                color: Color(0xFFC87F11),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  lalaCopy(language, ko: '투어 도슨트 스크립트', en: 'Tour docent script'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TinyMeta(sourceLabel),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            script,
            style: const TextStyle(
              color: Color(0xFF1A202C),
              fontWeight: FontWeight.w600,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
