//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'dust.g.dart';

/// Dust
///
/// Properties:
/// * [grade] 
/// * [gradeKo] 
/// * [pm10] 
/// * [pm10Grade] 
/// * [pm10GradeKo] 
/// * [pm25] 
/// * [pm25Grade] 
/// * [pm25GradeKo] 
@BuiltValue()
abstract class Dust implements Built<Dust, DustBuilder> {
  @BuiltValueField(wireName: r'grade')
  String get grade;

  @BuiltValueField(wireName: r'grade_ko')
  String get gradeKo;

  @BuiltValueField(wireName: r'pm10')
  String get pm10;

  @BuiltValueField(wireName: r'pm10_grade')
  String get pm10Grade;

  @BuiltValueField(wireName: r'pm10_grade_ko')
  String get pm10GradeKo;

  @BuiltValueField(wireName: r'pm25')
  String get pm25;

  @BuiltValueField(wireName: r'pm25_grade')
  String get pm25Grade;

  @BuiltValueField(wireName: r'pm25_grade_ko')
  String get pm25GradeKo;

  Dust._();

  factory Dust([void updates(DustBuilder b)]) = _$Dust;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DustBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Dust> get serializer => _$DustSerializer();
}

class _$DustSerializer implements PrimitiveSerializer<Dust> {
  @override
  final Iterable<Type> types = const [Dust, _$Dust];

  @override
  final String wireName = r'Dust';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Dust object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'grade';
    yield serializers.serialize(
      object.grade,
      specifiedType: const FullType(String),
    );
    yield r'grade_ko';
    yield serializers.serialize(
      object.gradeKo,
      specifiedType: const FullType(String),
    );
    yield r'pm10';
    yield serializers.serialize(
      object.pm10,
      specifiedType: const FullType(String),
    );
    yield r'pm10_grade';
    yield serializers.serialize(
      object.pm10Grade,
      specifiedType: const FullType(String),
    );
    yield r'pm10_grade_ko';
    yield serializers.serialize(
      object.pm10GradeKo,
      specifiedType: const FullType(String),
    );
    yield r'pm25';
    yield serializers.serialize(
      object.pm25,
      specifiedType: const FullType(String),
    );
    yield r'pm25_grade';
    yield serializers.serialize(
      object.pm25Grade,
      specifiedType: const FullType(String),
    );
    yield r'pm25_grade_ko';
    yield serializers.serialize(
      object.pm25GradeKo,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    Dust object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DustBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'grade':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.grade = valueDes;
          break;
        case r'grade_ko':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.gradeKo = valueDes;
          break;
        case r'pm10':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pm10 = valueDes;
          break;
        case r'pm10_grade':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pm10Grade = valueDes;
          break;
        case r'pm10_grade_ko':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pm10GradeKo = valueDes;
          break;
        case r'pm25':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pm25 = valueDes;
          break;
        case r'pm25_grade':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pm25Grade = valueDes;
          break;
        case r'pm25_grade_ko':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pm25GradeKo = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Dust deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DustBuilder();
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

