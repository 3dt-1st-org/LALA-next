//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:lala_next_flutter_client_generated/src/model/place.dart';
import 'package:lala_next_flutter_client_generated/src/model/places_query.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'places_data.g.dart';

/// PlacesData
///
/// Properties:
/// * [count] 
/// * [locationEngine] 
/// * [places] 
/// * [query] 
/// * [source_] 
@BuiltValue()
abstract class PlacesData implements Built<PlacesData, PlacesDataBuilder> {
  @BuiltValueField(wireName: r'count')
  int get count;

  @BuiltValueField(wireName: r'location_engine')
  PlacesDataLocationEngineEnum get locationEngine;
  // enum locationEngineEnum {  postgis,  static_snapshot,  none,  };

  @BuiltValueField(wireName: r'places')
  BuiltList<Place> get places;

  @BuiltValueField(wireName: r'query')
  PlacesQuery get query;

  @BuiltValueField(wireName: r'source')
  PlacesDataSource_Enum get source_;
  // enum source_Enum {  public_mvp_snapshot,  db,  };

  PlacesData._();

  factory PlacesData([void updates(PlacesDataBuilder b)]) = _$PlacesData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlacesDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlacesData> get serializer => _$PlacesDataSerializer();
}

class _$PlacesDataSerializer implements PrimitiveSerializer<PlacesData> {
  @override
  final Iterable<Type> types = const [PlacesData, _$PlacesData];

  @override
  final String wireName = r'PlacesData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlacesData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'count';
    yield serializers.serialize(
      object.count,
      specifiedType: const FullType(int),
    );
    yield r'location_engine';
    yield serializers.serialize(
      object.locationEngine,
      specifiedType: const FullType(PlacesDataLocationEngineEnum),
    );
    yield r'places';
    yield serializers.serialize(
      object.places,
      specifiedType: const FullType(BuiltList, [FullType(Place)]),
    );
    yield r'query';
    yield serializers.serialize(
      object.query,
      specifiedType: const FullType(PlacesQuery),
    );
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(PlacesDataSource_Enum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlacesData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlacesDataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.count = valueDes;
          break;
        case r'location_engine':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlacesDataLocationEngineEnum),
          ) as PlacesDataLocationEngineEnum;
          result.locationEngine = valueDes;
          break;
        case r'places':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Place)]),
          ) as BuiltList<Place>;
          result.places.replace(valueDes);
          break;
        case r'query':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlacesQuery),
          ) as PlacesQuery;
          result.query = valueDes.toBuilder();
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlacesDataSource_Enum),
          ) as PlacesDataSource_Enum;
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
  PlacesData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlacesDataBuilder();
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

class PlacesDataLocationEngineEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'postgis')
  static const PlacesDataLocationEngineEnum postgis = _$placesDataLocationEngineEnum_postgis;
  @BuiltValueEnumConst(wireName: r'static_snapshot')
  static const PlacesDataLocationEngineEnum staticSnapshot = _$placesDataLocationEngineEnum_staticSnapshot;
  @BuiltValueEnumConst(wireName: r'none')
  static const PlacesDataLocationEngineEnum none = _$placesDataLocationEngineEnum_none;

  static Serializer<PlacesDataLocationEngineEnum> get serializer => _$placesDataLocationEngineEnumSerializer;

  const PlacesDataLocationEngineEnum._(String name): super(name);

  static BuiltSet<PlacesDataLocationEngineEnum> get values => _$placesDataLocationEngineEnumValues;
  static PlacesDataLocationEngineEnum valueOf(String name) => _$placesDataLocationEngineEnumValueOf(name);
}

class PlacesDataSource_Enum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'public_mvp_snapshot')
  static const PlacesDataSource_Enum publicMvpSnapshot = _$placesDataSourceEnum_publicMvpSnapshot;
  @BuiltValueEnumConst(wireName: r'db')
  static const PlacesDataSource_Enum db = _$placesDataSourceEnum_db;

  static Serializer<PlacesDataSource_Enum> get serializer => _$placesDataSourceEnumSerializer;

  const PlacesDataSource_Enum._(String name): super(name);

  static BuiltSet<PlacesDataSource_Enum> get values => _$placesDataSourceEnumValues;
  static PlacesDataSource_Enum valueOf(String name) => _$placesDataSourceEnumValueOf(name);
}

