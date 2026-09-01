// 이슈 #120 §6/§7: 지도 레일/검색 타일/일정 슬롯 공용 도슨트 재생 진입 버튼.
// 히트 타겟은 항상 44dp(§13.5), 시각 원 지름만 [visual] 로 줄인다 — 좁은 카드에서
// 시각 크기를 줄여도 터치 타겟은 줄이지 않는다.
// 카드/타일 전체 탭(선택·내비게이션)과 분리된 독립 제스처 영역이어야 한다 —
// 중첩 제스처에서는 안쪽이 이기므로, 이 버튼의 탭이 부모 InkWell 로 새어
// 선택/내비게이션을 유발하지 않는다.
import 'package:flutter/material.dart';

import '../experience/docent_experience_copy.dart';

class DocentPlayButton extends StatelessWidget {
  const DocentPlayButton({
    required this.language,
    this.onPressed,
    this.visual = 36,
    super.key,
  });

  final String language;
  final VoidCallback? onPressed;

  /// 시각 원 지름(≤44). 히트 타겟은 항상 44dp.
  final double visual;

  @override
  Widget build(BuildContext context) {
    final visualSize = visual > 44 ? 44.0 : visual;
    return SizedBox(
      width: 44,
      height: 44,
      child: Semantics(
        label: docentPlaySemanticLabel(language),
        button: true,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Center(
            child: Container(
              width: visualSize,
              height: visualSize,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF5C842), width: 1.5),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                size: 26,
                color: Color(0xFFC87F11),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
