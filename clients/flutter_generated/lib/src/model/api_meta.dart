//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'api_meta.g.dart';

/// ApiMeta
///
/// Properties:
/// * [requestId] 
@BuiltValue()
abstract class ApiMeta implements Built<ApiMeta, ApiMetaBuilder> {
  @BuiltValueField(wireName: r'request_id')
  String get requestId;

  ApiMeta._();

  factory ApiMeta([void updates(ApiMetaBuilder b)]) = _$ApiMeta;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApiMetaBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApiMeta> get serializer => _$ApiMetaSerializer();
}

class _$ApiMetaSerializer implements PrimitiveSerializer<ApiMeta> {
  @override
  final Iterable<Type> types = const [ApiMeta, _$ApiMeta];

  @override
  final String wireName = r'ApiMeta';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApiMeta object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'request_id';
    yield serializers.serialize(
      object.requestId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ApiMeta object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ApiMetaBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'request_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.requestId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApiMeta deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApiMetaBuilder();
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

