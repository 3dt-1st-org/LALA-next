import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';

/// 날씨 개입(intervention) 알림 토스트.
///
/// presentational 위젯 — 표시할 [label] 은 호출부(_Dashboard)에서
/// `_interventionToastLabel(intervention, language)` 로 계산해 전달한다.
/// (라벨 계산의 helper 체인은 후속 feature 추출 시 함께 이동.)
class InterventionToast extends StatelessWidget {
  const InterventionToast({
    super.key,
    required this.label,
    required this.language,
    required this.onOpenPlanner,
    required this.onDismiss,
  });

  final String label;
  final String language;
  final VoidCallback onOpenPlanner;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                blurRadius: 18,
                offset: Offset(0, 8),
                color: Color(0x30000000),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.tips_and_updates_outlined,
                color: Color(0xFFF5C842),
                size: 19,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    height: 1.22,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('intervention-toast-plan'),
                onPressed: onOpenPlanner,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: const Color(0xFFF5C842),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
                child: Text(lalaCopy(language, ko: '일정 보기', en: 'Plan')),
              ),
              IconButton(
                key: const ValueKey('intervention-toast-close'),
                tooltip: lalaCopy(language, ko: '닫기', en: 'Close'),
                onPressed: onDismiss,
                icon: const Icon(Icons.close, size: 16),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(32, 32),
                  foregroundColor: const Color(0xFFCBD5E1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
