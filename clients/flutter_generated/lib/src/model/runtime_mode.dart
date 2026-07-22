//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'runtime_mode.g.dart';

/// RuntimeMode
///
/// Properties:
/// * [ai] 
/// * [data] 
/// * [overall] 
/// * [speech] 
/// * [worker] 
@BuiltValue()
abstract class RuntimeMode implements Built<RuntimeMode, RuntimeModeBuilder> {
  @BuiltValueField(wireName: r'ai')
  RuntimeModeAiEnum get ai;
  // enum aiEnum {  disabled,  live-azure,  degraded,  };

  @BuiltValueField(wireName: r'data')
  RuntimeModeDataEnum get data;
  // enum dataEnum {  unavailable,  public-cache,  db-backed,  degraded,  };

  @BuiltValueField(wireName: r'overall')
  RuntimeModeOverallEnum get overall;
  // enum overallEnum {  public-cache,  db-backed,  live-azure,  degraded,  };

  @BuiltValueField(wireName: r'speech')
  RuntimeModeSpeechEnum get speech;
  // enum speechEnum {  disabled,  live-azure,  degraded,  };

  @BuiltValueField(wireName: r'worker')
  RuntimeModeWorkerEnum get worker;
  // enum workerEnum {  dry-run,  degraded,  };

  RuntimeMode._();

  factory RuntimeMode([void updates(RuntimeModeBuilder b)]) = _$RuntimeMode;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RuntimeModeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RuntimeMode> get serializer => _$RuntimeModeSerializer();
}

class _$RuntimeModeSerializer implements PrimitiveSerializer<RuntimeMode> {
  @override
  final Iterable<Type> types = const [RuntimeMode, _$RuntimeMode];

  @override
  final String wireName = r'RuntimeMode';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RuntimeMode object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'ai';
    yield serializers.serialize(
      object.ai,
      specifiedType: const FullType(RuntimeModeAiEnum),
    );
    yield r'data';
    yield serializers.serialize(
      object.data,
      specifiedType: const FullType(RuntimeModeDataEnum),
    );
    yield r'overall';
    yield serializers.serialize(
      object.overall,
      specifiedType: const FullType(RuntimeModeOverallEnum),
    );
    yield r'speech';
    yield serializers.serialize(
      object.speech,
      specifiedType: const FullType(RuntimeModeSpeechEnum),
    );
    yield r'worker';
    yield serializers.serialize(
      object.worker,
      specifiedType: const FullType(RuntimeModeWorkerEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RuntimeMode object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RuntimeModeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'ai':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RuntimeModeAiEnum),
          ) as RuntimeModeAiEnum;
          result.ai = valueDes;
          break;
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RuntimeModeDataEnum),
          ) as RuntimeModeDataEnum;
          result.data = valueDes;
          break;
        case r'overall':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RuntimeModeOverallEnum),
          ) as RuntimeModeOverallEnum;
          result.overall = valueDes;
          break;
        case r'speech':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RuntimeModeSpeechEnum),
          ) as RuntimeModeSpeechEnum;
          result.speech = valueDes;
          break;
        case r'worker':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RuntimeModeWorkerEnum),
          ) as RuntimeModeWorkerEnum;
          result.worker = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RuntimeMode deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RuntimeModeBuilder();
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

class RuntimeModeAiEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'disabled')
  static const RuntimeModeAiEnum disabled = _$runtimeModeAiEnum_disabled;
  @BuiltValueEnumConst(wireName: r'live-azure')
  static const RuntimeModeAiEnum liveAzure = _$runtimeModeAiEnum_liveAzure;
  @BuiltValueEnumConst(wireName: r'degraded')
  static const RuntimeModeAiEnum degraded = _$runtimeModeAiEnum_degraded;

  static Serializer<RuntimeModeAiEnum> get serializer => _$runtimeModeAiEnumSerializer;

  const RuntimeModeAiEnum._(String name): super(name);

  static BuiltSet<RuntimeModeAiEnum> get values => _$runtimeModeAiEnumValues;
  static RuntimeModeAiEnum valueOf(String name) => _$runtimeModeAiEnumValueOf(name);
}

class RuntimeModeDataEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'unavailable')
  static const RuntimeModeDataEnum unavailable = _$runtimeModeDataEnum_unavailable;
  @BuiltValueEnumConst(wireName: r'public-cache')
  static const RuntimeModeDataEnum publicCache = _$runtimeModeDataEnum_publicCache;
  @BuiltValueEnumConst(wireName: r'db-backed')
  static const RuntimeModeDataEnum dbBacked = _$runtimeModeDataEnum_dbBacked;
  @BuiltValueEnumConst(wireName: r'degraded')
  static const RuntimeModeDataEnum degraded = _$runtimeModeDataEnum_degraded;

  static Serializer<RuntimeModeDataEnum> get serializer => _$runtimeModeDataEnumSerializer;

  const RuntimeModeDataEnum._(String name): super(name);

  static BuiltSet<RuntimeModeDataEnum> get values => _$runtimeModeDataEnumValues;
  static RuntimeModeDataEnum valueOf(String name) => _$runtimeModeDataEnumValueOf(name);
}

class RuntimeModeOverallEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'public-cache')
  static const RuntimeModeOverallEnum publicCache = _$runtimeModeOverallEnum_publicCache;
  @BuiltValueEnumConst(wireName: r'db-backed')
  static const RuntimeModeOverallEnum dbBacked = _$runtimeModeOverallEnum_dbBacked;
  @BuiltValueEnumConst(wireName: r'live-azure')
  static const RuntimeModeOverallEnum liveAzure = _$runtimeModeOverallEnum_liveAzure;
  @BuiltValueEnumConst(wireName: r'degraded')
  static const RuntimeModeOverallEnum degraded = _$runtimeModeOverallEnum_degraded;

  static Serializer<RuntimeModeOverallEnum> get serializer => _$runtimeModeOverallEnumSerializer;

  const RuntimeModeOverallEnum._(String name): super(name);

  static BuiltSet<RuntimeModeOverallEnum> get values => _$runtimeModeOverallEnumValues;
  static RuntimeModeOverallEnum valueOf(String name) => _$runtimeModeOverallEnumValueOf(name);
}

class RuntimeModeSpeechEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'disabled')
  static const RuntimeModeSpeechEnum disabled = _$runtimeModeSpeechEnum_disabled;
  @BuiltValueEnumConst(wireName: r'live-azure')
  static const RuntimeModeSpeechEnum liveAzure = _$runtimeModeSpeechEnum_liveAzure;
  @BuiltValueEnumConst(wireName: r'degraded')
  static const RuntimeModeSpeechEnum degraded = _$runtimeModeSpeechEnum_degraded;

  static Serializer<RuntimeModeSpeechEnum> get serializer => _$runtimeModeSpeechEnumSerializer;

  const RuntimeModeSpeechEnum._(String name): super(name);

  static BuiltSet<RuntimeModeSpeechEnum> get values => _$runtimeModeSpeechEnumValues;
  static RuntimeModeSpeechEnum valueOf(String name) => _$runtimeModeSpeechEnumValueOf(name);
}

class RuntimeModeWorkerEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'dry-run')
  static const RuntimeModeWorkerEnum dryRun = _$runtimeModeWorkerEnum_dryRun;
  @BuiltValueEnumConst(wireName: r'degraded')
  static const RuntimeModeWorkerEnum degraded = _$runtimeModeWorkerEnum_degraded;

  static Serializer<RuntimeModeWorkerEnum> get serializer => _$runtimeModeWorkerEnumSerializer;

  const RuntimeModeWorkerEnum._(String name): super(name);

  static BuiltSet<RuntimeModeWorkerEnum> get values => _$runtimeModeWorkerEnumValues;
  static RuntimeModeWorkerEnum valueOf(String name) => _$runtimeModeWorkerEnumValueOf(name);
}

