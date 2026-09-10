// CP1: 유효 선호 컨텍스트 합성 계약 — 기기 우선 기본값 + 여행 날짜 override.
// override 가 지원하는 필드는 항상 기본값을 이기고, 미지정 필드는 기본값을
// 상속한다(기존 TripPreferenceOverride.applyTo precedence). 게스트(계정 미연동)
// 도 기기 로컬 문서로 동작한다. 주입 스토어만 사용 — 전역 변경 없음.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/features/planning/domain/plan_preference_context.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_store.dart';
import 'package:lala_next_app/features/trip_library/domain/trip_library_models.dart';

void main() {
  test('device-first defaults compose without any account connection', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefsStore = TravelPreferencesStore();
    final tripStore = TripLibraryStore();

    final context = await composePlanPreferenceContext(
      preferencesStore: prefsStore,
      tripLibraryStore: tripStore,
    );

    // 기본값 그대로 — 계정 동기화가 전제가 아니다.
    expect(context, const LalaPlanPreferenceContext());
    expect(context.foodCuisines, isEmpty);
  });

  test('trip override wins for supported fields, defaults inherit the rest', () async {
    final planDate = tripLibraryDateKey();
    final preferencesDoc = jsonEncode(<String, dynamic>{
      'version': 1,
      'soft': <String, dynamic>{
        'indoor_outdoor': 'outdoor',
        'weather_sensitivity': 'low',
        'walking_band': 'medium',
        'food_cuisines': <String>['korean', 'cafeDessert'],
        'max_one_way_minutes': 90,
        'budget_band': 'value',
        'exclude_closing_soon': false,
      },
      'hard': <String, dynamic>{},
      'locale': <String, dynamic>{},
    });
    final tripDoc = jsonEncode(<String, dynamic>{
      'v': 1,
      'overrides': <String, dynamic>{
        planDate: <String, dynamic>{
          'revision': 1,
          'updated_at': null,
          'dirty': false,
          'value': <String, dynamic>{
            'version': 1,
            'indoor_outdoor': 'indoor',
            'weather_sensitivity': 'high',
            'walking_band': 'short',
          },
        },
      },
      'visits': <String, dynamic>{},
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      'lala.travel_preferences.v1': preferencesDoc,
      'lala.trip_library.v1': tripDoc,
    });
    final prefsStore = TravelPreferencesStore();
    final tripStore = TripLibraryStore();

    final context = await composePlanPreferenceContext(
      preferencesStore: prefsStore,
      tripLibraryStore: tripStore,
      planDate: planDate,
    );

    // override 필드: override 승리.
    expect(context.indoorOutdoor, 'indoor');
    expect(context.weatherSensitivity, 'high');
    expect(context.walkingBand, 'short');
    // override 미지원/미지정 필드: 기본값 상속.
    expect(context.maxOneWayMinutes, 90);
    expect(context.foodCuisines, <String>['cafeDessert', 'korean']); // 정렬 포함.
    expect(context.budgetBand, 'value');
    expect(context.excludeClosingSoon, isFalse);
  });

  test('override absent for the trip date keeps pure defaults', () async {
    final preferencesDoc = jsonEncode(<String, dynamic>{
      'version': 1,
      'soft': <String, dynamic>{'indoor_outdoor': 'outdoor'},
      'hard': <String, dynamic>{},
      'locale': <String, dynamic>{},
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      'lala.travel_preferences.v1': preferencesDoc,
    });
    final prefsStore = TravelPreferencesStore();
    final tripStore = TripLibraryStore();

    final context = await composePlanPreferenceContext(
      preferencesStore: prefsStore,
      tripLibraryStore: tripStore,
      planDate: '2099-01-01',
    );

    expect(context.indoorOutdoor, 'outdoor');
    expect(context.walkingBand, 'medium');
  });
}
