//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'preference_effect.g.dart';

/// One grounded (or honestly unapplied) travel-preference effect on the plan. Field names, reason codes and details are bounded enums/keys; raw preference documents and sensitive values are never included.
///
/// Properties:
/// * [applied] - True only when the effect observably changed the plan.
/// * [details] - Bounded structured facts (e.g. requested vs effective radius, weather status, ordering provenance).
/// * [explanation] - Localized (ko/en) user-safe explanation.
/// * [field] - Preference-context field this effect reports on.
/// * [reasonCode]
@BuiltValue()
abstract class PreferenceEffect implements Built<PreferenceEffect, PreferenceEffectBuilder> {
  /// True only when the effect observably changed the plan.
  @BuiltValueField(wireName: r'applied')
  bool get applied;

  /// Bounded structured facts (e.g. requested vs effective radius, weather status, ordering provenance).
  @BuiltValueField(wireName: r'details')
  JsonObject? get details;

  /// Localized (ko/en) user-safe explanation.
  @BuiltValueField(wireName: r'explanation')
  String get explanation;

  /// Preference-context field this effect reports on.
  @BuiltValueField(wireName: r'field')
  PreferenceEffectFieldEnum get field;
  // enum fieldEnum {  indoor_outdoor,  max_one_way_minutes,  walking_band,  food_cuisines,  budget_band,  exclude_closing_soon,  };

  @BuiltValueField(wireName: r'reason_code')
  PreferenceEffectReasonCodeEnum get reasonCode;
  // enum reasonCodeEnum {  RADIUS_CAPPED_TO_WALKING_TIME,  RADIUS_CAP_NOT_BINDING,  INDOOR_ORDERING_APPLIED,  WEATHER_SAFETY_INDOOR_PRIORITY,  INDOOR_ORDERING_NOT_DIRECTIONAL,  INDOOR_ORDERING_NO_CHANGE,  INDOOR_STATUS_UNAVAILABLE,  CUISINE_FACET_UNAVAILABLE,  PRICE_FACET_UNAVAILABLE,  CLOSING_SOON_FACET_UNAVAILABLE,  };

  PreferenceEffect._();

  factory PreferenceEffect([void updates(PreferenceEffectBuilder b)]) = _$PreferenceEffect;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PreferenceEffectBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PreferenceEffect> get serializer => _$PreferenceEffectSerializer();
}

class _$PreferenceEffectSerializer implements PrimitiveSerializer<PreferenceEffect> {
  @override
  final Iterable<Type> types = const [PreferenceEffect, _$PreferenceEffect];

  @override
  final String wireName = r'PreferenceEffect';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PreferenceEffect object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'applied';
    yield serializers.serialize(
      object.applied,
      specifiedType: const FullType(bool),
    );
    if (object.details != null) {
      yield r'details';
      yield serializers.serialize(
        object.details,
        specifiedType: const FullType(JsonObject),
      );
    }
    yield r'explanation';
    yield serializers.serialize(
      object.explanation,
      specifiedType: const FullType(String),
    );
    yield r'field';
    yield serializers.serialize(
      object.field,
      specifiedType: const FullType(PreferenceEffectFieldEnum),
    );
    yield r'reason_code';
    yield serializers.serialize(
      object.reasonCode,
      specifiedType: const FullType(PreferenceEffectReasonCodeEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PreferenceEffect object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PreferenceEffectBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'applied':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.applied = valueDes;
          break;
        case r'details':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(JsonObject),
          ) as JsonObject;
          result.details = valueDes;
          break;
        case r'explanation':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.explanation = valueDes;
          break;
        case r'field':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PreferenceEffectFieldEnum),
          ) as PreferenceEffectFieldEnum;
          result.field = valueDes;
          break;
        case r'reason_code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PreferenceEffectReasonCodeEnum),
          ) as PreferenceEffectReasonCodeEnum;
          result.reasonCode = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PreferenceEffect deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PreferenceEffectBuilder();
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

class PreferenceEffectFieldEnum extends EnumClass {

  /// Preference-context field this effect reports on.
  @BuiltValueEnumConst(wireName: r'indoor_outdoor')
  static const PreferenceEffectFieldEnum indoorOutdoor = _$preferenceEffectFieldEnum_indoorOutdoor;
  /// Preference-context field this effect reports on.
  @BuiltValueEnumConst(wireName: r'max_one_way_minutes')
  static const PreferenceEffectFieldEnum maxOneWayMinutes = _$preferenceEffectFieldEnum_maxOneWayMinutes;
  /// Preference-context field this effect reports on.
  @BuiltValueEnumConst(wireName: r'walking_band')
  static const PreferenceEffectFieldEnum walkingBand = _$preferenceEffectFieldEnum_walkingBand;
  /// Preference-context field this effect reports on.
  @BuiltValueEnumConst(wireName: r'food_cuisines')
  static const PreferenceEffectFieldEnum foodCuisines = _$preferenceEffectFieldEnum_foodCuisines;
  /// Preference-context field this effect reports on.
  @BuiltValueEnumConst(wireName: r'budget_band')
  static const PreferenceEffectFieldEnum budgetBand = _$preferenceEffectFieldEnum_budgetBand;
  /// Preference-context field this effect reports on.
  @BuiltValueEnumConst(wireName: r'exclude_closing_soon')
  static const PreferenceEffectFieldEnum excludeClosingSoon = _$preferenceEffectFieldEnum_excludeClosingSoon;

  static Serializer<PreferenceEffectFieldEnum> get serializer => _$preferenceEffectFieldEnumSerializer;

  const PreferenceEffectFieldEnum._(String name): super(name);

  static BuiltSet<PreferenceEffectFieldEnum> get values => _$preferenceEffectFieldEnumValues;
  static PreferenceEffectFieldEnum valueOf(String name) => _$preferenceEffectFieldEnumValueOf(name);
}

class PreferenceEffectReasonCodeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'RADIUS_CAPPED_TO_WALKING_TIME')
  static const PreferenceEffectReasonCodeEnum RADIUS_CAPPED_TO_WALKING_TIME = _$preferenceEffectReasonCodeEnum_RADIUS_CAPPED_TO_WALKING_TIME;
  @BuiltValueEnumConst(wireName: r'RADIUS_CAP_NOT_BINDING')
  static const PreferenceEffectReasonCodeEnum RADIUS_CAP_NOT_BINDING = _$preferenceEffectReasonCodeEnum_RADIUS_CAP_NOT_BINDING;
  @BuiltValueEnumConst(wireName: r'INDOOR_ORDERING_APPLIED')
  static const PreferenceEffectReasonCodeEnum INDOOR_ORDERING_APPLIED = _$preferenceEffectReasonCodeEnum_INDOOR_ORDERING_APPLIED;
  @BuiltValueEnumConst(wireName: r'WEATHER_SAFETY_INDOOR_PRIORITY')
  static const PreferenceEffectReasonCodeEnum WEATHER_SAFETY_INDOOR_PRIORITY = _$preferenceEffectReasonCodeEnum_WEATHER_SAFETY_INDOOR_PRIORITY;
  @BuiltValueEnumConst(wireName: r'INDOOR_ORDERING_NOT_DIRECTIONAL')
  static const PreferenceEffectReasonCodeEnum INDOOR_ORDERING_NOT_DIRECTIONAL = _$preferenceEffectReasonCodeEnum_INDOOR_ORDERING_NOT_DIRECTIONAL;
  @BuiltValueEnumConst(wireName: r'INDOOR_ORDERING_NO_CHANGE')
  static const PreferenceEffectReasonCodeEnum INDOOR_ORDERING_NO_CHANGE = _$preferenceEffectReasonCodeEnum_INDOOR_ORDERING_NO_CHANGE;
  @BuiltValueEnumConst(wireName: r'INDOOR_STATUS_UNAVAILABLE')
  static const PreferenceEffectReasonCodeEnum INDOOR_STATUS_UNAVAILABLE = _$preferenceEffectReasonCodeEnum_INDOOR_STATUS_UNAVAILABLE;
  @BuiltValueEnumConst(wireName: r'CUISINE_FACET_UNAVAILABLE')
  static const PreferenceEffectReasonCodeEnum CUISINE_FACET_UNAVAILABLE = _$preferenceEffectReasonCodeEnum_CUISINE_FACET_UNAVAILABLE;
  @BuiltValueEnumConst(wireName: r'PRICE_FACET_UNAVAILABLE')
  static const PreferenceEffectReasonCodeEnum PRICE_FACET_UNAVAILABLE = _$preferenceEffectReasonCodeEnum_PRICE_FACET_UNAVAILABLE;
  @BuiltValueEnumConst(wireName: r'CLOSING_SOON_FACET_UNAVAILABLE')
  static const PreferenceEffectReasonCodeEnum CLOSING_SOON_FACET_UNAVAILABLE = _$preferenceEffectReasonCodeEnum_CLOSING_SOON_FACET_UNAVAILABLE;

  static Serializer<PreferenceEffectReasonCodeEnum> get serializer => _$preferenceEffectReasonCodeEnumSerializer;

  const PreferenceEffectReasonCodeEnum._(String name): super(name);

  static BuiltSet<PreferenceEffectReasonCodeEnum> get values => _$preferenceEffectReasonCodeEnumValues;
  static PreferenceEffectReasonCodeEnum valueOf(String name) => _$preferenceEffectReasonCodeEnumValueOf(name);
}

