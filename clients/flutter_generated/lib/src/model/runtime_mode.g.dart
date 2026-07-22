// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runtime_mode.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const RuntimeModeAiEnum _$runtimeModeAiEnum_disabled =
    const RuntimeModeAiEnum._('disabled');
const RuntimeModeAiEnum _$runtimeModeAiEnum_liveAzure =
    const RuntimeModeAiEnum._('liveAzure');
const RuntimeModeAiEnum _$runtimeModeAiEnum_degraded =
    const RuntimeModeAiEnum._('degraded');

RuntimeModeAiEnum _$runtimeModeAiEnumValueOf(String name) {
  switch (name) {
    case 'disabled':
      return _$runtimeModeAiEnum_disabled;
    case 'liveAzure':
      return _$runtimeModeAiEnum_liveAzure;
    case 'degraded':
      return _$runtimeModeAiEnum_degraded;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<RuntimeModeAiEnum> _$runtimeModeAiEnumValues =
    BuiltSet<RuntimeModeAiEnum>(const <RuntimeModeAiEnum>[
  _$runtimeModeAiEnum_disabled,
  _$runtimeModeAiEnum_liveAzure,
  _$runtimeModeAiEnum_degraded,
]);

const RuntimeModeDataEnum _$runtimeModeDataEnum_unavailable =
    const RuntimeModeDataEnum._('unavailable');
const RuntimeModeDataEnum _$runtimeModeDataEnum_publicCache =
    const RuntimeModeDataEnum._('publicCache');
const RuntimeModeDataEnum _$runtimeModeDataEnum_dbBacked =
    const RuntimeModeDataEnum._('dbBacked');
const RuntimeModeDataEnum _$runtimeModeDataEnum_degraded =
    const RuntimeModeDataEnum._('degraded');

RuntimeModeDataEnum _$runtimeModeDataEnumValueOf(String name) {
  switch (name) {
    case 'unavailable':
      return _$runtimeModeDataEnum_unavailable;
    case 'publicCache':
      return _$runtimeModeDataEnum_publicCache;
    case 'dbBacked':
      return _$runtimeModeDataEnum_dbBacked;
    case 'degraded':
      return _$runtimeModeDataEnum_degraded;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<RuntimeModeDataEnum> _$runtimeModeDataEnumValues =
    BuiltSet<RuntimeModeDataEnum>(const <RuntimeModeDataEnum>[
  _$runtimeModeDataEnum_unavailable,
  _$runtimeModeDataEnum_publicCache,
  _$runtimeModeDataEnum_dbBacked,
  _$runtimeModeDataEnum_degraded,
]);

const RuntimeModeOverallEnum _$runtimeModeOverallEnum_publicCache =
    const RuntimeModeOverallEnum._('publicCache');
const RuntimeModeOverallEnum _$runtimeModeOverallEnum_dbBacked =
    const RuntimeModeOverallEnum._('dbBacked');
const RuntimeModeOverallEnum _$runtimeModeOverallEnum_liveAzure =
    const RuntimeModeOverallEnum._('liveAzure');
const RuntimeModeOverallEnum _$runtimeModeOverallEnum_degraded =
    const RuntimeModeOverallEnum._('degraded');

RuntimeModeOverallEnum _$runtimeModeOverallEnumValueOf(String name) {
  switch (name) {
    case 'publicCache':
      return _$runtimeModeOverallEnum_publicCache;
    case 'dbBacked':
      return _$runtimeModeOverallEnum_dbBacked;
    case 'liveAzure':
      return _$runtimeModeOverallEnum_liveAzure;
    case 'degraded':
      return _$runtimeModeOverallEnum_degraded;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<RuntimeModeOverallEnum> _$runtimeModeOverallEnumValues =
    BuiltSet<RuntimeModeOverallEnum>(const <RuntimeModeOverallEnum>[
  _$runtimeModeOverallEnum_publicCache,
  _$runtimeModeOverallEnum_dbBacked,
  _$runtimeModeOverallEnum_liveAzure,
  _$runtimeModeOverallEnum_degraded,
]);

const RuntimeModeSpeechEnum _$runtimeModeSpeechEnum_disabled =
    const RuntimeModeSpeechEnum._('disabled');
const RuntimeModeSpeechEnum _$runtimeModeSpeechEnum_liveAzure =
    const RuntimeModeSpeechEnum._('liveAzure');
const RuntimeModeSpeechEnum _$runtimeModeSpeechEnum_degraded =
    const RuntimeModeSpeechEnum._('degraded');

RuntimeModeSpeechEnum _$runtimeModeSpeechEnumValueOf(String name) {
  switch (name) {
    case 'disabled':
      return _$runtimeModeSpeechEnum_disabled;
    case 'liveAzure':
      return _$runtimeModeSpeechEnum_liveAzure;
    case 'degraded':
      return _$runtimeModeSpeechEnum_degraded;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<RuntimeModeSpeechEnum> _$runtimeModeSpeechEnumValues =
    BuiltSet<RuntimeModeSpeechEnum>(const <RuntimeModeSpeechEnum>[
  _$runtimeModeSpeechEnum_disabled,
  _$runtimeModeSpeechEnum_liveAzure,
  _$runtimeModeSpeechEnum_degraded,
]);

const RuntimeModeWorkerEnum _$runtimeModeWorkerEnum_dryRun =
    const RuntimeModeWorkerEnum._('dryRun');
const RuntimeModeWorkerEnum _$runtimeModeWorkerEnum_degraded =
    const RuntimeModeWorkerEnum._('degraded');

RuntimeModeWorkerEnum _$runtimeModeWorkerEnumValueOf(String name) {
  switch (name) {
    case 'dryRun':
      return _$runtimeModeWorkerEnum_dryRun;
    case 'degraded':
      return _$runtimeModeWorkerEnum_degraded;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<RuntimeModeWorkerEnum> _$runtimeModeWorkerEnumValues =
    BuiltSet<RuntimeModeWorkerEnum>(const <RuntimeModeWorkerEnum>[
  _$runtimeModeWorkerEnum_dryRun,
  _$runtimeModeWorkerEnum_degraded,
]);

Serializer<RuntimeModeAiEnum> _$runtimeModeAiEnumSerializer =
    _$RuntimeModeAiEnumSerializer();
Serializer<RuntimeModeDataEnum> _$runtimeModeDataEnumSerializer =
    _$RuntimeModeDataEnumSerializer();
Serializer<RuntimeModeOverallEnum> _$runtimeModeOverallEnumSerializer =
    _$RuntimeModeOverallEnumSerializer();
Serializer<RuntimeModeSpeechEnum> _$runtimeModeSpeechEnumSerializer =
    _$RuntimeModeSpeechEnumSerializer();
Serializer<RuntimeModeWorkerEnum> _$runtimeModeWorkerEnumSerializer =
    _$RuntimeModeWorkerEnumSerializer();

class _$RuntimeModeAiEnumSerializer
    implements PrimitiveSerializer<RuntimeModeAiEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'disabled': 'disabled',
    'liveAzure': 'live-azure',
    'degraded': 'degraded',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'disabled': 'disabled',
    'live-azure': 'liveAzure',
    'degraded': 'degraded',
  };

  @override
  final Iterable<Type> types = const <Type>[RuntimeModeAiEnum];
  @override
  final String wireName = 'RuntimeModeAiEnum';

  @override
  Object serialize(Serializers serializers, RuntimeModeAiEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  RuntimeModeAiEnum deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      RuntimeModeAiEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$RuntimeModeDataEnumSerializer
    implements PrimitiveSerializer<RuntimeModeDataEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'unavailable': 'unavailable',
    'publicCache': 'public-cache',
    'dbBacked': 'db-backed',
    'degraded': 'degraded',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'unavailable': 'unavailable',
    'public-cache': 'publicCache',
    'db-backed': 'dbBacked',
    'degraded': 'degraded',
  };

  @override
  final Iterable<Type> types = const <Type>[RuntimeModeDataEnum];
  @override
  final String wireName = 'RuntimeModeDataEnum';

  @override
  Object serialize(Serializers serializers, RuntimeModeDataEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  RuntimeModeDataEnum deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      RuntimeModeDataEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$RuntimeModeOverallEnumSerializer
    implements PrimitiveSerializer<RuntimeModeOverallEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'publicCache': 'public-cache',
    'dbBacked': 'db-backed',
    'liveAzure': 'live-azure',
    'degraded': 'degraded',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'public-cache': 'publicCache',
    'db-backed': 'dbBacked',
    'live-azure': 'liveAzure',
    'degraded': 'degraded',
  };

  @override
  final Iterable<Type> types = const <Type>[RuntimeModeOverallEnum];
  @override
  final String wireName = 'RuntimeModeOverallEnum';

  @override
  Object serialize(Serializers serializers, RuntimeModeOverallEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  RuntimeModeOverallEnum deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      RuntimeModeOverallEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$RuntimeModeSpeechEnumSerializer
    implements PrimitiveSerializer<RuntimeModeSpeechEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'disabled': 'disabled',
    'liveAzure': 'live-azure',
    'degraded': 'degraded',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'disabled': 'disabled',
    'live-azure': 'liveAzure',
    'degraded': 'degraded',
  };

  @override
  final Iterable<Type> types = const <Type>[RuntimeModeSpeechEnum];
  @override
  final String wireName = 'RuntimeModeSpeechEnum';

  @override
  Object serialize(Serializers serializers, RuntimeModeSpeechEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  RuntimeModeSpeechEnum deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      RuntimeModeSpeechEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$RuntimeModeWorkerEnumSerializer
    implements PrimitiveSerializer<RuntimeModeWorkerEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'dryRun': 'dry-run',
    'degraded': 'degraded',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'dry-run': 'dryRun',
    'degraded': 'degraded',
  };

  @override
  final Iterable<Type> types = const <Type>[RuntimeModeWorkerEnum];
  @override
  final String wireName = 'RuntimeModeWorkerEnum';

  @override
  Object serialize(Serializers serializers, RuntimeModeWorkerEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  RuntimeModeWorkerEnum deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      RuntimeModeWorkerEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$RuntimeMode extends RuntimeMode {
  @override
  final RuntimeModeAiEnum ai;
  @override
  final RuntimeModeDataEnum data;
  @override
  final RuntimeModeOverallEnum overall;
  @override
  final RuntimeModeSpeechEnum speech;
  @override
  final RuntimeModeWorkerEnum worker;

  factory _$RuntimeMode([void Function(RuntimeModeBuilder)? updates]) =>
      (RuntimeModeBuilder()..update(updates))._build();

  _$RuntimeMode._(
      {required this.ai,
      required this.data,
      required this.overall,
      required this.speech,
      required this.worker})
      : super._();
  @override
  RuntimeMode rebuild(void Function(RuntimeModeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RuntimeModeBuilder toBuilder() => RuntimeModeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RuntimeMode &&
        ai == other.ai &&
        data == other.data &&
        overall == other.overall &&
        speech == other.speech &&
        worker == other.worker;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, ai.hashCode);
    _$hash = $jc(_$hash, data.hashCode);
    _$hash = $jc(_$hash, overall.hashCode);
    _$hash = $jc(_$hash, speech.hashCode);
    _$hash = $jc(_$hash, worker.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RuntimeMode')
          ..add('ai', ai)
          ..add('data', data)
          ..add('overall', overall)
          ..add('speech', speech)
          ..add('worker', worker))
        .toString();
  }
}

class RuntimeModeBuilder implements Builder<RuntimeMode, RuntimeModeBuilder> {
  _$RuntimeMode? _$v;

  RuntimeModeAiEnum? _ai;
  RuntimeModeAiEnum? get ai => _$this._ai;
  set ai(RuntimeModeAiEnum? ai) => _$this._ai = ai;

  RuntimeModeDataEnum? _data;
  RuntimeModeDataEnum? get data => _$this._data;
  set data(RuntimeModeDataEnum? data) => _$this._data = data;

  RuntimeModeOverallEnum? _overall;
  RuntimeModeOverallEnum? get overall => _$this._overall;
  set overall(RuntimeModeOverallEnum? overall) => _$this._overall = overall;

  RuntimeModeSpeechEnum? _speech;
  RuntimeModeSpeechEnum? get speech => _$this._speech;
  set speech(RuntimeModeSpeechEnum? speech) => _$this._speech = speech;

  RuntimeModeWorkerEnum? _worker;
  RuntimeModeWorkerEnum? get worker => _$this._worker;
  set worker(RuntimeModeWorkerEnum? worker) => _$this._worker = worker;

  RuntimeModeBuilder() {
    RuntimeMode._defaults(this);
  }

  RuntimeModeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _ai = $v.ai;
      _data = $v.data;
      _overall = $v.overall;
      _speech = $v.speech;
      _worker = $v.worker;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RuntimeMode other) {
    _$v = other as _$RuntimeMode;
  }

  @override
  void update(void Function(RuntimeModeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RuntimeMode build() => _build();

  _$RuntimeMode _build() {
    final _$result = _$v ??
        _$RuntimeMode._(
          ai: BuiltValueNullFieldError.checkNotNull(ai, r'RuntimeMode', 'ai'),
          data: BuiltValueNullFieldError.checkNotNull(
              data, r'RuntimeMode', 'data'),
          overall: BuiltValueNullFieldError.checkNotNull(
              overall, r'RuntimeMode', 'overall'),
          speech: BuiltValueNullFieldError.checkNotNull(
              speech, r'RuntimeMode', 'speech'),
          worker: BuiltValueNullFieldError.checkNotNull(
              worker, r'RuntimeMode', 'worker'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
