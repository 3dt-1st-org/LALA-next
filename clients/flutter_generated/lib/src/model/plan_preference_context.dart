//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'plan_preference_context.g.dart';

/// PlanPreferenceContext
///
/// Properties:
/// * [budgetBand]
/// * [excludeClosingSoon]
/// * [foodCuisines]
/// * [indoorOutdoor]
/// * [maxOneWayMinutes]
/// * [walkingBand]
/// * [weatherSensitivity]
@BuiltValue()
abstract class PlanPreferenceContext implements Built<PlanPreferenceContext, PlanPreferenceContextBuilder> {
  @BuiltValueField(wireName: r'budget_band')
  PlanPreferenceContextBudgetBandEnum? get budgetBand;
  // enum budgetBandEnum {  value,  balanced,  special,  };

  @BuiltValueField(wireName: r'exclude_closing_soon')
  bool? get excludeClosingSoon;

  @BuiltValueField(wireName: r'food_cuisines')
  BuiltList<PlanPreferenceContextFoodCuisinesEnum>? get foodCuisines;
  // enum foodCuisinesEnum {  korean,  streetFood,  cafeDessert,  marketFood,  worldCuisine,  };

  @BuiltValueField(wireName: r'indoor_outdoor')
  PlanPreferenceContextIndoorOutdoorEnum? get indoorOutdoor;
  // enum indoorOutdoorEnum {  indoor,  balanced,  outdoor,  };

  @BuiltValueField(wireName: r'max_one_way_minutes')
  int? get maxOneWayMinutes;

  @BuiltValueField(wireName: r'walking_band')
  PlanPreferenceContextWalkingBandEnum? get walkingBand;
  // enum walkingBandEnum {  short,  medium,  long,  };

  @BuiltValueField(wireName: r'weather_sensitivity')
  PlanPreferenceContextWeatherSensitivityEnum? get weatherSensitivity;
  // enum weatherSensitivityEnum {  low,  medium,  high,  };

  PlanPreferenceContext._();

  factory PlanPreferenceContext([void updates(PlanPreferenceContextBuilder b)]) = _$PlanPreferenceContext;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlanPreferenceContextBuilder b) => b
    ..indoorOutdoor = PlanPreferenceContextIndoorOutdoorEnum.balanced
    ..weatherSensitivity = PlanPreferenceContextWeatherSensitivityEnum.medium
    ..walkingBand = PlanPreferenceContextWalkingBandEnum.medium
    ..maxOneWayMinutes = 30
    ..budgetBand = PlanPreferenceContextBudgetBandEnum.balanced
    ..excludeClosingSoon = true;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlanPreferenceContext> get serializer => _$PlanPreferenceContextSerializer();
}

class _$PlanPreferenceContextSerializer implements PrimitiveSerializer<PlanPreferenceContext> {
  @override
  final Iterable<Type> types = const [PlanPreferenceContext, _$PlanPreferenceContext];

  @override
  final String wireName = r'PlanPreferenceContext';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlanPreferenceContext object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.budgetBand != null) {
      yield r'budget_band';
      yield serializers.serialize(
        object.budgetBand,
        specifiedType: const FullType(PlanPreferenceContextBudgetBandEnum),
      );
    }
    if (object.excludeClosingSoon != null) {
      yield r'exclude_closing_soon';
      yield serializers.serialize(
        object.excludeClosingSoon,
        specifiedType: const FullType(bool),
      );
    }
    if (object.foodCuisines != null) {
      yield r'food_cuisines';
      yield serializers.serialize(
        object.foodCuisines,
        specifiedType: const FullType(BuiltList, [FullType(PlanPreferenceContextFoodCuisinesEnum)]),
      );
    }
    if (object.indoorOutdoor != null) {
      yield r'indoor_outdoor';
      yield serializers.serialize(
        object.indoorOutdoor,
        specifiedType: const FullType(PlanPreferenceContextIndoorOutdoorEnum),
      );
    }
    if (object.maxOneWayMinutes != null) {
      yield r'max_one_way_minutes';
      yield serializers.serialize(
        object.maxOneWayMinutes,
        specifiedType: const FullType(int),
      );
    }
    if (object.walkingBand != null) {
      yield r'walking_band';
      yield serializers.serialize(
        object.walkingBand,
        specifiedType: const FullType(PlanPreferenceContextWalkingBandEnum),
      );
    }
    if (object.weatherSensitivity != null) {
      yield r'weather_sensitivity';
      yield serializers.serialize(
        object.weatherSensitivity,
        specifiedType: const FullType(PlanPreferenceContextWeatherSensitivityEnum),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PlanPreferenceContext object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlanPreferenceContextBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'budget_band':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlanPreferenceContextBudgetBandEnum),
          ) as PlanPreferenceContextBudgetBandEnum;
          result.budgetBand = valueDes;
          break;
        case r'exclude_closing_soon':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.excludeClosingSoon = valueDes;
          break;
        case r'food_cuisines':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PlanPreferenceContextFoodCuisinesEnum)]),
          ) as BuiltList<PlanPreferenceContextFoodCuisinesEnum>;
          result.foodCuisines.replace(valueDes);
          break;
        case r'indoor_outdoor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlanPreferenceContextIndoorOutdoorEnum),
          ) as PlanPreferenceContextIndoorOutdoorEnum;
          result.indoorOutdoor = valueDes;
          break;
        case r'max_one_way_minutes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.maxOneWayMinutes = valueDes;
          break;
        case r'walking_band':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlanPreferenceContextWalkingBandEnum),
          ) as PlanPreferenceContextWalkingBandEnum;
          result.walkingBand = valueDes;
          break;
        case r'weather_sensitivity':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlanPreferenceContextWeatherSensitivityEnum),
          ) as PlanPreferenceContextWeatherSensitivityEnum;
          result.weatherSensitivity = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlanPreferenceContext deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlanPreferenceContextBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

class PlanPreferenceContextBudgetBandEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'value')
  static const PlanPreferenceContextBudgetBandEnum value = _$planPreferenceContextBudgetBandEnum_value;
  @BuiltValueEnumConst(wireName: r'balanced')
  static const PlanPreferenceContextBudgetBandEnum balanced = _$planPreferenceContextBudgetBandEnum_balanced;
  @BuiltValueEnumConst(wireName: r'special')
  static const PlanPreferenceContextBudgetBandEnum special = _$planPreferenceContextBudgetBandEnum_special;

  static Serializer<PlanPreferenceContextBudgetBandEnum> get serializer => _$planPreferenceContextBudgetBandEnumSerializer;

  const PlanPreferenceContextBudgetBandEnum._(String name): super(name);

  static BuiltSet<PlanPreferenceContextBudgetBandEnum> get values => _$planPreferenceContextBudgetBandEnumValues;
  static PlanPreferenceContextBudgetBandEnum valueOf(String name) => _$planPreferenceContextBudgetBandEnumValueOf(name);
}

class PlanPreferenceContextFoodCuisinesEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'korean')
  static const PlanPreferenceContextFoodCuisinesEnum korean = _$planPreferenceContextFoodCuisinesEnum_korean;
  @BuiltValueEnumConst(wireName: r'streetFood')
  static const PlanPreferenceContextFoodCuisinesEnum streetFood = _$planPreferenceContextFoodCuisinesEnum_streetFood;
  @BuiltValueEnumConst(wireName: r'cafeDessert')
  static const PlanPreferenceContextFoodCuisinesEnum cafeDessert = _$planPreferenceContextFoodCuisinesEnum_cafeDessert;
  @BuiltValueEnumConst(wireName: r'marketFood')
  static const PlanPreferenceContextFoodCuisinesEnum marketFood = _$planPreferenceContextFoodCuisinesEnum_marketFood;
  @BuiltValueEnumConst(wireName: r'worldCuisine')
  static const PlanPreferenceContextFoodCuisinesEnum worldCuisine = _$planPreferenceContextFoodCuisinesEnum_worldCuisine;

  static Serializer<PlanPreferenceContextFoodCuisinesEnum> get serializer => _$planPreferenceContextFoodCuisinesEnumSerializer;

  const PlanPreferenceContextFoodCuisinesEnum._(String name): super(name);

  static BuiltSet<PlanPreferenceContextFoodCuisinesEnum> get values => _$planPreferenceContextFoodCuisinesEnumValues;
  static PlanPreferenceContextFoodCuisinesEnum valueOf(String name) => _$planPreferenceContextFoodCuisinesEnumValueOf(name);
}

class PlanPreferenceContextIndoorOutdoorEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'indoor')
  static const PlanPreferenceContextIndoorOutdoorEnum indoor = _$planPreferenceContextIndoorOutdoorEnum_indoor;
  @BuiltValueEnumConst(wireName: r'balanced')
  static const PlanPreferenceContextIndoorOutdoorEnum balanced = _$planPreferenceContextIndoorOutdoorEnum_balanced;
  @BuiltValueEnumConst(wireName: r'outdoor')
  static const PlanPreferenceContextIndoorOutdoorEnum outdoor = _$planPreferenceContextIndoorOutdoorEnum_outdoor;

  static Serializer<PlanPreferenceContextIndoorOutdoorEnum> get serializer => _$planPreferenceContextIndoorOutdoorEnumSerializer;

  const PlanPreferenceContextIndoorOutdoorEnum._(String name): super(name);

  static BuiltSet<PlanPreferenceContextIndoorOutdoorEnum> get values => _$planPreferenceContextIndoorOutdoorEnumValues;
  static PlanPreferenceContextIndoorOutdoorEnum valueOf(String name) => _$planPreferenceContextIndoorOutdoorEnumValueOf(name);
}

class PlanPreferenceContextWalkingBandEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'short')
  static const PlanPreferenceContextWalkingBandEnum short = _$planPreferenceContextWalkingBandEnum_short;
  @BuiltValueEnumConst(wireName: r'medium')
  static const PlanPreferenceContextWalkingBandEnum medium = _$planPreferenceContextWalkingBandEnum_medium;
  @BuiltValueEnumConst(wireName: r'long')
  static const PlanPreferenceContextWalkingBandEnum long = _$planPreferenceContextWalkingBandEnum_long;

  static Serializer<PlanPreferenceContextWalkingBandEnum> get serializer => _$planPreferenceContextWalkingBandEnumSerializer;

  const PlanPreferenceContextWalkingBandEnum._(String name): super(name);

  static BuiltSet<PlanPreferenceContextWalkingBandEnum> get values => _$planPreferenceContextWalkingBandEnumValues;
  static PlanPreferenceContextWalkingBandEnum valueOf(String name) => _$planPreferenceContextWalkingBandEnumValueOf(name);
}

class PlanPreferenceContextWeatherSensitivityEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'low')
  static const PlanPreferenceContextWeatherSensitivityEnum low = _$planPreferenceContextWeatherSensitivityEnum_low;
  @BuiltValueEnumConst(wireName: r'medium')
  static const PlanPreferenceContextWeatherSensitivityEnum medium = _$planPreferenceContextWeatherSensitivityEnum_medium;
  @BuiltValueEnumConst(wireName: r'high')
  static const PlanPreferenceContextWeatherSensitivityEnum high = _$planPreferenceContextWeatherSensitivityEnum_high;

  static Serializer<PlanPreferenceContextWeatherSensitivityEnum> get serializer => _$planPreferenceContextWeatherSensitivityEnumSerializer;

  const PlanPreferenceContextWeatherSensitivityEnum._(String name): super(name);

  static BuiltSet<PlanPreferenceContextWeatherSensitivityEnum> get values => _$planPreferenceContextWeatherSensitivityEnumValues;
  static PlanPreferenceContextWeatherSensitivityEnum valueOf(String name) => _$planPreferenceContextWeatherSensitivityEnumValueOf(name);
}

