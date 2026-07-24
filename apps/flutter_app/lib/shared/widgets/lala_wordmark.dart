// 모바일 비주얼 계약(00-visual-ground-truth §2 / remediation F): 워드마크는
// 소스 이미지처럼 컴팩트한 plain 텍스트. floating 흰 알약/그림자/컨테이너를 뺀다.
import 'package:flutter/material.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';

class LalaWordmark extends StatelessWidget {
  const LalaWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'LALA',
      child: Text(
        'LALA',
        style: TextStyle(
          color: LalaVisualColors.primaryBlue,
          fontSize: LalaVisualTokens.wordmarkSize,
          height:
              LalaVisualTokens.wordmarkLineHeight /
              LalaVisualTokens.wordmarkSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
