import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';

/// 하단 독 빈 상태(추천 준비 중 / 에러 재시도)(C3 추출 — main.dart 의 _EmptyDockContent).
class EmptyDockContent extends StatelessWidget {
  const EmptyDockContent({
    super.key,
    required this.language,
    this.errorLabel,
    this.recoveryPending = false,
    this.onRetry,
  });

  final String language;
  final String? errorLabel;
  final bool recoveryPending;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final hasError = errorLabel != null && errorLabel!.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: hasError ? const Color(0xFFFFF3E8) : const Color(0xFFEAF2FF),
            shape: BoxShape.circle,
          ),
          child: Icon(
            hasError ? Icons.refresh_outlined : Icons.travel_explore,
            color: hasError ? const Color(0xFFB45309) : const Color(0xFF2B6CB0),
            size: 21,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasError
                    ? lalaCopy(
                        language,
                        ko: '추천 연결을 다시 확인하고 있어요',
                        en: 'Checking recommendations again',
                      )
                    : lalaCopy(
                        language,
                        ko: '추천을 준비 중입니다',
                        en: 'Preparing recommendations',
                      ),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF111827),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                hasError
                    ? lalaCopy(
                        language,
                        ko: recoveryPending
                            ? '잠시 후 자동으로 다시 시도합니다. 지금 바로 다시 시도할 수도 있어요.'
                            : '잠시 후 다시 시도해 주세요. 필요하면 지금 바로 다시 시도할 수 있어요.',
                        en: recoveryPending
                            ? 'Retrying automatically soon. You can also retry right now.'
                            : 'Please try again shortly. You can also retry right now.',
                      )
                    : lalaCopy(
                        language,
                        ko: '공식 데이터가 확인된 장소만 표시합니다.',
                        en: 'Only places backed by official data are shown.',
                      ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (hasError && onRetry != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('dock-error-retry'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(
                      lalaCopy(language, ko: '지금 다시 시도', en: 'Retry now'),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
