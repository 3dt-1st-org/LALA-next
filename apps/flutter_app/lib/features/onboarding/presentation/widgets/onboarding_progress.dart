// 온보딩 콘텐츠 진행 표시(1/3 ~ 3/3). 스플래시는 콘텐츠 단계에서 제외된다.
import 'package:flutter/material.dart';

/// [total] 단계 중 [step] 번째를 강조하는 진행 바(기본 3 콘텐츠 단계).
class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({required this.step, this.total = 3, super.key})
      : assert(step >= 1 && step <= total),
      assert(total >= 1);

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$step / $total',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: List<Widget>.generate(total, (index) {
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
