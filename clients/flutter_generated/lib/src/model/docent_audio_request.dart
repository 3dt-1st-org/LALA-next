//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'docent_audio_request.g.dart';

/// DocentAudioRequest
///
/// Properties:
/// * [language] 
/// * [script] 
@BuiltValue()
abstract class DocentAudioRequest implements Built<DocentAudioRequest, DocentAudioRequestBuilder> {
  @BuiltValueField(wireName: r'language')
  String? get language;

  @BuiltValueField(wireName: r'script')
  String get script;

  DocentAudioRequest._();

  factory DocentAudioRequest([void updates(DocentAudioRequestBuilder b)]) = _$DocentAudioRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DocentAudioRequestBuilder b) => b
      ..language = 'ko';

  @BuiltValueSerializer(custom: true)
  static Serializer<DocentAudioRequest> get serializer => _$DocentAudioRequestSerializer();
}

class _$DocentAudioRequestSerializer implements PrimitiveSerializer<DocentAudioRequest> {
  @override
  final Iterable<Type> types = const [DocentAudioRequest, _$DocentAudioRequest];

  @override
  final String wireName = r'DocentAudioRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DocentAudioRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.language != null) {
      yield r'language';
      yield serializers.serialize(
        object.language,
        specifiedType: const FullType(String),
      );
    }
    yield r'script';
    yield serializers.serialize(
      object.script,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DocentAudioRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DocentAudioRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'language':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.language = valueDes;
          break;
        case r'script':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.script = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DocentAudioRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DocentAudioRequestBuilder();
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

