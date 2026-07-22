// ONMU P2: 온보딩 플로우의 in-memory 전역 상태.
// - completed(ValueNotifier<bool>): GoRouter refreshListenable 이 구독. 완료 시 메인 쉘로 전환.
// - language / touristType: start·language 단계 선택을 다음 단계로 전달.
// SharedPreferences 영속화는 후속 작업에서 연결(이번엔 메모리 only).
import 'package:flutter/foundation.dart';

/// 온보딩 start 단계에서 선택하는 관광객 유형.
enum OnboardingTouristType { foreignTourist, localTourist }

/// 온보딩 진행 상태를 담는 간단한 전역 홀더(싱글톤 static).
///
/// GoRouter 의 refreshListenable 이 [completedListenable] 을 구독하여,
/// [markCompleted] 호출 시 redirect 가 재평가되고 메인 쉘(/map-route) 로 전환된다.
/// 첫 실행 시 [isCompleted] 는 false 이므로 메인 라우트 접근이 /onboarding/splash 로
/// 리다이렉트된다.
class OnboardingState {
  OnboardingState._();

  static final ValueNotifier<bool> _completed = ValueNotifier<bool>(false);
  static String _language = 'ko';
  static OnboardingTouristType _touristType =
      OnboardingTouristType.localTourist;

  /// GoRouter.refreshListenable 에 전달할 리스너.
  static ValueListenable<bool> get completedListenable => _completed;

  /// 온보딩 완료 여부.
  static bool get isCompleted => _completed.value;

  /// 현재 선택된 언어 코드(ko/en). start 단계 선택의 기본값이 반영된다.
  static String get language => _language;

  /// 현재 선택된 관광객 유형.
  static OnboardingTouristType get touristType => _touristType;

  /// 관광객 유형을 선택하고 기본 언어를 함께 세팅한다.
  /// - 외국인 관광객 → English(en)
  /// - 내국인 관광객 → 한국어(ko)
  static void selectTouristType(OnboardingTouristType type) {
    _touristType = type;
    _language = type == OnboardingTouristType.foreignTourist ? 'en' : 'ko';
  }

  /// 언어를 직접 변경(language 단계에서 start 기본값을 덮어쓸 수 있다).
  static void selectLanguage(String language) {
    _language = language == 'en' ? 'en' : 'ko';
  }

  /// 온보딩을 완료로 표시한다. refreshListenable 이 트리거되어 메인 쉘로 이동한다.
  static void markCompleted() {
    _completed.value = true;
  }

  /// 상태를 초기값(미완료)으로 되돌린다. 테스트/재온보딩에 사용.
  static void reset() {
    _touristType = OnboardingTouristType.localTourist;
    _language = 'ko';
    _completed.value = false;
  }
}
