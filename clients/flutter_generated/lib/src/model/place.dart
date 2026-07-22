//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:lala_next_flutter_client_generated/src/model/date.dart';
import 'package:lala_next_flutter_client_generated/src/model/place_score.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'place.g.dart';

/// Place
///
/// Properties:
/// * [address] 
/// * [category] 
/// * [distanceM] 
/// * [eventEndDate] 
/// * [eventStartDate] 
/// * [eventUrl] 
/// * [imageUrl] 
/// * [isApproximateLocation] 
/// * [isOngoing] 
/// * [lat] 
/// * [lng] 
/// * [name] 
/// * [nameEn] 
/// * [nameKo] 
/// * [placeId] 
/// * [regionEn] 
/// * [regionKo] 
/// * [score] 
/// * [source_] 
/// * [upstreamSource] 
@BuiltValue()
abstract class Place implements Built<Place, PlaceBuilder> {
  @BuiltValueField(wireName: r'address')
  String? get address;

  @BuiltValueField(wireName: r'category')
  PlaceCategoryEnum get category;
  // enum categoryEnum {  attraction,  restaurant,  event,  culture_venue,  };

  @BuiltValueField(wireName: r'distance_m')
  int get distanceM;

  @BuiltValueField(wireName: r'event_end_date')
  Date? get eventEndDate;

  @BuiltValueField(wireName: r'event_start_date')
  Date? get eventStartDate;

  @BuiltValueField(wireName: r'event_url')
  String? get eventUrl;

  @BuiltValueField(wireName: r'image_url')
  String? get imageUrl;

  @BuiltValueField(wireName: r'is_approximate_location')
  bool? get isApproximateLocation;

  @BuiltValueField(wireName: r'is_ongoing')
  bool? get isOngoing;

  @BuiltValueField(wireName: r'lat')
  double get lat;

  @BuiltValueField(wireName: r'lng')
  double get lng;

  @BuiltValueField(wireName: r'name')
  String? get name;

  @BuiltValueField(wireName: r'name_en')
  String? get nameEn;

  @BuiltValueField(wireName: r'name_ko')
  String? get nameKo;

  @BuiltValueField(wireName: r'place_id')
  String? get placeId;

  @BuiltValueField(wireName: r'region_en')
  String? get regionEn;

  @BuiltValueField(wireName: r'region_ko')
  String? get regionKo;

  @BuiltValueField(wireName: r'score')
  PlaceScore? get score;

  @BuiltValueField(wireName: r'source')
  PlaceSource_Enum get source_;
  // enum source_Enum {  public_mvp_snapshot,  db,  };

  @BuiltValueField(wireName: r'upstream_source')
  String? get upstreamSource;

  Place._();

  factory Place([void updates(PlaceBuilder b)]) = _$Place;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlaceBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Place> get serializer => _$PlaceSerializer();
}

class _$PlaceSerializer implements PrimitiveSerializer<Place> {
  @override
  final Iterable<Type> types = const [Place, _$Place];

  @override
  final String wireName = r'Place';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Place object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'address';
    yield object.address == null ? null : serializers.serialize(
      object.address,
      specifiedType: const FullType.nullable(String),
    );
    yield r'category';
    yield serializers.serialize(
      object.category,
      specifiedType: const FullType(PlaceCategoryEnum),
    );
    yield r'distance_m';
    yield serializers.serialize(
      object.distanceM,
      specifiedType: const FullType(int),
    );
    if (object.eventEndDate != null) {
      yield r'event_end_date';
      yield serializers.serialize(
        object.eventEndDate,
        specifiedType: const FullType(Date),
      );
    }
    if (object.eventStartDate != null) {
      yield r'event_start_date';
      yield serializers.serialize(
        object.eventStartDate,
        specifiedType: const FullType(Date),
      );
    }
    if (object.eventUrl != null) {
      yield r'event_url';
      yield serializers.serialize(
        object.eventUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.imageUrl != null) {
      yield r'image_url';
      yield serializers.serialize(
        object.imageUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.isApproximateLocation != null) {
      yield r'is_approximate_location';
      yield serializers.serialize(
        object.isApproximateLocation,
        specifiedType: const FullType(bool),
      );
    }
    if (object.isOngoing != null) {
      yield r'is_ongoing';
      yield serializers.serialize(
        object.isOngoing,
        specifiedType: const FullType(bool),
      );
    }
    yield r'lat';
    yield serializers.serialize(
      object.lat,
      specifiedType: const FullType(double),
    );
    yield r'lng';
    yield serializers.serialize(
      object.lng,
      specifiedType: const FullType(double),
    );
    yield r'name';
    yield object.name == null ? null : serializers.serialize(
      object.name,
      specifiedType: const FullType.nullable(String),
    );
    if (object.nameEn != null) {
      yield r'name_en';
      yield serializers.serialize(
        object.nameEn,
        specifiedType: const FullType(String),
      );
    }
    if (object.nameKo != null) {
      yield r'name_ko';
      yield serializers.serialize(
        object.nameKo,
        specifiedType: const FullType(String),
      );
    }
    yield r'place_id';
    yield object.placeId == null ? null : serializers.serialize(
      object.placeId,
      specifiedType: const FullType.nullable(String),
    );
    if (object.regionEn != null) {
      yield r'region_en';
      yield serializers.serialize(
        object.regionEn,
        specifiedType: const FullType(String),
      );
    }
    if (object.regionKo != null) {
      yield r'region_ko';
      yield serializers.serialize(
        object.regionKo,
        specifiedType: const FullType(String),
      );
    }
    if (object.score != null) {
      yield r'score';
      yield serializers.serialize(
        object.score,
        specifiedType: const FullType(PlaceScore),
      );
    }
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(PlaceSource_Enum),
    );
    if (object.upstreamSource != null) {
      yield r'upstream_source';
      yield serializers.serialize(
        object.upstreamSource,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Place object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PlaceBuilder result,
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
            specifiedType: const FullType(PlaceCategoryEnum),
          ) as PlaceCategoryEnum;
          result.category = valueDes;
          break;
        case r'distance_m':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.distanceM = valueDes;
          break;
        case r'event_end_date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.eventEndDate = valueDes;
          break;
        case r'event_start_date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.eventStartDate = valueDes;
          break;
        case r'event_url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.eventUrl = valueDes;
          break;
        case r'image_url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.imageUrl = valueDes;
          break;
        case r'is_approximate_location':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isApproximateLocation = valueDes;
          break;
        case r'is_ongoing':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isOngoing = valueDes;
          break;
        case r'lat':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.lat = valueDes;
          break;
        case r'lng':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.lng = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.name = valueDes;
          break;
        case r'name_en':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nameEn = valueDes;
          break;
        case r'name_ko':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nameKo = valueDes;
          break;
        case r'place_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.placeId = valueDes;
          break;
        case r'region_en':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.regionEn = valueDes;
          break;
        case r'region_ko':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.regionKo = valueDes;
          break;
        case r'score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlaceScore),
          ) as PlaceScore;
          result.score = valueDes.toBuilder();
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PlaceSource_Enum),
          ) as PlaceSource_Enum;
          result.source_ = valueDes;
          break;
        case r'upstream_source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.upstreamSource = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Place deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlaceBuilder();
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

class PlaceCategoryEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'attraction')
  static const PlaceCategoryEnum attraction = _$placeCategoryEnum_attraction;
  @BuiltValueEnumConst(wireName: r'restaurant')
  static const PlaceCategoryEnum restaurant = _$placeCategoryEnum_restaurant;
  @BuiltValueEnumConst(wireName: r'event')
  static const PlaceCategoryEnum event = _$placeCategoryEnum_event;
  @BuiltValueEnumConst(wireName: r'culture_venue')
  static const PlaceCategoryEnum cultureVenue = _$placeCategoryEnum_cultureVenue;

  static Serializer<PlaceCategoryEnum> get serializer => _$placeCategoryEnumSerializer;

  const PlaceCategoryEnum._(String name): super(name);

  static BuiltSet<PlaceCategoryEnum> get values => _$placeCategoryEnumValues;
  static PlaceCategoryEnum valueOf(String name) => _$placeCategoryEnumValueOf(name);
}

class PlaceSource_Enum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'public_mvp_snapshot')
  static const PlaceSource_Enum publicMvpSnapshot = _$placeSourceEnum_publicMvpSnapshot;
  @BuiltValueEnumConst(wireName: r'db')
  static const PlaceSource_Enum db = _$placeSourceEnum_db;

  static Serializer<PlaceSource_Enum> get serializer => _$placeSourceEnumSerializer;

  const PlaceSource_Enum._(String name): super(name);

  static BuiltSet<PlaceSource_Enum> get values => _$placeSourceEnumValues;
  static PlaceSource_Enum valueOf(String name) => _$placeSourceEnumValueOf(name);
}

