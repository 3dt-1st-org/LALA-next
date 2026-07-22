//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'me_data.g.dart';

/// MeData
///
/// Properties:
/// * [authenticated] 
/// * [createdAt] 
/// * [userId] 
@BuiltValue()
abstract class MeData implements Built<MeData, MeDataBuilder> {
  @BuiltValueField(wireName: r'authenticated')
  bool get authenticated;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  @BuiltValueField(wireName: r'user_id')
  String get userId;

  MeData._();

  factory MeData([void updates(MeDataBuilder b)]) = _$MeData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MeDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MeData> get serializer => _$MeDataSerializer();
}

class _$MeDataSerializer implements PrimitiveSerializer<MeData> {
  @override
  final Iterable<Type> types = const [MeData, _$MeData];

  @override
  final String wireName = r'MeData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MeData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'authenticated';
    yield serializers.serialize(
      object.authenticated,
      specifiedType: const FullType(bool),
    );
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    MeData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MeDataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'authenticated':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.authenticated = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'user_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MeData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MeDataBuilder();
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

