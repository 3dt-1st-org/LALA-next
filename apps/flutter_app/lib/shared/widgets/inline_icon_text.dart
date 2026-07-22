import 'package:flutter/material.dart';

/// 공용 아이콘+텍스트 한 줄 위젯(C3 추출 — main.dart 의 _InlineIconText).
/// 여러 feature(place/docent 등)에서 메타 라인으로 사용한다.
class InlineIconText extends StatelessWidget {
  const InlineIconText({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: const Color(0xFF64748B)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
