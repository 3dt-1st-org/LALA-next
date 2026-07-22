//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:lala_next_flutter_client_generated/src/model/api_error.dart';
import 'package:lala_next_flutter_client_generated/src/model/api_meta.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'api_error_envelope.g.dart';

/// ApiErrorEnvelope
///
/// Properties:
/// * [data] 
/// * [error] 
/// * [meta] 
/// * [ok] 
@BuiltValue()
abstract class ApiErrorEnvelope implements Built<ApiErrorEnvelope, ApiErrorEnvelopeBuilder> {
  @BuiltValueField(wireName: r'data')
  JsonObject get data;

  @BuiltValueField(wireName: r'error')
  ApiError get error;

  @BuiltValueField(wireName: r'meta')
  ApiMeta get meta;

  @BuiltValueField(wireName: r'ok')
  bool get ok;

  ApiErrorEnvelope._();

  factory ApiErrorEnvelope([void updates(ApiErrorEnvelopeBuilder b)]) = _$ApiErrorEnvelope;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApiErrorEnvelopeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApiErrorEnvelope> get serializer => _$ApiErrorEnvelopeSerializer();
}

class _$ApiErrorEnvelopeSerializer implements PrimitiveSerializer<ApiErrorEnvelope> {
  @override
  final Iterable<Type> types = const [ApiErrorEnvelope, _$ApiErrorEnvelope];

  @override
  final String wireName = r'ApiErrorEnvelope';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApiErrorEnvelope object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'data';
    yield serializers.serialize(
      object.data,
      specifiedType: const FullType(JsonObject),
    );
    yield r'error';
    yield serializers.serialize(
      object.error,
      specifiedType: const FullType(ApiError),
    );
    yield r'meta';
    yield serializers.serialize(
      object.meta,
      specifiedType: const FullType(ApiMeta),
    );
    yield r'ok';
    yield serializers.serialize(
      object.ok,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ApiErrorEnvelope object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ApiErrorEnvelopeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(JsonObject),
          ) as JsonObject;
          result.data = valueDes;
          break;
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ApiError),
          ) as ApiError;
          result.error = valueDes.toBuilder();
          break;
        case r'meta':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ApiMeta),
          ) as ApiMeta;
          result.meta = valueDes.toBuilder();
          break;
        case r'ok':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.ok = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApiErrorEnvelope deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApiErrorEnvelopeBuilder();
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

