//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'places_query.g.dart';

/// PlacesQuery
///
/// Properties:
/// * [category] 
/// * [includeScores] 
/// * [language] 
/// * [lat] 
/// * [limit] 
/// * [lng] 
/// * [radiusM] 
@BuiltValue()
abstract class PlacesQuery implements Built<PlacesQuery, PlacesQueryBuilder> {
  @BuiltValueField(wireName: r'category')
  PlacesQueryCategoryEnum get category;
  // enum categoryEnum {  all,  attraction,  restaurant,  event,  culture_venue,  };

  @BuiltValueField(wireName: r'include_scores')
  bool get includeScores;

  @BuiltValueField(wireName: r'language')
  PlacesQueryLanguageEnum get language;
  // enum languageEnum {  ko,  en,  };

  @BuiltValueField(wireName: r'lat')
  double get lat;

  @BuiltValueField(wireName: r'limit')
  int get limit;

  @BuiltValueField(wireName: r'lng')
  double get lng;

  @BuiltValueField(wireName: r'radius_m')
  int get radiusM;

  PlacesQuery._();

  factory PlacesQuery([void updates(PlacesQueryBuilder b)]) = _$PlacesQuery;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlacesQueryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlacesQuery> get serializer => _$PlacesQuerySerializer();
}

class _$PlacesQuerySerializer implements PrimitiveSerializer<PlacesQuery> {
  @override
  final Iterable<Type> types = const [PlacesQuery, _$PlacesQuery];

  @override
  final String wireName = r'PlacesQuery';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlacesQuery object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'category';
    yield serializers.serialize(
      object.category,
      specifiedType: const FullType(PlacesQueryCategoryEnum),
    );
    yield r'include_scores';
    yield serializers.serialize(
      object.includeScores,
      specifiedType: const FullType(bool),
    );
    yield r'language';
    yield serializers.serialize(
      object.language,
      specifiedType: const FullType(PlacesQueryLanguageEnum),
    );
    yield r'lat';
    yield serializers.serialize(
      object.lat,
      specifiedType: const FullType(double),
    );
    yield r'limit';
    yield serializers.serialize(
      object.limit,
      specifiedType: const FullType(int),
    );
    yield r'lng';
    yield serializers.serialize(
      object.lng,
      specifiedType: const FullType(double),
    );
    yield r'radius_m';
    yield serializers.serialize(
      object.radiusM,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlacesQuery object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlacesQueryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'category':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlacesQueryCategoryEnum),
          ) as PlacesQueryCategoryEnum;
          result.category = valueDes;
          break;
        case r'include_scores':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.includeScores = valueDes;
          break;
        case r'language':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlacesQueryLanguageEnum),
          ) as PlacesQueryLanguageEnum;
          result.language = valueDes;
          break;
        case r'lat':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.lat = valueDes;
          break;
        case r'limit':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.limit = valueDes;
          break;
        case r'lng':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
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
  PlacesQuery deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlacesQueryBuilder();
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

class PlacesQueryCategoryEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'all')
  static const PlacesQueryCategoryEnum all = _$placesQueryCategoryEnum_all;
  @BuiltValueEnumConst(wireName: r'attraction')
  static const PlacesQueryCategoryEnum attraction = _$placesQueryCategoryEnum_attraction;
  @BuiltValueEnumConst(wireName: r'restaurant')
  static const PlacesQueryCategoryEnum restaurant = _$placesQueryCategoryEnum_restaurant;
  @BuiltValueEnumConst(wireName: r'event')
  static const PlacesQueryCategoryEnum event = _$placesQueryCategoryEnum_event;
  @BuiltValueEnumConst(wireName: r'culture_venue')
  static const PlacesQueryCategoryEnum cultureVenue = _$placesQueryCategoryEnum_cultureVenue;

  static Serializer<PlacesQueryCategoryEnum> get serializer => _$placesQueryCategoryEnumSerializer;

  const PlacesQueryCategoryEnum._(String name): super(name);

  static BuiltSet<PlacesQueryCategoryEnum> get values => _$placesQueryCategoryEnumValues;
  static PlacesQueryCategoryEnum valueOf(String name) => _$placesQueryCategoryEnumValueOf(name);
}

class PlacesQueryLanguageEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'ko')
  static const PlacesQueryLanguageEnum ko = _$placesQueryLanguageEnum_ko;
  @BuiltValueEnumConst(wireName: r'en')
  static const PlacesQueryLanguageEnum en = _$placesQueryLanguageEnum_en;

  static Serializer<PlacesQueryLanguageEnum> get serializer => _$placesQueryLanguageEnumSerializer;

  const PlacesQueryLanguageEnum._(String name): super(name);

  static BuiltSet<PlacesQueryLanguageEnum> get values => _$placesQueryLanguageEnumValues;
  static PlacesQueryLanguageEnum valueOf(String name) => _$placesQueryLanguageEnumValueOf(name);
}

