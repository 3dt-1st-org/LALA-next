// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'docent_script_data.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const DocentScriptDataCategoryEnum _$docentScriptDataCategoryEnum_attraction =
    const DocentScriptDataCategoryEnum._('attraction');
const DocentScriptDataCategoryEnum _$docentScriptDataCategoryEnum_restaurant =
    const DocentScriptDataCategoryEnum._('restaurant');
const DocentScriptDataCategoryEnum _$docentScriptDataCategoryEnum_event =
    const DocentScriptDataCategoryEnum._('event');
const DocentScriptDataCategoryEnum _$docentScriptDataCategoryEnum_cultureVenue =
    const DocentScriptDataCategoryEnum._('cultureVenue');

DocentScriptDataCategoryEnum _$docentScriptDataCategoryEnumValueOf(
    String name) {
  switch (name) {
    case 'attraction':
      return _$docentScriptDataCategoryEnum_attraction;
    case 'restaurant':
      return _$docentScriptDataCategoryEnum_restaurant;
    case 'event':
      return _$docentScriptDataCategoryEnum_event;
    case 'cultureVenue':
      return _$docentScriptDataCategoryEnum_cultureVenue;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<DocentScriptDataCategoryEnum>
    _$docentScriptDataCategoryEnumValues =
    BuiltSet<DocentScriptDataCategoryEnum>(const <DocentScriptDataCategoryEnum>[
  _$docentScriptDataCategoryEnum_attraction,
  _$docentScriptDataCategoryEnum_restaurant,
  _$docentScriptDataCategoryEnum_event,
  _$docentScriptDataCategoryEnum_cultureVenue,
]);

const DocentScriptDataLanguageEnum _$docentScriptDataLanguageEnum_ko =
    const DocentScriptDataLanguageEnum._('ko');
const DocentScriptDataLanguageEnum _$docentScriptDataLanguageEnum_en =
    const DocentScriptDataLanguageEnum._('en');

DocentScriptDataLanguageEnum _$docentScriptDataLanguageEnumValueOf(
    String name) {
  switch (name) {
    case 'ko':
      return _$docentScriptDataLanguageEnum_ko;
    case 'en':
      return _$docentScriptDataLanguageEnum_en;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<DocentScriptDataLanguageEnum>
    _$docentScriptDataLanguageEnumValues =
    BuiltSet<DocentScriptDataLanguageEnum>(const <DocentScriptDataLanguageEnum>[
  _$docentScriptDataLanguageEnum_ko,
  _$docentScriptDataLanguageEnum_en,
]);

const DocentScriptDataModeEnum _$docentScriptDataModeEnum_brief =
    const DocentScriptDataModeEnum._('brief');
const DocentScriptDataModeEnum _$docentScriptDataModeEnum_detail =
    const DocentScriptDataModeEnum._('detail');

DocentScriptDataModeEnum _$docentScriptDataModeEnumValueOf(String name) {
  switch (name) {
    case 'brief':
      return _$docentScriptDataModeEnum_brief;
    case 'detail':
      return _$docentScriptDataModeEnum_detail;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<DocentScriptDataModeEnum> _$docentScriptDataModeEnumValues =
    BuiltSet<DocentScriptDataModeEnum>(const <DocentScriptDataModeEnum>[
  _$docentScriptDataModeEnum_brief,
  _$docentScriptDataModeEnum_detail,
]);

const DocentScriptDataSource_Enum
    _$docentScriptDataSourceEnum_ruleBasedCuration =
    const DocentScriptDataSource_Enum._('ruleBasedCuration');
const DocentScriptDataSource_Enum _$docentScriptDataSourceEnum_dbCache =
    const DocentScriptDataSource_Enum._('dbCache');
const DocentScriptDataSource_Enum _$docentScriptDataSourceEnum_azureOpenai =
    const DocentScriptDataSource_Enum._('azureOpenai');

DocentScriptDataSource_Enum _$docentScriptDataSourceEnumValueOf(String name) {
  switch (name) {
    case 'ruleBasedCuration':
      return _$docentScriptDataSourceEnum_ruleBasedCuration;
    case 'dbCache':
      return _$docentScriptDataSourceEnum_dbCache;
    case 'azureOpenai':
      return _$docentScriptDataSourceEnum_azureOpenai;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<DocentScriptDataSource_Enum> _$docentScriptDataSourceEnumValues =
    BuiltSet<DocentScriptDataSource_Enum>(const <DocentScriptDataSource_Enum>[
  _$docentScriptDataSourceEnum_ruleBasedCuration,
  _$docentScriptDataSourceEnum_dbCache,
  _$docentScriptDataSourceEnum_azureOpenai,
]);

Serializer<DocentScriptDataCategoryEnum>
    _$docentScriptDataCategoryEnumSerializer =
    _$DocentScriptDataCategoryEnumSerializer();
Serializer<DocentScriptDataLanguageEnum>
    _$docentScriptDataLanguageEnumSerializer =
    _$DocentScriptDataLanguageEnumSerializer();
Serializer<DocentScriptDataModeEnum> _$docentScriptDataModeEnumSerializer =
    _$DocentScriptDataModeEnumSerializer();
Serializer<DocentScriptDataSource_Enum> _$docentScriptDataSourceEnumSerializer =
    _$DocentScriptDataSource_EnumSerializer();

class _$DocentScriptDataCategoryEnumSerializer
    implements PrimitiveSerializer<DocentScriptDataCategoryEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'attraction': 'attraction',
    'restaurant': 'restaurant',
    'event': 'event',
    'cultureVenue': 'culture_venue',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'attraction': 'attraction',
    'restaurant': 'restaurant',
    'event': 'event',
    'culture_venue': 'cultureVenue',
  };

  @override
  final Iterable<Type> types = const <Type>[DocentScriptDataCategoryEnum];
  @override
  final String wireName = 'DocentScriptDataCategoryEnum';

  @override
  Object serialize(Serializers serializers, DocentScriptDataCategoryEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  DocentScriptDataCategoryEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      DocentScriptDataCategoryEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$DocentScriptDataLanguageEnumSerializer
    implements PrimitiveSerializer<DocentScriptDataLanguageEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'ko': 'ko',
    'en': 'en',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'ko': 'ko',
    'en': 'en',
  };

  @override
  final Iterable<Type> types = const <Type>[DocentScriptDataLanguageEnum];
  @override
  final String wireName = 'DocentScriptDataLanguageEnum';

  @override
  Object serialize(Serializers serializers, DocentScriptDataLanguageEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  DocentScriptDataLanguageEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      DocentScriptDataLanguageEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$DocentScriptDataModeEnumSerializer
    implements PrimitiveSerializer<DocentScriptDataModeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'brief': 'brief',
    'detail': 'detail',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'brief': 'brief',
    'detail': 'detail',
  };

  @override
  final Iterable<Type> types = const <Type>[DocentScriptDataModeEnum];
  @override
  final String wireName = 'DocentScriptDataModeEnum';

  @override
  Object serialize(Serializers serializers, DocentScriptDataModeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  DocentScriptDataModeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      DocentScriptDataModeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$DocentScriptDataSource_EnumSerializer
    implements PrimitiveSerializer<DocentScriptDataSource_Enum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'ruleBasedCuration': 'rule_based_curation',
    'dbCache': 'db_cache',
    'azureOpenai': 'azure_openai',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'rule_based_curation': 'ruleBasedCuration',
    'db_cache': 'dbCache',
    'azure_openai': 'azureOpenai',
  };

  @override
  final Iterable<Type> types = const <Type>[DocentScriptDataSource_Enum];
  @override
  final String wireName = 'DocentScriptDataSource_Enum';

  @override
  Object serialize(Serializers serializers, DocentScriptDataSource_Enum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  DocentScriptDataSource_Enum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      DocentScriptDataSource_Enum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$DocentScriptData extends DocentScriptData {
  @override
  final String cacheKey;
  @override
  final DocentScriptDataCategoryEnum category;
  @override
  final String? generatedAt;
  @override
  final int? groundingCount;
  @override
  final BuiltList<String>? groundingSources;
  @override
  final DocentScriptDataLanguageEnum language;
  @override
  final DocentScriptDataModeEnum mode;
  @override
  final String placeId;
  @override
  final String requestHash;
  @override
  final String script;
  @override
  final DocentScriptDataSource_Enum source_;
  @override
  final int? ttlSec;

  factory _$DocentScriptData(
          [void Function(DocentScriptDataBuilder)? updates]) =>
      (DocentScriptDataBuilder()..update(updates))._build();

  _$DocentScriptData._(
      {required this.cacheKey,
      required this.category,
      this.generatedAt,
      this.groundingCount,
      this.groundingSources,
      required this.language,
      required this.mode,
      required this.placeId,
      required this.requestHash,
      required this.script,
      required this.source_,
      this.ttlSec})
      : super._();
  @override
  DocentScriptData rebuild(void Function(DocentScriptDataBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DocentScriptDataBuilder toBuilder() =>
      DocentScriptDataBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DocentScriptData &&
        cacheKey == other.cacheKey &&
        category == other.category &&
        generatedAt == other.generatedAt &&
        groundingCount == other.groundingCount &&
        groundingSources == other.groundingSources &&
        language == other.language &&
        mode == other.mode &&
        placeId == other.placeId &&
        requestHash == other.requestHash &&
        script == other.script &&
        source_ == other.source_ &&
        ttlSec == other.ttlSec;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, cacheKey.hashCode);
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, generatedAt.hashCode);
    _$hash = $jc(_$hash, groundingCount.hashCode);
    _$hash = $jc(_$hash, groundingSources.hashCode);
    _$hash = $jc(_$hash, language.hashCode);
    _$hash = $jc(_$hash, mode.hashCode);
    _$hash = $jc(_$hash, placeId.hashCode);
    _$hash = $jc(_$hash, requestHash.hashCode);
    _$hash = $jc(_$hash, script.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, ttlSec.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DocentScriptData')
          ..add('cacheKey', cacheKey)
          ..add('category', category)
          ..add('generatedAt', generatedAt)
          ..add('groundingCount', groundingCount)
          ..add('groundingSources', groundingSources)
          ..add('language', language)
          ..add('mode', mode)
          ..add('placeId', placeId)
          ..add('requestHash', requestHash)
          ..add('script', script)
          ..add('source_', source_)
          ..add('ttlSec', ttlSec))
        .toString();
  }
}

class DocentScriptDataBuilder
    implements Builder<DocentScriptData, DocentScriptDataBuilder> {
  _$DocentScriptData? _$v;

  String? _cacheKey;
  String? get cacheKey => _$this._cacheKey;
  set cacheKey(String? cacheKey) => _$this._cacheKey = cacheKey;

  DocentScriptDataCategoryEnum? _category;
  DocentScriptDataCategoryEnum? get category => _$this._category;
  set category(DocentScriptDataCategoryEnum? category) =>
      _$this._category = category;

  String? _generatedAt;
  String? get generatedAt => _$this._generatedAt;
  set generatedAt(String? generatedAt) => _$this._generatedAt = generatedAt;

  int? _groundingCount;
  int? get groundingCount => _$this._groundingCount;
  set groundingCount(int? groundingCount) =>
      _$this._groundingCount = groundingCount;

  ListBuilder<String>? _groundingSources;
  ListBuilder<String> get groundingSources =>
      _$this._groundingSources ??= ListBuilder<String>();
  set groundingSources(ListBuilder<String>? groundingSources) =>
      _$this._groundingSources = groundingSources;

  DocentScriptDataLanguageEnum? _language;
  DocentScriptDataLanguageEnum? get language => _$this._language;
  set language(DocentScriptDataLanguageEnum? language) =>
      _$this._language = language;

  DocentScriptDataModeEnum? _mode;
  DocentScriptDataModeEnum? get mode => _$this._mode;
  set mode(DocentScriptDataModeEnum? mode) => _$this._mode = mode;

  String? _placeId;
  String? get placeId => _$this._placeId;
  set placeId(String? placeId) => _$this._placeId = placeId;

  String? _requestHash;
  String? get requestHash => _$this._requestHash;
  set requestHash(String? requestHash) => _$this._requestHash = requestHash;

  String? _script;
  String? get script => _$this._script;
  set script(String? script) => _$this._script = script;

  DocentScriptDataSource_Enum? _source_;
  DocentScriptDataSource_Enum? get source_ => _$this._source_;
  set source_(DocentScriptDataSource_Enum? source_) =>
      _$this._source_ = source_;

  int? _ttlSec;
  int? get ttlSec => _$this._ttlSec;
  set ttlSec(int? ttlSec) => _$this._ttlSec = ttlSec;

  DocentScriptDataBuilder() {
    DocentScriptData._defaults(this);
  }

  DocentScriptDataBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _cacheKey = $v.cacheKey;
      _category = $v.category;
      _generatedAt = $v.generatedAt;
      _groundingCount = $v.groundingCount;
      _groundingSources = $v.groundingSources?.toBuilder();
      _language = $v.language;
      _mode = $v.mode;
      _placeId = $v.placeId;
      _requestHash = $v.requestHash;
      _script = $v.script;
      _source_ = $v.source_;
      _ttlSec = $v.ttlSec;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DocentScriptData other) {
    _$v = other as _$DocentScriptData;
  }

  @override
  void update(void Function(DocentScriptDataBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DocentScriptData build() => _build();

  _$DocentScriptData _build() {
    _$DocentScriptData _$result;
    try {
      _$result = _$v ??
          _$DocentScriptData._(
            cacheKey: BuiltValueNullFieldError.checkNotNull(
                cacheKey, r'DocentScriptData', 'cacheKey'),
            category: BuiltValueNullFieldError.checkNotNull(
                category, r'DocentScriptData', 'category'),
            generatedAt: generatedAt,
            groundingCount: groundingCount,
            groundingSources: _groundingSources?.build(),
            language: BuiltValueNullFieldError.checkNotNull(
                language, r'DocentScriptData', 'language'),
            mode: BuiltValueNullFieldError.checkNotNull(
                mode, r'DocentScriptData', 'mode'),
            placeId: BuiltValueNullFieldError.checkNotNull(
                placeId, r'DocentScriptData', 'placeId'),
            requestHash: BuiltValueNullFieldError.checkNotNull(
                requestHash, r'DocentScriptData', 'requestHash'),
            script: BuiltValueNullFieldError.checkNotNull(
                script, r'DocentScriptData', 'script'),
            source_: BuiltValueNullFieldError.checkNotNull(
                source_, r'DocentScriptData', 'source_'),
            ttlSec: ttlSec,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'groundingSources';
        _groundingSources?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'DocentScriptData', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
