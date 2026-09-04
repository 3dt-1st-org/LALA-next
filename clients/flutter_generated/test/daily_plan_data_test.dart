import 'package:test/test.dart';
import 'package:built_collection/built_collection.dart';
import 'package:lala_next_flutter_client_generated/lala_next_flutter_client_generated.dart';

// tests for DailyPlanData
void main() {
  group(DailyPlanData, () {
    // BuiltList<PreferenceEffect>? preferenceEffects — CP1: absent → null
    // (legacy plans), present → parsed entries.
    test('preferenceEffects stays null for a legacy payload', () {
      const wire = [
        r'cache_key',
        r'daily_plan:abc',
        r'center',
        [r'lat', 37.2, r'lng', 127.0],
        r'language',
        r'ko',
        r'radius_m',
        3000,
        r'request_hash',
        r'b1111111111111111111111111111111111111111111111111111111111111111',
        r'slots',
        [],
        r'source',
        r'db',
        r'weather',
        [
          r'lat',
          37.2,
          r'lng',
          127.0,
          r'temp',
          r'21.0',
          r'icon',
          r'sun',
          r'dust',
          [
            r'pm10',
            r'10',
            r'pm25',
            r'5',
            r'grade',
            r'good',
            r'grade_ko',
            r'좋음',
            r'pm10_grade',
            r'good',
            r'pm10_grade_ko',
            r'좋음',
            r'pm25_grade',
            r'good',
            r'pm25_grade_ko',
            r'좋음',
          ],
          r'forecast',
          [],
          r'outdoor_status',
          r'good',
          r'force',
          false,
          r'source',
          r'db',
        ],
      ];

      final data = standardSerializers.deserializeWith(DailyPlanData.serializer, wire)!;

      expect(data.preferenceEffects, isNull);
    });

    test('parses a plan payload with preference_effects', () {
      const wire = [
        r'cache_key',
        r'daily_plan:abc',
        r'center',
        [r'lat', 37.2, r'lng', 127.0],
        r'language',
        r'ko',
        r'preference_effects',
        [
          [
            r'field',
            r'indoor_outdoor',
            r'applied',
            true,
            r'reason_code',
            r'INDOOR_ORDERING_APPLIED',
            r'explanation',
            r'후보 순서를 조정했어요.',
          ],
          [
            r'field',
            r'food_cuisines',
            r'applied',
            false,
            r'reason_code',
            r'CUISINE_FACET_UNAVAILABLE',
            r'explanation',
            r'요리 정보가 없어요.',
          ],
        ],
        r'radius_m',
        3000,
        r'request_hash',
        r'b1111111111111111111111111111111111111111111111111111111111111111',
        r'slots',
        [],
        r'source',
        r'db',
        r'weather',
        [
          r'lat',
          37.2,
          r'lng',
          127.0,
          r'temp',
          r'21.0',
          r'icon',
          r'sun',
          r'dust',
          [
            r'pm10',
            r'10',
            r'pm25',
            r'5',
            r'grade',
            r'good',
            r'grade_ko',
            r'좋음',
            r'pm10_grade',
            r'good',
            r'pm10_grade_ko',
            r'좋음',
            r'pm25_grade',
            r'good',
            r'pm25_grade_ko',
            r'좋음',
          ],
          r'forecast',
          [],
          r'outdoor_status',
          r'good',
          r'force',
          false,
          r'source',
          r'db',
        ],
      ];

      final data = standardSerializers.deserializeWith(
        DailyPlanData.serializer,
        wire,
      )!;

      final effects = data.preferenceEffects!;
      expect(effects.length, 2);
      expect(effects[0].field, PreferenceEffectFieldEnum.indoorOutdoor);
      expect(effects[0].applied, isTrue);
      expect(effects[0].reasonCode, PreferenceEffectReasonCodeEnum.indoorOrderingApplied);
      expect(effects[1].applied, isFalse);
      expect(
        effects[1].reasonCode,
        PreferenceEffectReasonCodeEnum.cuisineFacetUnavailable,
      );
    });
  });
}
