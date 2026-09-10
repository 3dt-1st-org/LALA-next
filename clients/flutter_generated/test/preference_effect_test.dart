import 'package:test/test.dart';
import 'package:lala_next_flutter_client_generated/lala_next_flutter_client_generated.dart';

// tests for PreferenceEffect — CP1 response-entry parsing contract.
void main() {
  group(PreferenceEffect, () {
    test('parses an applied radius effect with details', () {
      const wire = [
        r'field',
        r'max_one_way_minutes',
        r'applied',
        true,
        r'reason_code',
        r'RADIUS_CAPPED_TO_WALKING_TIME',
        r'explanation',
        'Capped the search radius from 5000m to 1005m.',
        r'details',
        {
          r'requested_radius_m': 5000,
          r'effective_radius_m': 1005,
          r'effective_one_way_minutes': 15,
          r'source_fields': [r'max_one_way_minutes'],
          r'walking_estimate': r'haversine_4kmh',
        },
      ];

      final effect = standardSerializers.deserializeWith(
        PreferenceEffect.serializer,
        wire,
      )!;

      expect(effect.field, PreferenceEffectFieldEnum.maxOneWayMinutes);
      expect(effect.applied, isTrue);
      expect(
        effect.reasonCode,
        PreferenceEffectReasonCodeEnum.RADIUS_CAPPED_TO_WALKING_TIME,
      );
      expect(effect.explanation, contains('1005'));
      expect(effect.details, isNotNull);
    });

    test('parses an honestly-unapplied cuisine effect without details', () {
      const wire = [
        r'field',
        r'food_cuisines',
        r'applied',
        false,
        r'reason_code',
        r'CUISINE_FACET_UNAVAILABLE',
        r'explanation',
        'Place data has no cuisine facet.',
      ];

      final effect = standardSerializers.deserializeWith(
        PreferenceEffect.serializer,
        wire,
      )!;

      expect(effect.field, PreferenceEffectFieldEnum.foodCuisines);
      expect(effect.applied, isFalse);
      expect(
        effect.reasonCode,
        PreferenceEffectReasonCodeEnum.CUISINE_FACET_UNAVAILABLE,
      );
      expect(effect.details, isNull);
    });

    test('round-trips every bounded field and reason-code enum value', () {
      for (final field in PreferenceEffectFieldEnum.values) {
        for (final reason in PreferenceEffectReasonCodeEnum.values) {
          final effect = PreferenceEffectBuilder()
            ..field = field
            ..applied = false
            ..reasonCode = reason
            ..explanation = 'unit';
          final wire = standardSerializers.serializeWith(
            PreferenceEffect.serializer,
            effect.build(),
          );
          final decoded = standardSerializers.deserializeWith(
            PreferenceEffect.serializer,
            wire,
          )!;
          expect(decoded.field, field);
          expect(decoded.reasonCode, reason);
        }
      }
    });
  });
}
