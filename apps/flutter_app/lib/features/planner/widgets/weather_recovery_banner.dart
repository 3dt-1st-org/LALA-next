import 'package:flutter/material.dart';

/// 날씨 recovery 배너(P6A §03 Screen 04).
///
/// 두 상태를 지원:
/// - **restored**: 앱 재실행 후 이전 일정이 복원됨. muted 톤.
/// - **swapped**: 날씨로 인해 슬롯이 교체됨. primaryBlue 액센트.
///
/// 제안 copy (design-owner 확인 후 조정 가능):
/// restored KO: "이전 일정을 복원했어요."
/// restored EN: "Restored your previous plan."
/// swapped KO: "날씨를 고려해 일정을 조정했어요."
/// swapped EN: "Adjusted your plan for the weather."
class WeatherRecoveryBanner extends StatelessWidget {
  const WeatherRecoveryBanner.restored({super.key, required this.language})
    : _mode = _WeatherRecoveryMode.restored,
      swapDetail = null;

  const WeatherRecoveryBanner.swapped({
    super.key,
    required this.language,
    this.swapDetail,
  }) : _mode = _WeatherRecoveryMode.swapped;

  final String language;
  final String? swapDetail;
  final _WeatherRecoveryMode _mode;

  @override
  Widget build(BuildContext context) {
    final isRestored = _mode == _WeatherRecoveryMode.restored;
    final accentColor = isRestored
        ? const Color(0xFF64748B)
        : const Color(0xFF2B6CB0);
    final bgColor = isRestored
        ? const Color(0xFFF1F5F9)
        : const Color(0xFFEBF4FE);
    final ko = language == 'ko';
    final title = isRestored
        ? (ko ? '이전 일정을 복원했어요.' : 'Restored your previous plan.')
        : (ko ? '날씨를 고려해 일정을 조정했어요.' : 'Adjusted your plan for the weather.');

    return Container(
      key: ValueKey('weather-recovery-${isRestored ? 'restored' : 'swapped'}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isRestored ? Icons.history : Icons.cloud_outlined,
            size: 16,
            color: accentColor,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (swapDetail != null && swapDetail!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    swapDetail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF475569),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _WeatherRecoveryMode { restored, swapped }
