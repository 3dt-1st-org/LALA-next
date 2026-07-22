//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:lala_next_flutter_client_generated/src/model/readiness_checks.dart';
import 'package:built_value/json_object.dart';
import 'package:lala_next_flutter_client_generated/src/model/runtime_mode.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'readyz_data.g.dart';

/// ReadyzData
///
/// Properties:
/// * [checks] 
/// * [mode] 
/// * [status] 
@BuiltValue()
abstract class ReadyzData implements Built<ReadyzData, ReadyzDataBuilder> {
  @BuiltValueField(wireName: r'checks')
  ReadinessChecks get checks;

  @BuiltValueField(wireName: r'mode')
  RuntimeMode get mode;

  @BuiltValueField(wireName: r'status')
  ReadyzDataStatusEnum get status;
  // enum statusEnum {  ok,  degraded,  };

  ReadyzData._();

  factory ReadyzData([void updates(ReadyzDataBuilder b)]) = _$ReadyzData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReadyzDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReadyzData> get serializer => _$ReadyzDataSerializer();
}

class _$ReadyzDataSerializer implements PrimitiveSerializer<ReadyzData> {
  @override
  final Iterable<Type> types = const [ReadyzData, _$ReadyzData];

  @override
  final String wireName = r'ReadyzData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReadyzData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'checks';
    yield serializers.serialize(
      object.checks,
      specifiedType: const FullType(ReadinessChecks),
    );
    yield r'mode';
    yield serializers.serialize(
      object.mode,
      specifiedType: const FullType(RuntimeMode),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(ReadyzDataStatusEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ReadyzData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReadyzDataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'checks':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecks),
          ) as ReadinessChecks;
          result.checks = valueDes.toBuilder();
          break;
        case r'mode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RuntimeMode),
          ) as RuntimeMode;
          result.mode = valueDes.toBuilder();
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadyzDataStatusEnum),
          ) as ReadyzDataStatusEnum;
          result.status = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReadyzData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReadyzDataBuilder();
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

class ReadyzDataStatusEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'ok')
  static const ReadyzDataStatusEnum ok = _$readyzDataStatusEnum_ok;
  @BuiltValueEnumConst(wireName: r'degraded')
  static const ReadyzDataStatusEnum degraded = _$readyzDataStatusEnum_degraded;

  static Serializer<ReadyzDataStatusEnum> get serializer => _$readyzDataStatusEnumSerializer;

  const ReadyzDataStatusEnum._(String name): super(name);

  static BuiltSet<ReadyzDataStatusEnum> get values => _$readyzDataStatusEnumValues;
  static ReadyzDataStatusEnum valueOf(String name) => _$readyzDataStatusEnumValueOf(name);
}

