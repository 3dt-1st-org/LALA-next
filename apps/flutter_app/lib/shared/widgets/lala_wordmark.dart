// C3 최종: main.dart 에서 이관.
// 모바일 비주얼 계약(00-visual-ground-truth.md §2) Wordmark 역할: 18/22, 800.
// 로고 위젯 자체는 변경하지 않고 타입 수치만 계약 토큰으로 정렬한다.
import 'package:flutter/material.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';

class LalaWordmark extends StatelessWidget {
  const LalaWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'LALA',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              blurRadius: 12,
              offset: Offset(0, 4),
              color: Color(0x14000000),
            ),
          ],
        ),
        child: Text(
          'LALA',
          style: TextStyle(
            color: LalaVisualColors.primaryBlue,
            fontSize: LalaVisualTokens.wordmarkSize,
            height: LalaVisualTokens.wordmarkLineHeight /
                LalaVisualTokens.wordmarkSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
