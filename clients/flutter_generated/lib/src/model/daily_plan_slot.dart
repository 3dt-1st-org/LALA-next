//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:lala_next_flutter_client_generated/src/model/place.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'daily_plan_slot.g.dart';

/// DailyPlanSlot
///
/// Properties:
/// * [period] 
/// * [place] 
/// * [title] 
/// * [weatherHint] 
@BuiltValue()
abstract class DailyPlanSlot implements Built<DailyPlanSlot, DailyPlanSlotBuilder> {
  @BuiltValueField(wireName: r'period')
  String get period;

  @BuiltValueField(wireName: r'place')
  Place? get place;

  @BuiltValueField(wireName: r'title')
  String get title;

  @BuiltValueField(wireName: r'weather_hint')
  String? get weatherHint;

  DailyPlanSlot._();

  factory DailyPlanSlot([void updates(DailyPlanSlotBuilder b)]) = _$DailyPlanSlot;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DailyPlanSlotBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DailyPlanSlot> get serializer => _$DailyPlanSlotSerializer();
}

class _$DailyPlanSlotSerializer implements PrimitiveSerializer<DailyPlanSlot> {
  @override
  final Iterable<Type> types = const [DailyPlanSlot, _$DailyPlanSlot];

  @override
  final String wireName = r'DailyPlanSlot';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DailyPlanSlot object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'period';
    yield serializers.serialize(
      object.period,
      specifiedType: const FullType(String),
    );
    if (object.place != null) {
      yield r'place';
      yield serializers.serialize(
        object.place,
        specifiedType: const FullType(Place),
      );
    }
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    if (object.weatherHint != null) {
      yield r'weather_hint';
      yield serializers.serialize(
        object.weatherHint,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DailyPlanSlot object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DailyPlanSlotBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'period':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.period = valueDes;
          break;
        case r'place':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Place),
          ) as Place;
          result.place = valueDes.toBuilder();
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'weather_hint':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.weatherHint = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DailyPlanSlot deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DailyPlanSlotBuilder();
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

