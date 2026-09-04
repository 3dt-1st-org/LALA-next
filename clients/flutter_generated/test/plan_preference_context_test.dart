import 'package:test/test.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'package:lala_next_flutter_client_generated/lala_next_flutter_client_generated.dart';

// tests for PlanPreferenceContext — CP1 wire-shape contract.
void main() {
  group(PlanPreferenceContext, () {
    test('serializes all soft fields with snake_case wire keys', () {
      final context = PlanPreferenceContextBuilder()
        ..indoorOutdoor = PlanPreferenceContextIndoorOutdoorEnum.outdoor
        ..weatherSensitivity = PlanPreferenceContextWeatherSensitivityEnum.high
        ..walkingBand = PlanPreferenceContextWalkingBandEnum.short
        ..maxOneWayMinutes = 15
        ..foodCuisines = ListBuilder<PlanPreferenceContextFoodCuisinesEnum>([
          PlanPreferenceContextFoodCuisinesEnum.korean,
          PlanPreferenceContextFoodCuisinesEnum.cafeDessert,
        ])
        ..budgetBand = PlanPreferenceContextBudgetBandEnum.value
        ..excludeClosingSoon = false;

      final serialized = standardSerializers.serialize(
        context.build(),
        specifiedType: const FullType(PlanPreferenceContext),
      ) as Map<String, Object?>;

      expect(serialized, {
        r'indoor_outdoor': 'outdoor',
        r'weather_sensitivity': 'high',
        r'walking_band': 'short',
        r'max_one_way_minutes': 15,
        r'food_cuisines': ['korean', 'cafeDessert'],
        r'budget_band': 'value',
        r'exclude_closing_soon': false,
      });
    });

    test('defaults mirror the server-side bounds', () {
      final context = PlanPreferenceContextBuilder().build();

      expect(context.indoorOutdoor, PlanPreferenceContextIndoorOutdoorEnum.balanced);
      expect(
        context.weatherSensitivity,
        PlanPreferenceContextWeatherSensitivityEnum.medium,
      );
      expect(context.walkingBand, PlanPreferenceContextWalkingBandEnum.medium);
      expect(context.maxOneWayMinutes, 30);
      expect(context.foodCuisines, isNull);
      expect(context.budgetBand, PlanPreferenceContextBudgetBandEnum.balanced);
      expect(context.excludeClosingSoon, isTrue);
    });

    test('round-trips through the standard serializers', () {
      final builder = PlanPreferenceContextBuilder()
        ..indoorOutdoor = PlanPreferenceContextIndoorOutdoorEnum.indoor
        ..maxOneWayMinutes = 60
        ..foodCuisines = ListBuilder<PlanPreferenceContextFoodCuisinesEnum>(
          [PlanPreferenceContextFoodCuisinesEnum.marketFood],
        );
      final context = builder.build();

      final wire = standardSerializers.serializeWith(
        PlanPreferenceContext.serializer,
        context,
      );
      final decoded = standardSerializers.deserializeWith(
        PlanPreferenceContext.serializer,
        wire,
      )!;

      expect(decoded.indoorOutdoor, PlanPreferenceContextIndoorOutdoorEnum.indoor);
      expect(decoded.maxOneWayMinutes, 60);
      expect(
        decoded.foodCuisines!.single,
        PlanPreferenceContextFoodCuisinesEnum.marketFood,
      );
    });
  });
}
