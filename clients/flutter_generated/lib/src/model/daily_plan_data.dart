//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:lala_next_flutter_client_generated/src/model/coordinate.dart';
import 'package:lala_next_flutter_client_generated/src/model/daily_plan_slot.dart';
import 'package:built_collection/built_collection.dart';
import 'package:lala_next_flutter_client_generated/src/model/weather_data.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'daily_plan_data.g.dart';

/// DailyPlanData
///
/// Properties:
/// * [cacheKey] 
/// * [center] 
/// * [language] 
/// * [radiusM] 
/// * [requestHash] 
/// * [slots] 
/// * [source_] 
/// * [weather] 
@BuiltValue()
abstract class DailyPlanData implements Built<DailyPlanData, DailyPlanDataBuilder> {
  @BuiltValueField(wireName: r'cache_key')
  String get cacheKey;

  @BuiltValueField(wireName: r'center')
  Coordinate get center;

  @BuiltValueField(wireName: r'language')
  DailyPlanDataLanguageEnum get language;
  // enum languageEnum {  ko,  en,  };

  @BuiltValueField(wireName: r'radius_m')
  int get radiusM;

  @BuiltValueField(wireName: r'request_hash')
  String get requestHash;

  @BuiltValueField(wireName: r'slots')
  BuiltList<DailyPlanSlot> get slots;

  @BuiltValueField(wireName: r'source')
  DailyPlanDataSource_Enum get source_;
  // enum source_Enum {  unavailable,  public_mvp_snapshot,  db,  mixed,  };

  @BuiltValueField(wireName: r'weather')
  WeatherData get weather;

  DailyPlanData._();

  factory DailyPlanData([void updates(DailyPlanDataBuilder b)]) = _$DailyPlanData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DailyPlanDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DailyPlanData> get serializer => _$DailyPlanDataSerializer();
}

class _$DailyPlanDataSerializer implements PrimitiveSerializer<DailyPlanData> {
  @override
  final Iterable<Type> types = const [DailyPlanData, _$DailyPlanData];

  @override
  final String wireName = r'DailyPlanData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DailyPlanData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'cache_key';
    yield serializers.serialize(
      object.cacheKey,
      specifiedType: const FullType(String),
    );
    yield r'center';
    yield serializers.serialize(
      object.center,
      specifiedType: const FullType(Coordinate),
    );
    yield r'language';
    yield serializers.serialize(
      object.language,
      specifiedType: const FullType(DailyPlanDataLanguageEnum),
    );
    yield r'radius_m';
    yield serializers.serialize(
      object.radiusM,
      specifiedType: const FullType(int),
    );
    yield r'request_hash';
    yield serializers.serialize(
      object.requestHash,
      specifiedType: const FullType(String),
    );
    yield r'slots';
    yield serializers.serialize(
      object.slots,
      specifiedType: const FullType(BuiltList, [FullType(DailyPlanSlot)]),
    );
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(DailyPlanDataSource_Enum),
    );
    yield r'weather';
    yield serializers.serialize(
      object.weather,
      specifiedType: const FullType(WeatherData),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DailyPlanData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DailyPlanDataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'cache_key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cacheKey = valueDes;
          break;
        case r'center':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Coordinate),
          ) as Coordinate;
          result.center = valueDes.toBuilder();
          break;
        case r'language':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DailyPlanDataLanguageEnum),
          ) as DailyPlanDataLanguageEnum;
          result.language = valueDes;
          break;
        case r'radius_m':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.radiusM = valueDes;
          break;
        case r'request_hash':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.requestHash = valueDes;
          break;
        case r'slots':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(DailyPlanSlot)]),
          ) as BuiltList<DailyPlanSlot>;
          result.slots.replace(valueDes);
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DailyPlanDataSource_Enum),
          ) as DailyPlanDataSource_Enum;
          result.source_ = valueDes;
          break;
        case r'weather':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(WeatherData),
          ) as WeatherData;
          result.weather = valueDes.toBuilder();
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DailyPlanData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DailyPlanDataBuilder();
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

class DailyPlanDataLanguageEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'ko')
  static const DailyPlanDataLanguageEnum ko = _$dailyPlanDataLanguageEnum_ko;
  @BuiltValueEnumConst(wireName: r'en')
  static const DailyPlanDataLanguageEnum en = _$dailyPlanDataLanguageEnum_en;

  static Serializer<DailyPlanDataLanguageEnum> get serializer => _$dailyPlanDataLanguageEnumSerializer;

  const DailyPlanDataLanguageEnum._(String name): super(name);

  static BuiltSet<DailyPlanDataLanguageEnum> get values => _$dailyPlanDataLanguageEnumValues;
  static DailyPlanDataLanguageEnum valueOf(String name) => _$dailyPlanDataLanguageEnumValueOf(name);
}

class DailyPlanDataSource_Enum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'unavailable')
  static const DailyPlanDataSource_Enum unavailable = _$dailyPlanDataSourceEnum_unavailable;
  @BuiltValueEnumConst(wireName: r'public_mvp_snapshot')
  static const DailyPlanDataSource_Enum publicMvpSnapshot = _$dailyPlanDataSourceEnum_publicMvpSnapshot;
  @BuiltValueEnumConst(wireName: r'db')
  static const DailyPlanDataSource_Enum db = _$dailyPlanDataSourceEnum_db;
  @BuiltValueEnumConst(wireName: r'mixed')
  static const DailyPlanDataSource_Enum mixed = _$dailyPlanDataSourceEnum_mixed;

  static Serializer<DailyPlanDataSource_Enum> get serializer => _$dailyPlanDataSourceEnumSerializer;

  const DailyPlanDataSource_Enum._(String name): super(name);

  static BuiltSet<DailyPlanDataSource_Enum> get values => _$dailyPlanDataSourceEnumValues;
  static DailyPlanDataSource_Enum valueOf(String name) => _$dailyPlanDataSourceEnumValueOf(name);
}

