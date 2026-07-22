//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:lala_next_flutter_client_generated/src/model/forecast_item.dart';
import 'package:built_collection/built_collection.dart';
import 'package:lala_next_flutter_client_generated/src/model/dust.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'weather_data.g.dart';

/// WeatherData
///
/// Properties:
/// * [dust] 
/// * [force] 
/// * [forecast] 
/// * [icon] 
/// * [lat] 
/// * [lng] 
/// * [location] 
/// * [locationMatch] 
/// * [outdoorStatus] 
/// * [recordTime] 
/// * [source_] 
/// * [temp] 
@BuiltValue()
abstract class WeatherData implements Built<WeatherData, WeatherDataBuilder> {
  @BuiltValueField(wireName: r'dust')
  Dust get dust;

  @BuiltValueField(wireName: r'force')
  bool get force;

  @BuiltValueField(wireName: r'forecast')
  BuiltList<ForecastItem> get forecast;

  @BuiltValueField(wireName: r'icon')
  String get icon;

  @BuiltValueField(wireName: r'lat')
  double get lat;

  @BuiltValueField(wireName: r'lng')
  double get lng;

  @BuiltValueField(wireName: r'location')
  String? get location;

  @BuiltValueField(wireName: r'location_match')
  bool? get locationMatch;

  @BuiltValueField(wireName: r'outdoor_status')
  WeatherDataOutdoorStatusEnum get outdoorStatus;
  // enum outdoorStatusEnum {  good,  bad,  unknown,  };

  @BuiltValueField(wireName: r'record_time')
  String? get recordTime;

  @BuiltValueField(wireName: r'source')
  WeatherDataSource_Enum get source_;
  // enum source_Enum {  db,  db+airkorea_sido_realtime,  kma_ultra_srt_ncst,  airkorea_sido_realtime,  kma_ultra_srt_ncst+airkorea_sido_realtime,  unavailable,  };

  @BuiltValueField(wireName: r'temp')
  String get temp;

  WeatherData._();

  factory WeatherData([void updates(WeatherDataBuilder b)]) = _$WeatherData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WeatherDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WeatherData> get serializer => _$WeatherDataSerializer();
}

class _$WeatherDataSerializer implements PrimitiveSerializer<WeatherData> {
  @override
  final Iterable<Type> types = const [WeatherData, _$WeatherData];

  @override
  final String wireName = r'WeatherData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WeatherData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'dust';
    yield serializers.serialize(
      object.dust,
      specifiedType: const FullType(Dust),
    );
    yield r'force';
    yield serializers.serialize(
      object.force,
      specifiedType: const FullType(bool),
    );
    yield r'forecast';
    yield serializers.serialize(
      object.forecast,
      specifiedType: const FullType(BuiltList, [FullType(ForecastItem)]),
    );
    yield r'icon';
    yield serializers.serialize(
      object.icon,
      specifiedType: const FullType(String),
    );
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
    if (object.location != null) {
      yield r'location';
      yield serializers.serialize(
        object.location,
        specifiedType: const FullType(String),
      );
    }
    if (object.locationMatch != null) {
      yield r'location_match';
      yield serializers.serialize(
        object.locationMatch,
        specifiedType: const FullType(bool),
      );
    }
    yield r'outdoor_status';
    yield serializers.serialize(
      object.outdoorStatus,
      specifiedType: const FullType(WeatherDataOutdoorStatusEnum),
    );
    if (object.recordTime != null) {
      yield r'record_time';
      yield serializers.serialize(
        object.recordTime,
        specifiedType: const FullType(String),
      );
    }
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(WeatherDataSource_Enum),
    );
    yield r'temp';
    yield serializers.serialize(
      object.temp,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    WeatherData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WeatherDataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'dust':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Dust),
          ) as Dust;
          result.dust = valueDes.toBuilder();
          break;
        case r'force':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.force = valueDes;
          break;
        case r'forecast':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ForecastItem)]),
          ) as BuiltList<ForecastItem>;
          result.forecast.replace(valueDes);
          break;
        case r'icon':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.icon = valueDes;
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
        case r'location':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.location = valueDes;
          break;
        case r'location_match':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.locationMatch = valueDes;
          break;
        case r'outdoor_status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(WeatherDataOutdoorStatusEnum),
          ) as WeatherDataOutdoorStatusEnum;
          result.outdoorStatus = valueDes;
          break;
        case r'record_time':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.recordTime = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(WeatherDataSource_Enum),
          ) as WeatherDataSource_Enum;
          result.source_ = valueDes;
          break;
        case r'temp':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.temp = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WeatherData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WeatherDataBuilder();
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

class WeatherDataOutdoorStatusEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'good')
  static const WeatherDataOutdoorStatusEnum good = _$weatherDataOutdoorStatusEnum_good;
  @BuiltValueEnumConst(wireName: r'bad')
  static const WeatherDataOutdoorStatusEnum bad = _$weatherDataOutdoorStatusEnum_bad;
  @BuiltValueEnumConst(wireName: r'unknown')
  static const WeatherDataOutdoorStatusEnum unknown = _$weatherDataOutdoorStatusEnum_unknown;

  static Serializer<WeatherDataOutdoorStatusEnum> get serializer => _$weatherDataOutdoorStatusEnumSerializer;

  const WeatherDataOutdoorStatusEnum._(String name): super(name);

  static BuiltSet<WeatherDataOutdoorStatusEnum> get values => _$weatherDataOutdoorStatusEnumValues;
  static WeatherDataOutdoorStatusEnum valueOf(String name) => _$weatherDataOutdoorStatusEnumValueOf(name);
}

class WeatherDataSource_Enum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'db')
  static const WeatherDataSource_Enum db = _$weatherDataSourceEnum_db;
  @BuiltValueEnumConst(wireName: r'db+airkorea_sido_realtime')
  static const WeatherDataSource_Enum dbPlusAirkoreaSidoRealtime = _$weatherDataSourceEnum_dbPlusAirkoreaSidoRealtime;
  @BuiltValueEnumConst(wireName: r'kma_ultra_srt_ncst')
  static const WeatherDataSource_Enum kmaUltraSrtNcst = _$weatherDataSourceEnum_kmaUltraSrtNcst;
  @BuiltValueEnumConst(wireName: r'airkorea_sido_realtime')
  static const WeatherDataSource_Enum airkoreaSidoRealtime = _$weatherDataSourceEnum_airkoreaSidoRealtime;
  @BuiltValueEnumConst(wireName: r'kma_ultra_srt_ncst+airkorea_sido_realtime')
  static const WeatherDataSource_Enum kmaUltraSrtNcstPlusAirkoreaSidoRealtime = _$weatherDataSourceEnum_kmaUltraSrtNcstPlusAirkoreaSidoRealtime;
  @BuiltValueEnumConst(wireName: r'unavailable')
  static const WeatherDataSource_Enum unavailable = _$weatherDataSourceEnum_unavailable;

  static Serializer<WeatherDataSource_Enum> get serializer => _$weatherDataSourceEnumSerializer;

  const WeatherDataSource_Enum._(String name): super(name);

  static BuiltSet<WeatherDataSource_Enum> get values => _$weatherDataSourceEnumValues;
  static WeatherDataSource_Enum valueOf(String name) => _$weatherDataSourceEnumValueOf(name);
}

