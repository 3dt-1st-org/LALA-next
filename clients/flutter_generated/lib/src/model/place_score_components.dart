//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'place_score_components.g.dart';

/// PlaceScoreComponents
///
/// Properties:
/// * [accessibilityFitScore] 
/// * [cultureRelevanceScore] 
/// * [demandDispersionScore] 
/// * [localSpendingScore] 
/// * [reviewQualityScore] 
/// * [smallMerchantFitScore] 
/// * [weatherFitScore] 
@BuiltValue()
abstract class PlaceScoreComponents implements Built<PlaceScoreComponents, PlaceScoreComponentsBuilder> {
  @BuiltValueField(wireName: r'accessibility_fit_score')
  double get accessibilityFitScore;

  @BuiltValueField(wireName: r'culture_relevance_score')
  double get cultureRelevanceScore;

  @BuiltValueField(wireName: r'demand_dispersion_score')
  double get demandDispersionScore;

  @BuiltValueField(wireName: r'local_spending_score')
  double get localSpendingScore;

  @BuiltValueField(wireName: r'review_quality_score')
  double get reviewQualityScore;

  @BuiltValueField(wireName: r'small_merchant_fit_score')
  double get smallMerchantFitScore;

  @BuiltValueField(wireName: r'weather_fit_score')
  double get weatherFitScore;

  PlaceScoreComponents._();

  factory PlaceScoreComponents([void updates(PlaceScoreComponentsBuilder b)]) = _$PlaceScoreComponents;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaceScoreComponentsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlaceScoreComponents> get serializer => _$PlaceScoreComponentsSerializer();
}

class _$PlaceScoreComponentsSerializer implements PrimitiveSerializer<PlaceScoreComponents> {
  @override
  final Iterable<Type> types = const [PlaceScoreComponents, _$PlaceScoreComponents];

  @override
  final String wireName = r'PlaceScoreComponents';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlaceScoreComponents object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'accessibility_fit_score';
    yield serializers.serialize(
      object.accessibilityFitScore,
      specifiedType: const FullType(double),
    );
    yield r'culture_relevance_score';
    yield serializers.serialize(
      object.cultureRelevanceScore,
      specifiedType: const FullType(double),
    );
    yield r'demand_dispersion_score';
    yield serializers.serialize(
      object.demandDispersionScore,
      specifiedType: const FullType(double),
    );
    yield r'local_spending_score';
    yield serializers.serialize(
      object.localSpendingScore,
      specifiedType: const FullType(double),
    );
    yield r'review_quality_score';
    yield serializers.serialize(
      object.reviewQualityScore,
      specifiedType: const FullType(double),
    );
    yield r'small_merchant_fit_score';
    yield serializers.serialize(
      object.smallMerchantFitScore,
      specifiedType: const FullType(double),
    );
    yield r'weather_fit_score';
    yield serializers.serialize(
      object.weatherFitScore,
      specifiedType: const FullType(double),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlaceScoreComponents object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaceScoreComponentsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'accessibility_fit_score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.accessibilityFitScore = valueDes;
          break;
        case r'culture_relevance_score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.cultureRelevanceScore = valueDes;
          break;
        case r'demand_dispersion_score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.demandDispersionScore = valueDes;
          break;
        case r'local_spending_score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.localSpendingScore = valueDes;
          break;
        case r'review_quality_score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.reviewQualityScore = valueDes;
          break;
        case r'small_merchant_fit_score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.smallMerchantFitScore = valueDes;
          break;
        case r'weather_fit_score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.weatherFitScore = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlaceScoreComponents deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaceScoreComponentsBuilder();
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

