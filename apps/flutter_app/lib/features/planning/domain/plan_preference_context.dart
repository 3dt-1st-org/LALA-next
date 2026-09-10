import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_store.dart';
import 'package:lala_next_app/features/trip_library/domain/trip_library_models.dart';

/// CP1: 플랜 생성에 실을 유효 선호 컨텍스트 공급자. 주입 지점(테스트 교체 가능).
typedef LalaPlanPreferenceContextProvider
    = Future<LalaPlanPreferenceContext> Function();

/// 기본 공급자: 현재 불러온 TravelPreferences 기본값 + 해당 여행 날짜의
/// TripPreferenceOverride 를 기존 precedence 방식(applyTo)으로 합성한다.
/// 읽기 전용 — 전역 변경을 일으키지 않으며, 계정 동기화는 전제가 아니다
/// (게스트는 기기 로컬 문서가 그대로 권위다).
LalaPlanPreferenceContextProvider get defaultPlanPreferenceContextProvider =>
    composePlanPreferenceContext;

/// 유효 컨텍스트 합성. override 가 지원하는 필드는 항상 기본값을 이긴다
/// (TripPreferenceOverride.applyTo — null 필드는 기본값 상속).
Future<LalaPlanPreferenceContext> composePlanPreferenceContext({
  TravelPreferencesStore? preferencesStore,
  TripLibraryStore? tripLibraryStore,
  String? planDate,
}) async {
  final prefsStore = preferencesStore ?? TravelPreferencesStore.instance;
  final tripStore = tripLibraryStore ?? TripLibraryStore.instance;
  await prefsStore.ensureLoaded();
  await tripStore.ensureLoaded();
  final effective = tripStore.effectivePreferences(
    planDate ?? tripLibraryDateKey(),
    prefsStore.value,
  );
  return planPreferenceContextFrom(effective);
}

/// 합성된 유효 선호를 요청 컨텍스트로 내린다. 비민감 soft 값만 옮긴다 —
/// 알레르겐·식이·기피 식재료·이동약성/접근성 선언은 앱→공개 플랜 엔드포인트로
/// 전송되지 않는다(계약 경계).
LalaPlanPreferenceContext planPreferenceContextFrom(TravelPreferences effective) {
  final cuisines = effective.cuisines.map((c) => c.name).toList()..sort();
  return LalaPlanPreferenceContext(
    indoorOutdoor: effective.indoorOutdoorPreference.name,
    weatherSensitivity: effective.weatherSensitivity.name,
    walkingBand: effective.walkingBand.name,
    maxOneWayMinutes: effective.maxOneWayMinutes,
    foodCuisines: cuisines,
    budgetBand: effective.budgetBand.name,
    excludeClosingSoon: effective.excludeClosingSoon,
  );
}
