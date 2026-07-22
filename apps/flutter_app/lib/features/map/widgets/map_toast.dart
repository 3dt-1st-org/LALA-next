import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 지도 상단 토스트(에러/위치 안내)(C3 추출 — main.dart 의 _MapToast).
class MapToast extends StatelessWidget {
  const MapToast({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.actionKey = const ValueKey('map-error-retry'),
    this.secondaryActionKey = const ValueKey('map-secondary-action'),
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Key actionKey;
  final Key secondaryActionKey;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onErrorContainer;
    final accent = Theme.of(context).colorScheme.error;
    final actions = <Widget>[
      if (actionLabel != null && onAction != null)
        TextButton(
          key: actionKey,
          onPressed: onAction,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: accent,
            backgroundColor: color.withValues(alpha: 0.42),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          child: Text(actionLabel!),
        ),
      if (secondaryActionLabel != null && onSecondaryAction != null)
        TextButton(
          key: secondaryActionKey,
          onPressed: onSecondaryAction,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: const Color(0xFF2B6CB0),
            backgroundColor: const Color(0xFFE6F0FB),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          child: Text(secondaryActionLabel!),
        ),
    ];

    Widget message() {
      return Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );
    }

    Widget actionWrap() {
      return Wrap(spacing: 4, runSpacing: 4, children: actions);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = math.max(
          0.0,
          MediaQuery.sizeOf(context).width - 32,
        );
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth;
        final toastWidth = math.min(520.0, availableWidth);
        final compact = actions.length > 1 && toastWidth < 440;
        return SizedBox(
          width: toastWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(compact ? 18 : 999),
              border: Border.all(color: color.withValues(alpha: 0.78)),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 14,
                  offset: Offset(0, 5),
                  color: Color(0x16000000),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: compact
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        message(),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: actionWrap(),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: message()),
                        if (actions.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          actionWrap(),
                        ],
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}
