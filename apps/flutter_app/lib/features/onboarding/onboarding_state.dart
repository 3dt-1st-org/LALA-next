// ONMU P2: 온보딩 플로우의 전역 상태 홀더(싱글톤 static).
// - completed(ValueNotifier<bool>): GoRouter refreshListenable 이 구독. 완료 시 메인 쉘로 전환.
// - language / touristType: start·language 단계 선택을 다음 단계로 전달.
// Wave-1 cold-start: 완료/언어/관광객 유형을 SharedPreferences 로 영속화(restart 에도 복원).
//   정확한 기기 좌표/RegionSource.current 는 영속화하지 않는다(privacy).
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';

/// 온보딩 start 단계에서 선택하는 관광객 유형.
enum OnboardingTouristType { foreignTourist, localTourist }

/// 온보딩 진행 상태를 담는 간단한 전역 홀더(싱글톤 static).
///
/// GoRouter 의 refreshListenable 이 [completedListenable] 을 구독하여,
/// [markCompleted] 호출 시 redirect 가 재평가되고 메인 쉘(/map-route) 로 전환된다.
/// 첫 실행 시 [isCompleted] 는 false 이므로 메인 라우트 접근이 /onboarding/splash 로
/// 리다이렉트된다. Cold-start 시 [applySnapshot] 이 영속화된 값을 먼저 복원한다.
class OnboardingState {
  OnboardingState._();

  static final ValueNotifier<bool> _completed = ValueNotifier<bool>(false);
  static final ValueNotifier<String> _language = ValueNotifier<String>('ko');
  static OnboardingTouristType _touristType =
      OnboardingTouristType.localTourist;

  // Optional cold-start persistence. When attached (bootstrapAppState), the
  // intentional choices below are write-through so they survive a process
  // restart. null in tests that don't exercise persistence.
  static OnboardingPreferences? _prefs;

  /// GoRouter.refreshListenable 에 전달할 리스너.
  static ValueListenable<bool> get completedListenable => _completed;

  /// 온보딩 완료 여부.
  static bool get isCompleted => _completed.value;

  /// 현재 선택된 언어 코드(ko/en). start 단계 선택의 기본값이 반영된다.
  static String get language => _language.value;

  /// 런타임 UI가 구독하는 선택 언어 SSOT.
  static ValueListenable<String> get languageListenable => _language;

  /// 현재 선택된 관광객 유형.
  static OnboardingTouristType get touristType => _touristType;

  /// 이 프로세스에서 영속화를 활성화한다(bootstrapAppState 참고).
  static void attachPersistence(OnboardingPreferences prefs) => _prefs = prefs;

  /// 영속화 참조를 해제(테스트 격리).
  static void detachPersistence() => _prefs = null;

  /// 관광객 유형을 선택하고 기본 언어를 함께 세팅한다.
  /// - 외국인 관광객 → English(en)
  /// - 내국인 관광객 → 한국어(ko)
  static void selectTouristType(OnboardingTouristType type) {
    _touristType = type;
    _language.value = type == OnboardingTouristType.foreignTourist
        ? 'en'
        : 'ko';
    _persist();
  }

  /// 언어를 직접 변경(language 단계에서 start 기본값을 덮어쓸 수 있다).
  static void selectLanguage(String language) {
    _language.value = language == 'en' ? 'en' : 'ko';
    _persist();
  }

  /// 온보딩을 완료로 표시한다. refreshListenable 이 트리거되어 메인 쉘로 이동한다.
  /// 동기 경로/기존 테스트 호환용. 완료 게이트를 넘기기 전에 영속화까지 보장하려면
  /// [completeAndFlush] 를 쓴다(완료 지점에서 호출).
  static void markCompleted() {
    _completed.value = true;
    _persist();
  }

  /// 온보딩을 완료로 표시하면서, 라우터가 보는 게이트를 뒤집기 *전에* 영속화를
  /// 확정한다. 완료 탭 직후 프로세스가 종료되어도 restart 상태를 잃지 않도록.
  /// 저장 실패해도 인메모리 완료는 기록한다(사용자를 온보딩에 남기지 않는다) —
  /// 단 cold restart 에는 기억되지 않는다.
  static Future<void> completeAndFlush() async {
    final prefs = _prefs;
    if (prefs == null) {
      _completed.value = true;
      return;
    }
    try {
      await prefs.writeOnboarding(
        completed: true,
        language: _language.value,
        touristTypeCode: _encodeTouristType(_touristType),
      );
    } on Object {
      // best-effort: 아래에서 인메모리 완료는 기록한다.
    }
    // 게이트를 저장 *후*에 뒤집어 refreshListenable redirect 가 영속화 이후에 발생.
    _completed.value = true;
  }

  /// Cold start: 영속화된 스냅샷으로 인메모리 상태를 복원한다. 역직렬화는
  /// 이미 안전한 기본값으로 정규화되어 있으므로 추가 검증 없이 적용한다.
  static void applySnapshot(OnboardingSnapshot snapshot) {
    _language.value = snapshot.language == 'en' ? 'en' : 'ko';
    _touristType = _decodeTouristType(snapshot.touristTypeCode);
    _completed.value = snapshot.completed;
  }

  /// 현재 선택을 best-effort 로 영속화. select/markCompleted 은 동기여야 하므로
  /// fire-and-forget 한다. 완료 지점의 내비게이션 전 확정 보장은 completeAndFlush.
  static void _persist() {
    final prefs = _prefs;
    if (prefs == null) {
      return;
    }
    unawaited(_writeSnapshot(prefs));
  }

  static Future<void> _writeSnapshot(OnboardingPreferences prefs) async {
    try {
      await prefs.writeOnboarding(
        completed: _completed.value,
        language: _language.value,
        touristTypeCode: _encodeTouristType(_touristType),
      );
    } on Object {
      // best-effort 영속화; 인메모리 상태가 권위 있다.
    }
  }

  /// 상태를 초기값(미완료)으로 되돌린다. 테스트/재온보딩에 사용.
  /// 재온보딩은 영속화된 완료/선택도 함께 지워 restart 로 이전 완료 상태가
  /// 부활하지 않도록 한다. region 영속화는 RegionContextStore.clear() 가 담당.
  static void reset() {
    _touristType = OnboardingTouristType.localTourist;
    _language.value = 'ko';
    _completed.value = false;
    final prefs = _prefs;
    if (prefs == null) {
      return;
    }
    unawaited(_clearAll(prefs));
  }

  static Future<void> _clearAll(OnboardingPreferences prefs) async {
    try {
      await prefs.clearAll();
    } on Object {
      // best-effort.
    }
  }

  static String _encodeTouristType(OnboardingTouristType type) {
    return type == OnboardingTouristType.foreignTourist
        ? kTouristTypeCodeForeign
        : kTouristTypeCodeLocal;
  }

  static OnboardingTouristType _decodeTouristType(String code) {
    return code == kTouristTypeCodeForeign
        ? OnboardingTouristType.foreignTourist
        : OnboardingTouristType.localTourist;
  }
}
