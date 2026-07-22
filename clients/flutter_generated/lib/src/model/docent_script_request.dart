//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'docent_script_request.g.dart';

/// DocentScriptRequest
///
/// Properties:
/// * [address] 
/// * [category] 
/// * [cultureRelevanceScore] 
/// * [demandDispersionScore] 
/// * [distanceM] 
/// * [dustGrade] 
/// * [dustPm10] 
/// * [dustPm10Grade] 
/// * [dustPm25] 
/// * [dustPm25Grade] 
/// * [finalScore] 
/// * [language] 
/// * [localSpendingScore] 
/// * [mode] 
/// * [placeId] 
/// * [placeName] 
/// * [regionEn] 
/// * [regionKo] 
/// * [smallMerchantFitScore] 
/// * [source_] 
/// * [upstreamSource] 
/// * [weatherFitScore] 
/// * [weatherIcon] 
/// * [weatherOutdoorStatus] 
/// * [weatherTemp] 
@BuiltValue()
abstract class DocentScriptRequest implements Built<DocentScriptRequest, DocentScriptRequestBuilder> {
  @BuiltValueField(wireName: r'address')
  String? get address;

  @BuiltValueField(wireName: r'category')
  DocentScriptRequestCategoryEnum get category;
  // enum categoryEnum {  attraction,  restaurant,  event,  culture_venue,  };

  @BuiltValueField(wireName: r'culture_relevance_score')
  num? get cultureRelevanceScore;

  @BuiltValueField(wireName: r'demand_dispersion_score')
  num? get demandDispersionScore;

  @BuiltValueField(wireName: r'distance_m')
  int? get distanceM;

  @BuiltValueField(wireName: r'dust_grade')
  String? get dustGrade;

  @BuiltValueField(wireName: r'dust_pm10')
  String? get dustPm10;

  @BuiltValueField(wireName: r'dust_pm10_grade')
  String? get dustPm10Grade;

  @BuiltValueField(wireName: r'dust_pm25')
  String? get dustPm25;

  @BuiltValueField(wireName: r'dust_pm25_grade')
  String? get dustPm25Grade;

  @BuiltValueField(wireName: r'final_score')
  num? get finalScore;

  @BuiltValueField(wireName: r'language')
  String? get language;

  @BuiltValueField(wireName: r'local_spending_score')
  num? get localSpendingScore;

  @BuiltValueField(wireName: r'mode')
  String? get mode;

  @BuiltValueField(wireName: r'place_id')
  String get placeId;

  @BuiltValueField(wireName: r'place_name')
  String? get placeName;

  @BuiltValueField(wireName: r'region_en')
  String? get regionEn;

  @BuiltValueField(wireName: r'region_ko')
  String? get regionKo;

  @BuiltValueField(wireName: r'small_merchant_fit_score')
  num? get smallMerchantFitScore;

  @BuiltValueField(wireName: r'source')
  String? get source_;

  @BuiltValueField(wireName: r'upstream_source')
  String? get upstreamSource;

  @BuiltValueField(wireName: r'weather_fit_score')
  num? get weatherFitScore;

  @BuiltValueField(wireName: r'weather_icon')
  String? get weatherIcon;

  @BuiltValueField(wireName: r'weather_outdoor_status')
  String? get weatherOutdoorStatus;

  @BuiltValueField(wireName: r'weather_temp')
  String? get weatherTemp;

  DocentScriptRequest._();

  factory DocentScriptRequest([void updates(DocentScriptRequestBuilder b)]) = _$DocentScriptRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DocentScriptRequestBuilder b) => b
      ..language = 'ko'
      ..mode = 'brief';

  @BuiltValueSerializer(custom: true)
  static Serializer<DocentScriptRequest> get serializer => _$DocentScriptRequestSerializer();
}

class _$DocentScriptRequestSerializer implements PrimitiveSerializer<DocentScriptRequest> {
  @override
  final Iterable<Type> types = const [DocentScriptRequest, _$DocentScriptRequest];

  @override
  final String wireName = r'DocentScriptRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DocentScriptRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.address != null) {
      yield r'address';
      yield serializers.serialize(
        object.address,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'category';
    yield serializers.serialize(
      object.category,
      specifiedType: const FullType(DocentScriptRequestCategoryEnum),
    );
    if (object.cultureRelevanceScore != null) {
      yield r'culture_relevance_score';
      yield serializers.serialize(
        object.cultureRelevanceScore,
        specifiedType: const FullType.nullable(num),
      );
    }
    if (object.demandDispersionScore != null) {
      yield r'demand_dispersion_score';
      yield serializers.serialize(
        object.demandDispersionScore,
        specifiedType: const FullType.nullable(num),
      );
    }
    if (object.distanceM != null) {
      yield r'distance_m';
      yield serializers.serialize(
        object.distanceM,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.dustGrade != null) {
      yield r'dust_grade';
      yield serializers.serialize(
        object.dustGrade,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.dustPm10 != null) {
      yield r'dust_pm10';
      yield serializers.serialize(
        object.dustPm10,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.dustPm10Grade != null) {
      yield r'dust_pm10_grade';
      yield serializers.serialize(
        object.dustPm10Grade,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.dustPm25 != null) {
      yield r'dust_pm25';
      yield serializers.serialize(
        object.dustPm25,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.dustPm25Grade != null) {
      yield r'dust_pm25_grade';
      yield serializers.serialize(
        object.dustPm25Grade,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.finalScore != null) {
      yield r'final_score';
      yield serializers.serialize(
        object.finalScore,
        specifiedType: const FullType.nullable(num),
      );
    }
    if (object.language != null) {
      yield r'language';
      yield serializers.serialize(
        object.language,
        specifiedType: const FullType(String),
      );
    }
    if (object.localSpendingScore != null) {
      yield r'local_spending_score';
      yield serializers.serialize(
        object.localSpendingScore,
        specifiedType: const FullType.nullable(num),
      );
    }
    if (object.mode != null) {
      yield r'mode';
      yield serializers.serialize(
        object.mode,
        specifiedType: const FullType(String),
      );
    }
    yield r'place_id';
    yield serializers.serialize(
      object.placeId,
      specifiedType: const FullType(String),
    );
    if (object.placeName != null) {
      yield r'place_name';
      yield serializers.serialize(
        object.placeName,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.regionEn != null) {
      yield r'region_en';
      yield serializers.serialize(
        object.regionEn,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.regionKo != null) {
      yield r'region_ko';
      yield serializers.serialize(
        object.regionKo,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.smallMerchantFitScore != null) {
      yield r'small_merchant_fit_score';
      yield serializers.serialize(
        object.smallMerchantFitScore,
        specifiedType: const FullType.nullable(num),
      );
    }
    if (object.source_ != null) {
      yield r'source';
      yield serializers.serialize(
        object.source_,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.upstreamSource != null) {
      yield r'upstream_source';
      yield serializers.serialize(
        object.upstreamSource,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.weatherFitScore != null) {
      yield r'weather_fit_score';
      yield serializers.serialize(
        object.weatherFitScore,
        specifiedType: const FullType.nullable(num),
      );
    }
    if (object.weatherIcon != null) {
      yield r'weather_icon';
      yield serializers.serialize(
        object.weatherIcon,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.weatherOutdoorStatus != null) {
      yield r'weather_outdoor_status';
      yield serializers.serialize(
        object.weatherOutdoorStatus,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.weatherTemp != null) {
      yield r'weather_temp';
      yield serializers.serialize(
        object.weatherTemp,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DocentScriptRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DocentScriptRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'address':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.address = valueDes;
          break;
        case r'category':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DocentScriptRequestCategoryEnum),
          ) as DocentScriptRequestCategoryEnum;
          result.category = valueDes;
          break;
        case r'culture_relevance_score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(num),
          ) as num?;
          if (valueDes == null) continue;
          result.cultureRelevanceScore = valueDes;
          break;
        case r'demand_dispersion_score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(num),
          ) as num?;
          if (valueDes == null) continue;
          result.demandDispersionScore = valueDes;
          break;
        case r'distance_m':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.distanceM = valueDes;
          break;
        case r'dust_grade':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.dustGrade = valueDes;
          break;
        case r'dust_pm10':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.dustPm10 = valueDes;
          break;
        case r'dust_pm10_grade':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.dustPm10Grade = valueDes;
          break;
        case r'dust_pm25':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.dustPm25 = valueDes;
          break;
        case r'dust_pm25_grade':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.dustPm25Grade = valueDes;
          break;
        case r'final_score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(num),
          ) as num?;
          if (valueDes == null) continue;
          result.finalScore = valueDes;
          break;
        case r'language':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.language = valueDes;
          break;
        case r'local_spending_score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(num),
          ) as num?;
          if (valueDes == null) continue;
          result.localSpendingScore = valueDes;
          break;
        case r'mode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.mode = valueDes;
          break;
        case r'place_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.placeId = valueDes;
          break;
        case r'place_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.placeName = valueDes;
          break;
        case r'region_en':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.regionEn = valueDes;
          break;
        case r'region_ko':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.regionKo = valueDes;
          break;
        case r'small_merchant_fit_score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(num),
          ) as num?;
          if (valueDes == null) continue;
          result.smallMerchantFitScore = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.source_ = valueDes;
          break;
        case r'upstream_source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.upstreamSource = valueDes;
          break;
        case r'weather_fit_score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(num),
          ) as num?;
          if (valueDes == null) continue;
          result.weatherFitScore = valueDes;
          break;
        case r'weather_icon':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.weatherIcon = valueDes;
          break;
        case r'weather_outdoor_status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.weatherOutdoorStatus = valueDes;
          break;
        case r'weather_temp':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.weatherTemp = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DocentScriptRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DocentScriptRequestBuilder();
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

class DocentScriptRequestCategoryEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'attraction')
  static const DocentScriptRequestCategoryEnum attraction = _$docentScriptRequestCategoryEnum_attraction;
  @BuiltValueEnumConst(wireName: r'restaurant')
  static const DocentScriptRequestCategoryEnum restaurant = _$docentScriptRequestCategoryEnum_restaurant;
  @BuiltValueEnumConst(wireName: r'event')
  static const DocentScriptRequestCategoryEnum event = _$docentScriptRequestCategoryEnum_event;
  @BuiltValueEnumConst(wireName: r'culture_venue')
  static const DocentScriptRequestCategoryEnum cultureVenue = _$docentScriptRequestCategoryEnum_cultureVenue;

  static Serializer<DocentScriptRequestCategoryEnum> get serializer => _$docentScriptRequestCategoryEnumSerializer;

  const DocentScriptRequestCategoryEnum._(String name): super(name);

  static BuiltSet<DocentScriptRequestCategoryEnum> get values => _$docentScriptRequestCategoryEnumValues;
  static DocentScriptRequestCategoryEnum valueOf(String name) => _$docentScriptRequestCategoryEnumValueOf(name);
}

