// ONMU P0: 하단 네비게이션 3-분기 경로 상수.
// 각 분기는 하나의 탭(검색 / 지도 / 플랜)에 대응하며 StatefulShellRoute 와 매핑된다.
abstract final class LalaRoutePaths {
  const LalaRoutePaths._();

  static const String search = '/search';
  static const String mapRoute = '/map-route';
  static const String plan = '/plan';
}
