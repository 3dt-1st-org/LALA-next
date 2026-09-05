//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'plan_preference_context.g.dart';

/// CP1: 일정 생성에 반영할 수 있는 비민감 soft 선호 값만 담는다.  계약 경계(중요): 이 객체는 public plan endpoint 로 전송 가능한 값만 허용한다. 알레르겐·식이·기피 식재료·이동약성/접근성 선언·인증 클레임·PII·계정 식별자는 필드로 존재할 수 없다(extra=\"forbid\" 로 알 수 없는 키도 거부). 값 집합과 상한은 TravelPreferenceSoft 와 같은 소스(schemas/preferences.py)를 재사용한다.
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
  BuiltList<TravelPreferenceSoftFoodCuisinesEnum>? get foodCuisines;
  // enum foodCuisinesEnum {  korean,  streetFood,  cafeDessert,  marketFood,  worldCuisine,  };

  @BuiltValueField(wireName: r'indoor_outdoor')
  PlanPreferenceContextIndoorOutdoorEnum? get indoorOutdoor;
  // enum indoorOutdoorEnum {  indoor,  balanced,  outdoor,  };

  @BuiltValueField(wireName: r'max_one_way_minutes')
  PlanPreferenceContextMaxOneWayMinutesEnum? get maxOneWayMinutes;
  // enum maxOneWayMinutesEnum {  15,  30,  60,  90,  };

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
      ..budgetBand = const PlanPreferenceContextBudgetBandEnum._('balanced')
      ..excludeClosingSoon = true
      ..indoorOutdoor = const PlanPreferenceContextIndoorOutdoorEnum._('balanced')
      ..maxOneWayMinutes = const PlanPreferenceContextMaxOneWayMinutesEnum._('number30')
      ..walkingBand = const PlanPreferenceContextWalkingBandEnum._('medium')
      ..weatherSensitivity = const PlanPreferenceContextWeatherSensitivityEnum._('medium');

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
        specifiedType: const FullType(BuiltList, [FullType(TravelPreferenceSoftFoodCuisinesEnum)]),
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
        specifiedType: const FullType(PlanPreferenceContextMaxOneWayMinutesEnum),
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
            specifiedType: const FullType(BuiltList, [FullType(TravelPreferenceSoftFoodCuisinesEnum)]),
          ) as BuiltList<TravelPreferenceSoftFoodCuisinesEnum>;
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
            specifiedType: const FullType(PlanPreferenceContextMaxOneWayMinutesEnum),
          ) as PlanPreferenceContextMaxOneWayMinutesEnum;
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

class TravelPreferenceSoftFoodCuisinesEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'korean')
  static const TravelPreferenceSoftFoodCuisinesEnum korean = _$travelPreferenceSoftFoodCuisinesEnum_korean;
  @BuiltValueEnumConst(wireName: r'streetFood')
  static const TravelPreferenceSoftFoodCuisinesEnum streetFood = _$travelPreferenceSoftFoodCuisinesEnum_streetFood;
  @BuiltValueEnumConst(wireName: r'cafeDessert')
  static const TravelPreferenceSoftFoodCuisinesEnum cafeDessert = _$travelPreferenceSoftFoodCuisinesEnum_cafeDessert;
  @BuiltValueEnumConst(wireName: r'marketFood')
  static const TravelPreferenceSoftFoodCuisinesEnum marketFood = _$travelPreferenceSoftFoodCuisinesEnum_marketFood;
  @BuiltValueEnumConst(wireName: r'worldCuisine')
  static const TravelPreferenceSoftFoodCuisinesEnum worldCuisine = _$travelPreferenceSoftFoodCuisinesEnum_worldCuisine;

  static Serializer<TravelPreferenceSoftFoodCuisinesEnum> get serializer => _$travelPreferenceSoftFoodCuisinesEnumSerializer;

  const TravelPreferenceSoftFoodCuisinesEnum._(String name): super(name);

  static BuiltSet<TravelPreferenceSoftFoodCuisinesEnum> get values => _$travelPreferenceSoftFoodCuisinesEnumValues;
  static TravelPreferenceSoftFoodCuisinesEnum valueOf(String name) => _$travelPreferenceSoftFoodCuisinesEnumValueOf(name);
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

class PlanPreferenceContextMaxOneWayMinutesEnum extends EnumClass {

  @BuiltValueEnumConst(wireNumber: 15)
  static const PlanPreferenceContextMaxOneWayMinutesEnum number15 = _$planPreferenceContextMaxOneWayMinutesEnum_number15;
  @BuiltValueEnumConst(wireNumber: 30)
  static const PlanPreferenceContextMaxOneWayMinutesEnum number30 = _$planPreferenceContextMaxOneWayMinutesEnum_number30;
  @BuiltValueEnumConst(wireNumber: 60)
  static const PlanPreferenceContextMaxOneWayMinutesEnum number60 = _$planPreferenceContextMaxOneWayMinutesEnum_number60;
  @BuiltValueEnumConst(wireNumber: 90)
  static const PlanPreferenceContextMaxOneWayMinutesEnum number90 = _$planPreferenceContextMaxOneWayMinutesEnum_number90;

  static Serializer<PlanPreferenceContextMaxOneWayMinutesEnum> get serializer => _$planPreferenceContextMaxOneWayMinutesEnumSerializer;

  const PlanPreferenceContextMaxOneWayMinutesEnum._(String name): super(name);

  static BuiltSet<PlanPreferenceContextMaxOneWayMinutesEnum> get values => _$planPreferenceContextMaxOneWayMinutesEnumValues;
  static PlanPreferenceContextMaxOneWayMinutesEnum valueOf(String name) => _$planPreferenceContextMaxOneWayMinutesEnumValueOf(name);
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

