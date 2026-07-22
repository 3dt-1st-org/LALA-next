//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:lala_next_flutter_client_generated/src/model/me_data.dart';
import 'package:lala_next_flutter_client_generated/src/model/api_meta.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'me_success_envelope.g.dart';

/// MeSuccessEnvelope
///
/// Properties:
/// * [data] 
/// * [error] 
/// * [meta] 
/// * [ok] 
@BuiltValue()
abstract class MeSuccessEnvelope implements Built<MeSuccessEnvelope, MeSuccessEnvelopeBuilder> {
  @BuiltValueField(wireName: r'data')
  MeData get data;

  @BuiltValueField(wireName: r'error')
  JsonObject? get error;

  @BuiltValueField(wireName: r'meta')
  ApiMeta get meta;

  @BuiltValueField(wireName: r'ok')
  bool get ok;

  MeSuccessEnvelope._();

  factory MeSuccessEnvelope([void updates(MeSuccessEnvelopeBuilder b)]) = _$MeSuccessEnvelope;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MeSuccessEnvelopeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MeSuccessEnvelope> get serializer => _$MeSuccessEnvelopeSerializer();
}

class _$MeSuccessEnvelopeSerializer implements PrimitiveSerializer<MeSuccessEnvelope> {
  @override
  final Iterable<Type> types = const [MeSuccessEnvelope, _$MeSuccessEnvelope];

  @override
  final String wireName = r'MeSuccessEnvelope';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MeSuccessEnvelope object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'data';
    yield serializers.serialize(
      object.data,
      specifiedType: const FullType(MeData),
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
    MeSuccessEnvelope object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MeSuccessEnvelopeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MeData),
          ) as MeData;
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
  MeSuccessEnvelope deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MeSuccessEnvelopeBuilder();
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

