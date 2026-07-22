//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:lala_next_flutter_client_generated/src/model/coordinate.dart';
import 'package:built_collection/built_collection.dart';
import 'package:lala_next_flutter_client_generated/src/model/place.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'intervention_data.g.dart';

/// InterventionData
///
/// Properties:
/// * [center] 
/// * [place] 
/// * [radiusM] 
/// * [reason] 
/// * [recommendedAction] 
/// * [shouldIntervene] 
/// * [source_] 
@BuiltValue()
abstract class InterventionData implements Built<InterventionData, InterventionDataBuilder> {
  @BuiltValueField(wireName: r'center')
  Coordinate get center;

  @BuiltValueField(wireName: r'place')
  Place? get place;

  @BuiltValueField(wireName: r'radius_m')
  int get radiusM;

  @BuiltValueField(wireName: r'reason')
  String get reason;

  @BuiltValueField(wireName: r'recommended_action')
  String get recommendedAction;

  @BuiltValueField(wireName: r'should_intervene')
  bool get shouldIntervene;

  @BuiltValueField(wireName: r'source')
  InterventionDataSource_Enum get source_;
  // enum source_Enum {  unavailable,  public_mvp_snapshot,  db,  mixed,  };

  InterventionData._();

  factory InterventionData([void updates(InterventionDataBuilder b)]) = _$InterventionData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InterventionDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InterventionData> get serializer => _$InterventionDataSerializer();
}

class _$InterventionDataSerializer implements PrimitiveSerializer<InterventionData> {
  @override
  final Iterable<Type> types = const [InterventionData, _$InterventionData];

  @override
  final String wireName = r'InterventionData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InterventionData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'center';
    yield serializers.serialize(
      object.center,
      specifiedType: const FullType(Coordinate),
    );
    if (object.place != null) {
      yield r'place';
      yield serializers.serialize(
        object.place,
        specifiedType: const FullType(Place),
      );
    }
    yield r'radius_m';
    yield serializers.serialize(
      object.radiusM,
      specifiedType: const FullType(int),
    );
    yield r'reason';
    yield serializers.serialize(
      object.reason,
      specifiedType: const FullType(String),
    );
    yield r'recommended_action';
    yield serializers.serialize(
      object.recommendedAction,
      specifiedType: const FullType(String),
    );
    yield r'should_intervene';
    yield serializers.serialize(
      object.shouldIntervene,
      specifiedType: const FullType(bool),
    );
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(InterventionDataSource_Enum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    InterventionData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InterventionDataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'center':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Coordinate),
          ) as Coordinate;
          result.center = valueDes.toBuilder();
          break;
        case r'place':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Place),
          ) as Place;
          result.place = valueDes.toBuilder();
          break;
        case r'radius_m':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.radiusM = valueDes;
          break;
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reason = valueDes;
          break;
        case r'recommended_action':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.recommendedAction = valueDes;
          break;
        case r'should_intervene':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.shouldIntervene = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(InterventionDataSource_Enum),
          ) as InterventionDataSource_Enum;
          result.source_ = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InterventionData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InterventionDataBuilder();
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

class InterventionDataSource_Enum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'unavailable')
  static const InterventionDataSource_Enum unavailable = _$interventionDataSourceEnum_unavailable;
  @BuiltValueEnumConst(wireName: r'public_mvp_snapshot')
  static const InterventionDataSource_Enum publicMvpSnapshot = _$interventionDataSourceEnum_publicMvpSnapshot;
  @BuiltValueEnumConst(wireName: r'db')
  static const InterventionDataSource_Enum db = _$interventionDataSourceEnum_db;
  @BuiltValueEnumConst(wireName: r'mixed')
  static const InterventionDataSource_Enum mixed = _$interventionDataSourceEnum_mixed;

  static Serializer<InterventionDataSource_Enum> get serializer => _$interventionDataSourceEnumSerializer;

  const InterventionDataSource_Enum._(String name): super(name);

  static BuiltSet<InterventionDataSource_Enum> get values => _$interventionDataSourceEnumValues;
  static InterventionDataSource_Enum valueOf(String name) => _$interventionDataSourceEnumValueOf(name);
}

