//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:lala_next_flutter_client_generated/src/model/place_score_components.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'place_score.g.dart';

/// PlaceScore
///
/// Properties:
/// * [components] 
/// * [dataBasis] 
/// * [features] 
/// * [finalScore] 
/// * [formulaVersion] 
@BuiltValue()
abstract class PlaceScore implements Built<PlaceScore, PlaceScoreBuilder> {
  @BuiltValueField(wireName: r'components')
  PlaceScoreComponents get components;

  @BuiltValueField(wireName: r'data_basis')
  PlaceScoreDataBasisEnum get dataBasis;
  // enum dataBasisEnum {  analytics.place_score_snapshots,  public_mvp_snapshot,  };

  @BuiltValueField(wireName: r'features')
  JsonObject get features;

  @BuiltValueField(wireName: r'final_score')
  double get finalScore;

  @BuiltValueField(wireName: r'formula_version')
  String get formulaVersion;

  PlaceScore._();

  factory PlaceScore([void updates(PlaceScoreBuilder b)]) = _$PlaceScore;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaceScoreBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaceScore> get serializer => _$PlaceScoreSerializer();
}

class _$PlaceScoreSerializer implements PrimitiveSerializer<PlaceScore> {
  @override
  final Iterable<Type> types = const [PlaceScore, _$PlaceScore];

  @override
  final String wireName = r'PlaceScore';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaceScore object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'components';
    yield serializers.serialize(
      object.components,
      specifiedType: const FullType(PlaceScoreComponents),
    );
    yield r'data_basis';
    yield serializers.serialize(
      object.dataBasis,
      specifiedType: const FullType(PlaceScoreDataBasisEnum),
    );
    yield r'features';
    yield serializers.serialize(
      object.features,
      specifiedType: const FullType(JsonObject),
    );
    yield r'final_score';
    yield serializers.serialize(
      object.finalScore,
      specifiedType: const FullType(double),
    );
    yield r'formula_version';
    yield serializers.serialize(
      object.formulaVersion,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaceScore object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaceScoreBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'components':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlaceScoreComponents),
          ) as PlaceScoreComponents;
          result.components = valueDes.toBuilder();
          break;
        case r'data_basis':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlaceScoreDataBasisEnum),
          ) as PlaceScoreDataBasisEnum;
          result.dataBasis = valueDes;
          break;
        case r'features':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(JsonObject),
          ) as JsonObject;
          result.features = valueDes;
          break;
        case r'final_score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.finalScore = valueDes;
          break;
        case r'formula_version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.formulaVersion = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaceScore deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaceScoreBuilder();
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

class PlaceScoreDataBasisEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'analytics.place_score_snapshots')
  static const PlaceScoreDataBasisEnum analyticsPeriodPlaceScoreSnapshots = _$placeScoreDataBasisEnum_analyticsPeriodPlaceScoreSnapshots;
  @BuiltValueEnumConst(wireName: r'public_mvp_snapshot')
  static const PlaceScoreDataBasisEnum publicMvpSnapshot = _$placeScoreDataBasisEnum_publicMvpSnapshot;

  static Serializer<PlaceScoreDataBasisEnum> get serializer => _$placeScoreDataBasisEnumSerializer;

  const PlaceScoreDataBasisEnum._(String name): super(name);

  static BuiltSet<PlaceScoreDataBasisEnum> get values => _$placeScoreDataBasisEnumValues;
  static PlaceScoreDataBasisEnum valueOf(String name) => _$placeScoreDataBasisEnumValueOf(name);
}

