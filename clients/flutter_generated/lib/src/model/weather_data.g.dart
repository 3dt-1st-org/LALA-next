// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather_data.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const WeatherDataOutdoorStatusEnum _$weatherDataOutdoorStatusEnum_good =
    const WeatherDataOutdoorStatusEnum._('good');
const WeatherDataOutdoorStatusEnum _$weatherDataOutdoorStatusEnum_bad =
    const WeatherDataOutdoorStatusEnum._('bad');
const WeatherDataOutdoorStatusEnum _$weatherDataOutdoorStatusEnum_unknown =
    const WeatherDataOutdoorStatusEnum._('unknown');

WeatherDataOutdoorStatusEnum _$weatherDataOutdoorStatusEnumValueOf(
    String name) {
  switch (name) {
    case 'good':
      return _$weatherDataOutdoorStatusEnum_good;
    case 'bad':
      return _$weatherDataOutdoorStatusEnum_bad;
    case 'unknown':
      return _$weatherDataOutdoorStatusEnum_unknown;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<WeatherDataOutdoorStatusEnum>
    _$weatherDataOutdoorStatusEnumValues =
    BuiltSet<WeatherDataOutdoorStatusEnum>(const <WeatherDataOutdoorStatusEnum>[
  _$weatherDataOutdoorStatusEnum_good,
  _$weatherDataOutdoorStatusEnum_bad,
  _$weatherDataOutdoorStatusEnum_unknown,
]);

const WeatherDataSource_Enum _$weatherDataSourceEnum_db =
    const WeatherDataSource_Enum._('db');
const WeatherDataSource_Enum
    _$weatherDataSourceEnum_dbPlusAirkoreaSidoRealtime =
    const WeatherDataSource_Enum._('dbPlusAirkoreaSidoRealtime');
const WeatherDataSource_Enum _$weatherDataSourceEnum_kmaUltraSrtNcst =
    const WeatherDataSource_Enum._('kmaUltraSrtNcst');
const WeatherDataSource_Enum _$weatherDataSourceEnum_airkoreaSidoRealtime =
    const WeatherDataSource_Enum._('airkoreaSidoRealtime');
const WeatherDataSource_Enum
    _$weatherDataSourceEnum_kmaUltraSrtNcstPlusAirkoreaSidoRealtime =
    const WeatherDataSource_Enum._('kmaUltraSrtNcstPlusAirkoreaSidoRealtime');
const WeatherDataSource_Enum _$weatherDataSourceEnum_unavailable =
    const WeatherDataSource_Enum._('unavailable');

WeatherDataSource_Enum _$weatherDataSourceEnumValueOf(String name) {
  switch (name) {
    case 'db':
      return _$weatherDataSourceEnum_db;
    case 'dbPlusAirkoreaSidoRealtime':
      return _$weatherDataSourceEnum_dbPlusAirkoreaSidoRealtime;
    case 'kmaUltraSrtNcst':
      return _$weatherDataSourceEnum_kmaUltraSrtNcst;
    case 'airkoreaSidoRealtime':
      return _$weatherDataSourceEnum_airkoreaSidoRealtime;
    case 'kmaUltraSrtNcstPlusAirkoreaSidoRealtime':
      return _$weatherDataSourceEnum_kmaUltraSrtNcstPlusAirkoreaSidoRealtime;
    case 'unavailable':
      return _$weatherDataSourceEnum_unavailable;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<WeatherDataSource_Enum> _$weatherDataSourceEnumValues =
    BuiltSet<WeatherDataSource_Enum>(const <WeatherDataSource_Enum>[
  _$weatherDataSourceEnum_db,
  _$weatherDataSourceEnum_dbPlusAirkoreaSidoRealtime,
  _$weatherDataSourceEnum_kmaUltraSrtNcst,
  _$weatherDataSourceEnum_airkoreaSidoRealtime,
  _$weatherDataSourceEnum_kmaUltraSrtNcstPlusAirkoreaSidoRealtime,
  _$weatherDataSourceEnum_unavailable,
]);

Serializer<WeatherDataOutdoorStatusEnum>
    _$weatherDataOutdoorStatusEnumSerializer =
    _$WeatherDataOutdoorStatusEnumSerializer();
Serializer<WeatherDataSource_Enum> _$weatherDataSourceEnumSerializer =
    _$WeatherDataSource_EnumSerializer();

class _$WeatherDataOutdoorStatusEnumSerializer
    implements PrimitiveSerializer<WeatherDataOutdoorStatusEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'good': 'good',
    'bad': 'bad',
    'unknown': 'unknown',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'good': 'good',
    'bad': 'bad',
    'unknown': 'unknown',
  };

  @override
  final Iterable<Type> types = const <Type>[WeatherDataOutdoorStatusEnum];
  @override
  final String wireName = 'WeatherDataOutdoorStatusEnum';

  @override
  Object serialize(Serializers serializers, WeatherDataOutdoorStatusEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  WeatherDataOutdoorStatusEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      WeatherDataOutdoorStatusEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$WeatherDataSource_EnumSerializer
    implements PrimitiveSerializer<WeatherDataSource_Enum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'db': 'db',
    'dbPlusAirkoreaSidoRealtime': 'db+airkorea_sido_realtime',
    'kmaUltraSrtNcst': 'kma_ultra_srt_ncst',
    'airkoreaSidoRealtime': 'airkorea_sido_realtime',
    'kmaUltraSrtNcstPlusAirkoreaSidoRealtime':
        'kma_ultra_srt_ncst+airkorea_sido_realtime',
    'unavailable': 'unavailable',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'db': 'db',
    'db+airkorea_sido_realtime': 'dbPlusAirkoreaSidoRealtime',
    'kma_ultra_srt_ncst': 'kmaUltraSrtNcst',
    'airkorea_sido_realtime': 'airkoreaSidoRealtime',
    'kma_ultra_srt_ncst+airkorea_sido_realtime':
        'kmaUltraSrtNcstPlusAirkoreaSidoRealtime',
    'unavailable': 'unavailable',
  };

  @override
  final Iterable<Type> types = const <Type>[WeatherDataSource_Enum];
  @override
  final String wireName = 'WeatherDataSource_Enum';

  @override
  Object serialize(Serializers serializers, WeatherDataSource_Enum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  WeatherDataSource_Enum deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      WeatherDataSource_Enum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$WeatherData extends WeatherData {
  @override
  final Dust dust;
  @override
  final bool force;
  @override
  final BuiltList<ForecastItem> forecast;
  @override
  final String icon;
  @override
  final double lat;
  @override
  final double lng;
  @override
  final String? location;
  @override
  final bool? locationMatch;
  @override
  final WeatherDataOutdoorStatusEnum outdoorStatus;
  @override
  final String? recordTime;
  @override
  final WeatherDataSource_Enum source_;
  @override
  final String temp;

  factory _$WeatherData([void Function(WeatherDataBuilder)? updates]) =>
      (WeatherDataBuilder()..update(updates))._build();

  _$WeatherData._(
      {required this.dust,
      required this.force,
      required this.forecast,
      required this.icon,
      required this.lat,
      required this.lng,
      this.location,
      this.locationMatch,
      required this.outdoorStatus,
      this.recordTime,
      required this.source_,
      required this.temp})
      : super._();
  @override
  WeatherData rebuild(void Function(WeatherDataBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WeatherDataBuilder toBuilder() => WeatherDataBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WeatherData &&
        dust == other.dust &&
        force == other.force &&
        forecast == other.forecast &&
        icon == other.icon &&
        lat == other.lat &&
        lng == other.lng &&
        location == other.location &&
        locationMatch == other.locationMatch &&
        outdoorStatus == other.outdoorStatus &&
        recordTime == other.recordTime &&
        source_ == other.source_ &&
        temp == other.temp;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, dust.hashCode);
    _$hash = $jc(_$hash, force.hashCode);
    _$hash = $jc(_$hash, forecast.hashCode);
    _$hash = $jc(_$hash, icon.hashCode);
    _$hash = $jc(_$hash, lat.hashCode);
    _$hash = $jc(_$hash, lng.hashCode);
    _$hash = $jc(_$hash, location.hashCode);
    _$hash = $jc(_$hash, locationMatch.hashCode);
    _$hash = $jc(_$hash, outdoorStatus.hashCode);
    _$hash = $jc(_$hash, recordTime.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, temp.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WeatherData')
          ..add('dust', dust)
          ..add('force', force)
          ..add('forecast', forecast)
          ..add('icon', icon)
          ..add('lat', lat)
          ..add('lng', lng)
          ..add('location', location)
          ..add('locationMatch', locationMatch)
          ..add('outdoorStatus', outdoorStatus)
          ..add('recordTime', recordTime)
          ..add('source_', source_)
          ..add('temp', temp))
        .toString();
  }
}

class WeatherDataBuilder implements Builder<WeatherData, WeatherDataBuilder> {
  _$WeatherData? _$v;

  DustBuilder? _dust;
  DustBuilder get dust => _$this._dust ??= DustBuilder();
  set dust(DustBuilder? dust) => _$this._dust = dust;

  bool? _force;
  bool? get force => _$this._force;
  set force(bool? force) => _$this._force = force;

  ListBuilder<ForecastItem>? _forecast;
  ListBuilder<ForecastItem> get forecast =>
      _$this._forecast ??= ListBuilder<ForecastItem>();
  set forecast(ListBuilder<ForecastItem>? forecast) =>
      _$this._forecast = forecast;

  String? _icon;
  String? get icon => _$this._icon;
  set icon(String? icon) => _$this._icon = icon;

  double? _lat;
  double? get lat => _$this._lat;
  set lat(double? lat) => _$this._lat = lat;

  double? _lng;
  double? get lng => _$this._lng;
  set lng(double? lng) => _$this._lng = lng;

  String? _location;
  String? get location => _$this._location;
  set location(String? location) => _$this._location = location;

  bool? _locationMatch;
  bool? get locationMatch => _$this._locationMatch;
  set locationMatch(bool? locationMatch) =>
      _$this._locationMatch = locationMatch;

  WeatherDataOutdoorStatusEnum? _outdoorStatus;
  WeatherDataOutdoorStatusEnum? get outdoorStatus => _$this._outdoorStatus;
  set outdoorStatus(WeatherDataOutdoorStatusEnum? outdoorStatus) =>
      _$this._outdoorStatus = outdoorStatus;

  String? _recordTime;
  String? get recordTime => _$this._recordTime;
  set recordTime(String? recordTime) => _$this._recordTime = recordTime;

  WeatherDataSource_Enum? _source_;
  WeatherDataSource_Enum? get source_ => _$this._source_;
  set source_(WeatherDataSource_Enum? source_) => _$this._source_ = source_;

  String? _temp;
  String? get temp => _$this._temp;
  set temp(String? temp) => _$this._temp = temp;

  WeatherDataBuilder() {
    WeatherData._defaults(this);
  }

  WeatherDataBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _dust = $v.dust.toBuilder();
      _force = $v.force;
      _forecast = $v.forecast.toBuilder();
      _icon = $v.icon;
      _lat = $v.lat;
      _lng = $v.lng;
      _location = $v.location;
      _locationMatch = $v.locationMatch;
      _outdoorStatus = $v.outdoorStatus;
      _recordTime = $v.recordTime;
      _source_ = $v.source_;
      _temp = $v.temp;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WeatherData other) {
    _$v = other as _$WeatherData;
  }

  @override
  void update(void Function(WeatherDataBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WeatherData build() => _build();

  _$WeatherData _build() {
    _$WeatherData _$result;
    try {
      _$result = _$v ??
          _$WeatherData._(
            dust: dust.build(),
            force: BuiltValueNullFieldError.checkNotNull(
                force, r'WeatherData', 'force'),
            forecast: forecast.build(),
            icon: BuiltValueNullFieldError.checkNotNull(
                icon, r'WeatherData', 'icon'),
            lat: BuiltValueNullFieldError.checkNotNull(
                lat, r'WeatherData', 'lat'),
            lng: BuiltValueNullFieldError.checkNotNull(
                lng, r'WeatherData', 'lng'),
            location: location,
            locationMatch: locationMatch,
            outdoorStatus: BuiltValueNullFieldError.checkNotNull(
                outdoorStatus, r'WeatherData', 'outdoorStatus'),
            recordTime: recordTime,
            source_: BuiltValueNullFieldError.checkNotNull(
                source_, r'WeatherData', 'source_'),
            temp: BuiltValueNullFieldError.checkNotNull(
                temp, r'WeatherData', 'temp'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'dust';
        dust.build();

        _$failedField = 'forecast';
        forecast.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'WeatherData', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
