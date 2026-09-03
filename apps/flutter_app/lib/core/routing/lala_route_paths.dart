// LALA main-shell tab route constants.
// Each branch maps to one tab (search / map / plan / Local Signals / profile).
// ONMU P2: 온보딩 4단계 경로(splash/start/language/location) 추가.
abstract final class LalaRoutePaths {
  const LalaRoutePaths._();

  static const String search = '/search';
  static const String mapRoute = '/map-route';
  static const String plan = '/plan';
  static const String localSignals = '/local-signals';
  static const String profile = '/profile';

  /// Canonical full-screen place detail. The map/search hand-off also passes a
  /// LalaPlace through GoRouterState.extra so the first frame does not refetch.
  static const String placeDetail = '/places/:placeId';

  /// Account and preference routes are pushed above the profile tab.
  static const String account = '/profile/account';
  static const String travelPreferences = '/profile/travel-preferences';
  static const String savedPlaces = '/profile/saved-places';
  static const String pastTrips = '/profile/past-trips';
  static const String tripSettings = '/plan/:planDate/settings';
  static const String visitConfirmation = '/plan/:planDate/visit/:slotPeriod';
  static const String interventionComparison = '/plan/change-comparison';
  static const String localSignalDetail = '/local-signals/detail/:signalId';

  /// S-31 feed-level contribution. Stable path so a web refresh or deep link
  /// rebuilds contribute mode without GoRouter extra; the optional coarse
  /// region/place context travels in extra only — never in the URL, which
  /// carries no coordinates or ids beyond this fixed segment.
  static const String localSignalContribution = '/local-signals/contribute';
  static const String preferenceSyncConflict =
      '/profile/preference-sync-conflict';
  static const String privacyLocation = '/profile/privacy-location';

  /// 온보딩 라우트 공통 접두사. redirect 가 온보딩 라우트 여부를 판별하는 데 사용.
  static const String onboardingPrefix = '/onboarding';

  /// 1/4 스플래시 — 온보딩 진입점. 미완료 시 메인 라우트가 여기로 리다이렉트된다.
  static const String onboardingSplash = '/onboarding/splash';

  /// 2/4 관광객 유형 선택.
  static const String onboardingStart = '/onboarding/start';

  /// 3/4 언어 선택.
  static const String onboardingLanguage = '/onboarding/language';

  /// 3/3 위치 권한 요청 — 선택형 계정 연결 또는 /map-route 로 전환.
  static const String onboardingLocation = '/onboarding/location';

  /// 위치 선택 뒤의 선택형 계정 연결. 3단계 진행률에는 포함하지 않는다.
  static const String onboardingAccount = '/onboarding/account';

  // --- ONMU P3b: 커뮤니티 push 라우트(메인 쉘 외부, 탭 상태 유지) ---
  /// 이슈 #120 §6.3: 전체 화면 도슨트 플레이어(메인 쉘 외부 push 라우트).
  static const String docentPlayer = '/docent-player';

  /// 커뮤니티 게시판 피드.
  static const String community = '/community';

  /// 커뮤니티 게시글 상세(:id = postId).
  static const String communityPost = '/community/post/:id';

  /// 커뮤니티 게시글 작성.
  static const String communityCreate = '/community/create';

  /// 커뮤니티 채팅방 목록.
  static const String communityChat = '/community/chat';

  /// 커뮤니티 채팅방(:id = roomId).
  static const String communityChatRoom = '/community/chat/:id';

  /// 커뮤니티 상세 경로를 postId 로 조합.
  static String communityPostFor(String postId) => '/community/post/$postId';

  /// 채팅방 경로를 roomId 로 조합.
  static String communityChatRoomFor(String roomId) =>
      '/community/chat/$roomId';

  static String placeDetailFor(String placeId) =>
      '/places/${Uri.encodeComponent(placeId)}';

  static String tripSettingsFor(String planDate) =>
      '/plan/${Uri.encodeComponent(planDate)}/settings';

  static String visitConfirmationFor(String planDate, String slotPeriod) =>
      '/plan/${Uri.encodeComponent(planDate)}/visit/'
      '${Uri.encodeComponent(slotPeriod)}';

  static String localSignalDetailFor(String signalId) =>
      '/local-signals/detail/${Uri.encodeComponent(signalId)}';
}
