// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_plan_data.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const DailyPlanDataLanguageEnum _$dailyPlanDataLanguageEnum_ko =
    const DailyPlanDataLanguageEnum._('ko');
const DailyPlanDataLanguageEnum _$dailyPlanDataLanguageEnum_en =
    const DailyPlanDataLanguageEnum._('en');

DailyPlanDataLanguageEnum _$dailyPlanDataLanguageEnumValueOf(String name) {
  switch (name) {
    case 'ko':
      return _$dailyPlanDataLanguageEnum_ko;
    case 'en':
      return _$dailyPlanDataLanguageEnum_en;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<DailyPlanDataLanguageEnum> _$dailyPlanDataLanguageEnumValues =
    BuiltSet<DailyPlanDataLanguageEnum>(const <DailyPlanDataLanguageEnum>[
  _$dailyPlanDataLanguageEnum_ko,
  _$dailyPlanDataLanguageEnum_en,
]);

const DailyPlanDataSource_Enum _$dailyPlanDataSourceEnum_unavailable =
    const DailyPlanDataSource_Enum._('unavailable');
const DailyPlanDataSource_Enum _$dailyPlanDataSourceEnum_publicMvpSnapshot =
    const DailyPlanDataSource_Enum._('publicMvpSnapshot');
const DailyPlanDataSource_Enum _$dailyPlanDataSourceEnum_db =
    const DailyPlanDataSource_Enum._('db');
const DailyPlanDataSource_Enum _$dailyPlanDataSourceEnum_mixed =
    const DailyPlanDataSource_Enum._('mixed');

DailyPlanDataSource_Enum _$dailyPlanDataSourceEnumValueOf(String name) {
  switch (name) {
    case 'unavailable':
      return _$dailyPlanDataSourceEnum_unavailable;
    case 'publicMvpSnapshot':
      return _$dailyPlanDataSourceEnum_publicMvpSnapshot;
    case 'db':
      return _$dailyPlanDataSourceEnum_db;
    case 'mixed':
      return _$dailyPlanDataSourceEnum_mixed;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<DailyPlanDataSource_Enum> _$dailyPlanDataSourceEnumValues =
    BuiltSet<DailyPlanDataSource_Enum>(const <DailyPlanDataSource_Enum>[
  _$dailyPlanDataSourceEnum_unavailable,
  _$dailyPlanDataSourceEnum_publicMvpSnapshot,
  _$dailyPlanDataSourceEnum_db,
  _$dailyPlanDataSourceEnum_mixed,
]);

Serializer<DailyPlanDataLanguageEnum> _$dailyPlanDataLanguageEnumSerializer =
    _$DailyPlanDataLanguageEnumSerializer();
Serializer<DailyPlanDataSource_Enum> _$dailyPlanDataSourceEnumSerializer =
    _$DailyPlanDataSource_EnumSerializer();

class _$DailyPlanDataLanguageEnumSerializer
    implements PrimitiveSerializer<DailyPlanDataLanguageEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'ko': 'ko',
    'en': 'en',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'ko': 'ko',
    'en': 'en',
  };

  @override
  final Iterable<Type> types = const <Type>[DailyPlanDataLanguageEnum];
  @override
  final String wireName = 'DailyPlanDataLanguageEnum';

  @override
  Object serialize(Serializers serializers, DailyPlanDataLanguageEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  DailyPlanDataLanguageEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      DailyPlanDataLanguageEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$DailyPlanDataSource_EnumSerializer
    implements PrimitiveSerializer<DailyPlanDataSource_Enum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'unavailable': 'unavailable',
    'publicMvpSnapshot': 'public_mvp_snapshot',
    'db': 'db',
    'mixed': 'mixed',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'unavailable': 'unavailable',
    'public_mvp_snapshot': 'publicMvpSnapshot',
    'db': 'db',
    'mixed': 'mixed',
  };

  @override
  final Iterable<Type> types = const <Type>[DailyPlanDataSource_Enum];
  @override
  final String wireName = 'DailyPlanDataSource_Enum';

  @override
  Object serialize(Serializers serializers, DailyPlanDataSource_Enum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  DailyPlanDataSource_Enum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      DailyPlanDataSource_Enum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$DailyPlanData extends DailyPlanData {
  @override
  final String cacheKey;
  @override
  final Coordinate center;
  @override
  final DailyPlanDataLanguageEnum language;
  @override
  final int radiusM;
  @override
  final String requestHash;
  @override
  final BuiltList<DailyPlanSlot> slots;
  @override
  final DailyPlanDataSource_Enum source_;
  @override
  final WeatherData weather;

  factory _$DailyPlanData([void Function(DailyPlanDataBuilder)? updates]) =>
      (DailyPlanDataBuilder()..update(updates))._build();

  _$DailyPlanData._(
      {required this.cacheKey,
      required this.center,
      required this.language,
      required this.radiusM,
      required this.requestHash,
      required this.slots,
      required this.source_,
      required this.weather})
      : super._();
  @override
  DailyPlanData rebuild(void Function(DailyPlanDataBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DailyPlanDataBuilder toBuilder() => DailyPlanDataBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DailyPlanData &&
        cacheKey == other.cacheKey &&
        center == other.center &&
        language == other.language &&
        radiusM == other.radiusM &&
        requestHash == other.requestHash &&
        slots == other.slots &&
        source_ == other.source_ &&
        weather == other.weather;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, cacheKey.hashCode);
    _$hash = $jc(_$hash, center.hashCode);
    _$hash = $jc(_$hash, language.hashCode);
    _$hash = $jc(_$hash, radiusM.hashCode);
    _$hash = $jc(_$hash, requestHash.hashCode);
    _$hash = $jc(_$hash, slots.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, weather.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DailyPlanData')
          ..add('cacheKey', cacheKey)
          ..add('center', center)
          ..add('language', language)
          ..add('radiusM', radiusM)
          ..add('requestHash', requestHash)
          ..add('slots', slots)
          ..add('source_', source_)
          ..add('weather', weather))
        .toString();
  }
}

class DailyPlanDataBuilder
    implements Builder<DailyPlanData, DailyPlanDataBuilder> {
  _$DailyPlanData? _$v;

  String? _cacheKey;
  String? get cacheKey => _$this._cacheKey;
  set cacheKey(String? cacheKey) => _$this._cacheKey = cacheKey;

  CoordinateBuilder? _center;
  CoordinateBuilder get center => _$this._center ??= CoordinateBuilder();
  set center(CoordinateBuilder? center) => _$this._center = center;

  DailyPlanDataLanguageEnum? _language;
  DailyPlanDataLanguageEnum? get language => _$this._language;
  set language(DailyPlanDataLanguageEnum? language) =>
      _$this._language = language;

  int? _radiusM;
  int? get radiusM => _$this._radiusM;
  set radiusM(int? radiusM) => _$this._radiusM = radiusM;

  String? _requestHash;
  String? get requestHash => _$this._requestHash;
  set requestHash(String? requestHash) => _$this._requestHash = requestHash;

  ListBuilder<DailyPlanSlot>? _slots;
  ListBuilder<DailyPlanSlot> get slots =>
      _$this._slots ??= ListBuilder<DailyPlanSlot>();
  set slots(ListBuilder<DailyPlanSlot>? slots) => _$this._slots = slots;

  DailyPlanDataSource_Enum? _source_;
  DailyPlanDataSource_Enum? get source_ => _$this._source_;
  set source_(DailyPlanDataSource_Enum? source_) => _$this._source_ = source_;

  WeatherDataBuilder? _weather;
  WeatherDataBuilder get weather => _$this._weather ??= WeatherDataBuilder();
  set weather(WeatherDataBuilder? weather) => _$this._weather = weather;

  DailyPlanDataBuilder() {
    DailyPlanData._defaults(this);
  }

  DailyPlanDataBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _cacheKey = $v.cacheKey;
      _center = $v.center.toBuilder();
      _language = $v.language;
      _radiusM = $v.radiusM;
      _requestHash = $v.requestHash;
      _slots = $v.slots.toBuilder();
      _source_ = $v.source_;
      _weather = $v.weather.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DailyPlanData other) {
    _$v = other as _$DailyPlanData;
  }

  @override
  void update(void Function(DailyPlanDataBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DailyPlanData build() => _build();

  _$DailyPlanData _build() {
    _$DailyPlanData _$result;
    try {
      _$result = _$v ??
          _$DailyPlanData._(
            cacheKey: BuiltValueNullFieldError.checkNotNull(
                cacheKey, r'DailyPlanData', 'cacheKey'),
            center: center.build(),
            language: BuiltValueNullFieldError.checkNotNull(
                language, r'DailyPlanData', 'language'),
            radiusM: BuiltValueNullFieldError.checkNotNull(
                radiusM, r'DailyPlanData', 'radiusM'),
            requestHash: BuiltValueNullFieldError.checkNotNull(
                requestHash, r'DailyPlanData', 'requestHash'),
            slots: slots.build(),
            source_: BuiltValueNullFieldError.checkNotNull(
                source_, r'DailyPlanData', 'source_'),
            weather: weather.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'center';
        center.build();

        _$failedField = 'slots';
        slots.build();

        _$failedField = 'weather';
        weather.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'DailyPlanData', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
