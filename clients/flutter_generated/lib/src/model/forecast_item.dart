//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'forecast_item.g.dart';

/// ForecastItem
///
/// Properties:
/// * [icon] 
/// * [temp] 
/// * [time] 
@BuiltValue()
abstract class ForecastItem implements Built<ForecastItem, ForecastItemBuilder> {
  @BuiltValueField(wireName: r'icon')
  String get icon;

  @BuiltValueField(wireName: r'temp')
  String get temp;

  @BuiltValueField(wireName: r'time')
  String get time;

  ForecastItem._();

  factory ForecastItem([void updates(ForecastItemBuilder b)]) = _$ForecastItem;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ForecastItemBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ForecastItem> get serializer => _$ForecastItemSerializer();
}

class _$ForecastItemSerializer implements PrimitiveSerializer<ForecastItem> {
  @override
  final Iterable<Type> types = const [ForecastItem, _$ForecastItem];

  @override
  final String wireName = r'ForecastItem';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ForecastItem object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'icon';
    yield serializers.serialize(
      object.icon,
      specifiedType: const FullType(String),
    );
    yield r'temp';
    yield serializers.serialize(
      object.temp,
      specifiedType: const FullType(String),
    );
    yield r'time';
    yield serializers.serialize(
      object.time,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ForecastItem object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ForecastItemBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'icon':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.icon = valueDes;
          break;
        case r'temp':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.temp = valueDes;
          break;
        case r'time':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.time = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ForecastItem deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ForecastItemBuilder();
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

