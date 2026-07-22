// ONMU P0: 하단 네비게이션 3-분기 경로 상수.
// 각 분기는 하나의 탭(검색 / 지도 / 플랜)에 대응하며 StatefulShellRoute 와 매핑된다.
// ONMU P2: 온보딩 4단계 경로(splash/start/language/location) 추가.
abstract final class LalaRoutePaths {
  const LalaRoutePaths._();

  static const String search = '/search';
  static const String mapRoute = '/map-route';
  static const String plan = '/plan';

  /// 온보딩 라우트 공통 접두사. redirect 가 온보딩 라우트 여부를 판별하는 데 사용.
  static const String onboardingPrefix = '/onboarding';

  /// 1/4 스플래시 — 온보딩 진입점. 미완료 시 메인 라우트가 여기로 리다이렉트된다.
  static const String onboardingSplash = '/onboarding/splash';

  /// 2/4 관광객 유형 선택.
  static const String onboardingStart = '/onboarding/start';

  /// 3/4 언어 선택.
  static const String onboardingLanguage = '/onboarding/language';

  /// 4/4 위치 권한 요청 — 완료 시 /map-route 로 전환.
  static const String onboardingLocation = '/onboarding/location';
}
