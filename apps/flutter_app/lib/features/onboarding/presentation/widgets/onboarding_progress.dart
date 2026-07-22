// ONMU P2: 온보딩 4단계 진행 표시(현재 단계 dot/bar).
// 모바일 터치 타겟과 ColorScheme 톤을 준수한다.
import 'package:flutter/material.dart';

/// 4단계 중 [step] 번째를 강조하는 진행 표시 바. [step] 은 1..4.
class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({required this.step, super.key});

  final int step;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$step / 4',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: List<Widget>.generate(4, (index) {
            final active = index < step;
            final isCurrent = index == step - 1;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 4,
                  decoration: BoxDecoration(
                    color: active
                        ? colorScheme.primary
                        : colorScheme.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: isCurrent
                        ? Border.all(
                            color: colorScheme.primary,
                            width: 1,
                          )
                        : null,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
