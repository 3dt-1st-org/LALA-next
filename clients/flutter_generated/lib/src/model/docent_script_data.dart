//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'docent_script_data.g.dart';

/// DocentScriptData
///
/// Properties:
/// * [cacheKey] 
/// * [category] 
/// * [generatedAt] 
/// * [groundingCount] 
/// * [groundingSources] 
/// * [language] 
/// * [mode] 
/// * [placeId] 
/// * [requestHash] 
/// * [script] 
/// * [source_] 
/// * [ttlSec] 
@BuiltValue()
abstract class DocentScriptData implements Built<DocentScriptData, DocentScriptDataBuilder> {
  @BuiltValueField(wireName: r'cache_key')
  String get cacheKey;

  @BuiltValueField(wireName: r'category')
  DocentScriptDataCategoryEnum get category;
  // enum categoryEnum {  attraction,  restaurant,  event,  culture_venue,  };

  @BuiltValueField(wireName: r'generated_at')
  String? get generatedAt;

  @BuiltValueField(wireName: r'grounding_count')
  int? get groundingCount;

  @BuiltValueField(wireName: r'grounding_sources')
  BuiltList<String>? get groundingSources;

  @BuiltValueField(wireName: r'language')
  DocentScriptDataLanguageEnum get language;
  // enum languageEnum {  ko,  en,  };

  @BuiltValueField(wireName: r'mode')
  DocentScriptDataModeEnum get mode;
  // enum modeEnum {  brief,  detail,  };

  @BuiltValueField(wireName: r'place_id')
  String get placeId;

  @BuiltValueField(wireName: r'request_hash')
  String get requestHash;

  @BuiltValueField(wireName: r'script')
  String get script;

  @BuiltValueField(wireName: r'source')
  DocentScriptDataSource_Enum get source_;
  // enum source_Enum {  rule_based_curation,  db_cache,  azure_openai,  };

  @BuiltValueField(wireName: r'ttl_sec')
  int? get ttlSec;

  DocentScriptData._();

  factory DocentScriptData([void updates(DocentScriptDataBuilder b)]) = _$DocentScriptData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DocentScriptDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DocentScriptData> get serializer => _$DocentScriptDataSerializer();
}

class _$DocentScriptDataSerializer implements PrimitiveSerializer<DocentScriptData> {
  @override
  final Iterable<Type> types = const [DocentScriptData, _$DocentScriptData];

  @override
  final String wireName = r'DocentScriptData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DocentScriptData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'cache_key';
    yield serializers.serialize(
      object.cacheKey,
      specifiedType: const FullType(String),
    );
    yield r'category';
    yield serializers.serialize(
      object.category,
      specifiedType: const FullType(DocentScriptDataCategoryEnum),
    );
    if (object.generatedAt != null) {
      yield r'generated_at';
      yield serializers.serialize(
        object.generatedAt,
        specifiedType: const FullType(String),
      );
    }
    if (object.groundingCount != null) {
      yield r'grounding_count';
      yield serializers.serialize(
        object.groundingCount,
        specifiedType: const FullType(int),
      );
    }
    if (object.groundingSources != null) {
      yield r'grounding_sources';
      yield serializers.serialize(
        object.groundingSources,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    yield r'language';
    yield serializers.serialize(
      object.language,
      specifiedType: const FullType(DocentScriptDataLanguageEnum),
    );
    yield r'mode';
    yield serializers.serialize(
      object.mode,
      specifiedType: const FullType(DocentScriptDataModeEnum),
    );
    yield r'place_id';
    yield serializers.serialize(
      object.placeId,
      specifiedType: const FullType(String),
    );
    yield r'request_hash';
    yield serializers.serialize(
      object.requestHash,
      specifiedType: const FullType(String),
    );
    yield r'script';
    yield serializers.serialize(
      object.script,
      specifiedType: const FullType(String),
    );
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(DocentScriptDataSource_Enum),
    );
    if (object.ttlSec != null) {
      yield r'ttl_sec';
      yield serializers.serialize(
        object.ttlSec,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DocentScriptData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DocentScriptDataBuilder result,
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
        case r'category':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DocentScriptDataCategoryEnum),
          ) as DocentScriptDataCategoryEnum;
          result.category = valueDes;
          break;
        case r'generated_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.generatedAt = valueDes;
          break;
        case r'grounding_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.groundingCount = valueDes;
          break;
        case r'grounding_sources':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.groundingSources.replace(valueDes);
          break;
        case r'language':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DocentScriptDataLanguageEnum),
          ) as DocentScriptDataLanguageEnum;
          result.language = valueDes;
          break;
        case r'mode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DocentScriptDataModeEnum),
          ) as DocentScriptDataModeEnum;
          result.mode = valueDes;
          break;
        case r'place_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.placeId = valueDes;
          break;
        case r'request_hash':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.requestHash = valueDes;
          break;
        case r'script':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.script = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DocentScriptDataSource_Enum),
          ) as DocentScriptDataSource_Enum;
          result.source_ = valueDes;
          break;
        case r'ttl_sec':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.ttlSec = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DocentScriptData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DocentScriptDataBuilder();
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

class DocentScriptDataCategoryEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'attraction')
  static const DocentScriptDataCategoryEnum attraction = _$docentScriptDataCategoryEnum_attraction;
  @BuiltValueEnumConst(wireName: r'restaurant')
  static const DocentScriptDataCategoryEnum restaurant = _$docentScriptDataCategoryEnum_restaurant;
  @BuiltValueEnumConst(wireName: r'event')
  static const DocentScriptDataCategoryEnum event = _$docentScriptDataCategoryEnum_event;
  @BuiltValueEnumConst(wireName: r'culture_venue')
  static const DocentScriptDataCategoryEnum cultureVenue = _$docentScriptDataCategoryEnum_cultureVenue;

  static Serializer<DocentScriptDataCategoryEnum> get serializer => _$docentScriptDataCategoryEnumSerializer;

  const DocentScriptDataCategoryEnum._(String name): super(name);

  static BuiltSet<DocentScriptDataCategoryEnum> get values => _$docentScriptDataCategoryEnumValues;
  static DocentScriptDataCategoryEnum valueOf(String name) => _$docentScriptDataCategoryEnumValueOf(name);
}

class DocentScriptDataLanguageEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'ko')
  static const DocentScriptDataLanguageEnum ko = _$docentScriptDataLanguageEnum_ko;
  @BuiltValueEnumConst(wireName: r'en')
  static const DocentScriptDataLanguageEnum en = _$docentScriptDataLanguageEnum_en;

  static Serializer<DocentScriptDataLanguageEnum> get serializer => _$docentScriptDataLanguageEnumSerializer;

  const DocentScriptDataLanguageEnum._(String name): super(name);

  static BuiltSet<DocentScriptDataLanguageEnum> get values => _$docentScriptDataLanguageEnumValues;
  static DocentScriptDataLanguageEnum valueOf(String name) => _$docentScriptDataLanguageEnumValueOf(name);
}

class DocentScriptDataModeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'brief')
  static const DocentScriptDataModeEnum brief = _$docentScriptDataModeEnum_brief;
  @BuiltValueEnumConst(wireName: r'detail')
  static const DocentScriptDataModeEnum detail = _$docentScriptDataModeEnum_detail;

  static Serializer<DocentScriptDataModeEnum> get serializer => _$docentScriptDataModeEnumSerializer;

  const DocentScriptDataModeEnum._(String name): super(name);

  static BuiltSet<DocentScriptDataModeEnum> get values => _$docentScriptDataModeEnumValues;
  static DocentScriptDataModeEnum valueOf(String name) => _$docentScriptDataModeEnumValueOf(name);
}

class DocentScriptDataSource_Enum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'rule_based_curation')
  static const DocentScriptDataSource_Enum ruleBasedCuration = _$docentScriptDataSourceEnum_ruleBasedCuration;
  @BuiltValueEnumConst(wireName: r'db_cache')
  static const DocentScriptDataSource_Enum dbCache = _$docentScriptDataSourceEnum_dbCache;
  @BuiltValueEnumConst(wireName: r'azure_openai')
  static const DocentScriptDataSource_Enum azureOpenai = _$docentScriptDataSourceEnum_azureOpenai;

  static Serializer<DocentScriptDataSource_Enum> get serializer => _$docentScriptDataSourceEnumSerializer;

  const DocentScriptDataSource_Enum._(String name): super(name);

  static BuiltSet<DocentScriptDataSource_Enum> get values => _$docentScriptDataSourceEnumValues;
  static DocentScriptDataSource_Enum valueOf(String name) => _$docentScriptDataSourceEnumValueOf(name);
}

