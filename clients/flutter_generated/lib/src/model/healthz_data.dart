//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'healthz_data.g.dart';

/// HealthzData
///
/// Properties:
/// * [service] 
/// * [status] 
/// * [version] 
@BuiltValue()
abstract class HealthzData implements Built<HealthzData, HealthzDataBuilder> {
  @BuiltValueField(wireName: r'service')
  HealthzDataServiceEnum get service;
  // enum serviceEnum {  lala-next-api,  };

  @BuiltValueField(wireName: r'status')
  HealthzDataStatusEnum get status;
  // enum statusEnum {  ok,  };

  @BuiltValueField(wireName: r'version')
  String get version;

  HealthzData._();

  factory HealthzData([void updates(HealthzDataBuilder b)]) = _$HealthzData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HealthzDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<HealthzData> get serializer => _$HealthzDataSerializer();
}

class _$HealthzDataSerializer implements PrimitiveSerializer<HealthzData> {
  @override
  final Iterable<Type> types = const [HealthzData, _$HealthzData];

  @override
  final String wireName = r'HealthzData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    HealthzData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'service';
    yield serializers.serialize(
      object.service,
      specifiedType: const FullType(HealthzDataServiceEnum),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(HealthzDataStatusEnum),
    );
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    HealthzData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required HealthzDataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'service':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(HealthzDataServiceEnum),
          ) as HealthzDataServiceEnum;
          result.service = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(HealthzDataStatusEnum),
          ) as HealthzDataStatusEnum;
          result.status = valueDes;
          break;
        case r'version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.version = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  HealthzData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HealthzDataBuilder();
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

class HealthzDataServiceEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'lala-next-api')
  static const HealthzDataServiceEnum lalaNextApi = _$healthzDataServiceEnum_lalaNextApi;

  static Serializer<HealthzDataServiceEnum> get serializer => _$healthzDataServiceEnumSerializer;

  const HealthzDataServiceEnum._(String name): super(name);

  static BuiltSet<HealthzDataServiceEnum> get values => _$healthzDataServiceEnumValues;
  static HealthzDataServiceEnum valueOf(String name) => _$healthzDataServiceEnumValueOf(name);
}

class HealthzDataStatusEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'ok')
  static const HealthzDataStatusEnum ok = _$healthzDataStatusEnum_ok;

  static Serializer<HealthzDataStatusEnum> get serializer => _$healthzDataStatusEnumSerializer;

  const HealthzDataStatusEnum._(String name): super(name);

  static BuiltSet<HealthzDataStatusEnum> get values => _$healthzDataStatusEnumValues;
  static HealthzDataStatusEnum valueOf(String name) => _$healthzDataStatusEnumValueOf(name);
}

