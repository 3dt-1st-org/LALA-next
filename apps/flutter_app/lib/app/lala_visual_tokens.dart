// LALA 모바일 비주얼 계약(00-visual-ground-truth.md §2)의 측정값을 하나로 모은 토큰.
// 색상은 기존 ColorScheme.fromSeed / Pretendard / categoryColor 경로를 대체하지 않고
// 보조 상수로만 제공한다. 계약이 요구한 dp/반경/타입 수치의 SSOT.
import 'package:flutter/material.dart';

/// 393 x 852 dp 앱 소유 뷰포트 기준 측정 토큰(00-visual-ground-truth.md §2).
abstract final class LalaVisualTokens {
  const LalaVisualTokens._();

  // --- spacing ---
  /// 온보딩/검색 가로 여백.
  static const double pageGutter = 24;

  /// 지도 칩/레일/시트 가로 여백.
  static const double mapGutter = 12;

  /// 같은 그룹 내 인접 컨트롤 간격.
  static const double contentGap = 12;

  /// 주요 블록 사이 간격.
  static const double sectionGap = 24;

  /// 온보딩 행 간격(S1 domestic→overseas 등).
  static const double onboardingRowGap = 16;

  // --- sizes ---
  /// 주/부 온보딩 액션 높이.
  static const double actionHeight = 52;

  /// 아이콘 전용 컨트롤 최소 타겟.
  static const double iconTarget = 44;

  /// 카드/행/칩/입력/버튼 공통 반경.
  static const double controlRadius = 8;

  /// 드래그 가능한 장소/상세 시트 상단 반경.
  static const double sheetTopRadius = 20;

  /// S3 지도 미리보기 높이.
  static const double locationPreviewHeight = 150;

  // --- typography (size / line height) ---
  static const double wordmarkSize = 18;
  static const double wordmarkLineHeight = 22;
  static const double onboardingTitleSize = 30;
  static const double onboardingTitleLineHeight = 36;
  static const double screenSize = 28;
  static const double screenLineHeight = 34;
  static const double sectionTitleSize = 20;
  static const double sectionTitleLineHeight = 26;
  static const double bodySize = 15;
  static const double bodyLineHeight = 22;
  static const double controlLabelSize = 16;
  static const double controlLabelLineHeight = 20;
  static const double chipSize = 13;
  static const double chipLineHeight = 16;
  static const double bottomNavSize = 12;
  static const double bottomNavLineHeight = 16;

  /// 하단 탭의 콘텐츠 높이. iOS 안전영역은 별도의 제한된 여백으로 더한다.
  static const double bottomNavHeight = 64;

  /// 홈 인디케이터와의 완충 여백 상한. 전체 시스템 패딩을 그대로 더하지 않는다.
  static const double bottomNavMaxSafeInset = 16;
}

/// 계약 색상 토큰. 거의 흰 canvas + 선명한 action blue + 카테고리 다색을 함께 써서
/// 근거 중심 화면이 회색 일변도로 보이지 않게 한다.
abstract final class LalaVisualColors {
  const LalaVisualColors._();

  static const Color primaryBlue = Color(0xFF0B67D8);
  static const Color primaryPressed = Color(0xFF0754B5);
  static const Color primarySoft = Color(0xFFEAF3FF);
  static const Color ink = Color(0xFF162033);
  static const Color muted = Color(0xFF5E6B7E);
  static const Color line = Color(0xFFDCE5F0);
  static const Color surface = Color(0xFFF8FBFF);
  static const Color card = Color(0xFFFFFFFF);
  static const Color disabledFill = Color(0xFFC9DCF5);
  static const Color disabledInk = Color(0xFF4D6685);

  // --- category colors (chip/pin) ---
  static const Color attraction = Color(0xFFD93C56);
  static const Color restaurant = Color(0xFFF4B740);
  static const Color event = Color(0xFF1769CF);
  static const Color culture = Color(0xFF0B8478);

  /// 식당 노랑 표면 위 텍스트 색(대비 확보를 위해 어둡게).
  static const Color restaurantInk = Color(0xFF1A202C);
}
