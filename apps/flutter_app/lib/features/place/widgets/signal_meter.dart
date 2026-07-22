import 'package:flutter/material.dart';

/// 신호 지표 미터(C3 추출 — main.dart 의 _SignalMeter).
class SignalMeter extends StatelessWidget {
  const SignalMeter({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bounded = value.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF1A202C),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            bounded.toStringAsFixed(2),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF475569),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: bounded,
              minHeight: 7,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
