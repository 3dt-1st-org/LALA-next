//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'daily_plan_request.g.dart';

/// DailyPlanRequest
///
/// Properties:
/// * [language] 
/// * [lat] 
/// * [lng] 
/// * [radiusM] 
@BuiltValue()
abstract class DailyPlanRequest implements Built<DailyPlanRequest, DailyPlanRequestBuilder> {
  @BuiltValueField(wireName: r'language')
  String? get language;

  @BuiltValueField(wireName: r'lat')
  num get lat;

  @BuiltValueField(wireName: r'lng')
  num get lng;

  @BuiltValueField(wireName: r'radius_m')
  int? get radiusM;

  DailyPlanRequest._();

  factory DailyPlanRequest([void updates(DailyPlanRequestBuilder b)]) = _$DailyPlanRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DailyPlanRequestBuilder b) => b
      ..language = 'ko'
      ..radiusM = 3000;

  @BuiltValueSerializer(custom: true)
  static Serializer<DailyPlanRequest> get serializer => _$DailyPlanRequestSerializer();
}

class _$DailyPlanRequestSerializer implements PrimitiveSerializer<DailyPlanRequest> {
  @override
  final Iterable<Type> types = const [DailyPlanRequest, _$DailyPlanRequest];

  @override
  final String wireName = r'DailyPlanRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DailyPlanRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.language != null) {
      yield r'language';
      yield serializers.serialize(
        object.language,
        specifiedType: const FullType(String),
      );
    }
    yield r'lat';
    yield serializers.serialize(
      object.lat,
      specifiedType: const FullType(num),
    );
    yield r'lng';
    yield serializers.serialize(
      object.lng,
      specifiedType: const FullType(num),
    );
    if (object.radiusM != null) {
      yield r'radius_m';
      yield serializers.serialize(
        object.radiusM,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DailyPlanRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DailyPlanRequestBuilder result,
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
        case r'lat':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.lat = valueDes;
          break;
        case r'lng':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.lng = valueDes;
          break;
        case r'radius_m':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.radiusM = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DailyPlanRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DailyPlanRequestBuilder();
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

