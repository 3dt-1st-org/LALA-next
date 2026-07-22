//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:lala_next_flutter_client_generated/src/model/api_meta.dart';
import 'package:lala_next_flutter_client_generated/src/model/healthz_data.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'healthz_success_envelope.g.dart';

/// HealthzSuccessEnvelope
///
/// Properties:
/// * [data] 
/// * [error] 
/// * [meta] 
/// * [ok] 
@BuiltValue()
abstract class HealthzSuccessEnvelope implements Built<HealthzSuccessEnvelope, HealthzSuccessEnvelopeBuilder> {
  @BuiltValueField(wireName: r'data')
  HealthzData get data;

  @BuiltValueField(wireName: r'error')
  JsonObject? get error;

  @BuiltValueField(wireName: r'meta')
  ApiMeta get meta;

  @BuiltValueField(wireName: r'ok')
  bool get ok;

  HealthzSuccessEnvelope._();

  factory HealthzSuccessEnvelope([void updates(HealthzSuccessEnvelopeBuilder b)]) = _$HealthzSuccessEnvelope;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HealthzSuccessEnvelopeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<HealthzSuccessEnvelope> get serializer => _$HealthzSuccessEnvelopeSerializer();
}

class _$HealthzSuccessEnvelopeSerializer implements PrimitiveSerializer<HealthzSuccessEnvelope> {
  @override
  final Iterable<Type> types = const [HealthzSuccessEnvelope, _$HealthzSuccessEnvelope];

  @override
  final String wireName = r'HealthzSuccessEnvelope';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    HealthzSuccessEnvelope object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'data';
    yield serializers.serialize(
      object.data,
      specifiedType: const FullType(HealthzData),
    );
    if (object.error != null) {
      yield r'error';
      yield serializers.serialize(
        object.error,
        specifiedType: const FullType(JsonObject),
      );
    }
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
    HealthzSuccessEnvelope object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required HealthzSuccessEnvelopeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(HealthzData),
          ) as HealthzData;
          result.data = valueDes.toBuilder();
          break;
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(JsonObject),
          ) as JsonObject;
          result.error = valueDes;
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
  HealthzSuccessEnvelope deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HealthzSuccessEnvelopeBuilder();
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

