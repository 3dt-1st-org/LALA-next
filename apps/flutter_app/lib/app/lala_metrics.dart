import 'package:flutter/material.dart';

/// LALA 레이아웃/타이포 측정값 SSOT — image-to-code 리디자인 토큰.
/// 카드/시트/터치타겟 반경과 타이포 목표 sp 값을 한 곳에 둬서
/// 온보딩·지도·검색·일정·하단탭이 동일한 스케일을 공유한다.
class LalaMetrics {
  LalaMetrics._();

  /// 카드 반경(참조: 8px). CardTheme 과 동일.
  static const double cardRadius = 8;

  /// 바텀시트 상단 반경(참조: 20px).
  static const double sheetTopRadius = 20;

  /// 선택 행(온보딩 등) 반경.
  static const double choiceRowRadius = 8;

  /// 최소 터치 타겟(접근성, 44px).
  static const double minTouchTarget = 44;

  /// 컴팩트 컨트롤(지도 FAB) 한 변.
  static const double mapControlSize = 44;

  /// 페이지 타이틀 sp(참조: 30~32, 제한적).
  static const double pageTitleSp = 30;

  /// 본문 sp(참조: 15~17).
  static const double bodySp = 16;

  /// 칩/라벨 sp(참조: 13~14).
  static const double chipSp = 13;

  /// 하단탭 라벨 sp(참조: 12~13).
  static const double navLabelSp = 12;
}

/// 접근성 대비를 보장하는 텍스트 색 선택: 노란 계열 배경 위는 어둡게.
Color contrastOnCategory(Color background) {
  // restaurant 노란(#F5C842)은 밝아서 어두운 텍스트를 써야 대비가 확보된다.
  if (background == const Color(0xFFF5C842)) {
    return const Color(0xFF1A202C);
  }
  return Colors.white;
}
