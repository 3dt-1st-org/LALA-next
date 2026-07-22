// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'places_data.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const PlacesDataLocationEngineEnum _$placesDataLocationEngineEnum_postgis =
    const PlacesDataLocationEngineEnum._('postgis');
const PlacesDataLocationEngineEnum
    _$placesDataLocationEngineEnum_staticSnapshot =
    const PlacesDataLocationEngineEnum._('staticSnapshot');
const PlacesDataLocationEngineEnum _$placesDataLocationEngineEnum_none =
    const PlacesDataLocationEngineEnum._('none');

PlacesDataLocationEngineEnum _$placesDataLocationEngineEnumValueOf(
    String name) {
  switch (name) {
    case 'postgis':
      return _$placesDataLocationEngineEnum_postgis;
    case 'staticSnapshot':
      return _$placesDataLocationEngineEnum_staticSnapshot;
    case 'none':
      return _$placesDataLocationEngineEnum_none;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<PlacesDataLocationEngineEnum>
    _$placesDataLocationEngineEnumValues =
    BuiltSet<PlacesDataLocationEngineEnum>(const <PlacesDataLocationEngineEnum>[
  _$placesDataLocationEngineEnum_postgis,
  _$placesDataLocationEngineEnum_staticSnapshot,
  _$placesDataLocationEngineEnum_none,
]);

const PlacesDataSource_Enum _$placesDataSourceEnum_publicMvpSnapshot =
    const PlacesDataSource_Enum._('publicMvpSnapshot');
const PlacesDataSource_Enum _$placesDataSourceEnum_db =
    const PlacesDataSource_Enum._('db');

PlacesDataSource_Enum _$placesDataSourceEnumValueOf(String name) {
  switch (name) {
    case 'publicMvpSnapshot':
      return _$placesDataSourceEnum_publicMvpSnapshot;
    case 'db':
      return _$placesDataSourceEnum_db;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<PlacesDataSource_Enum> _$placesDataSourceEnumValues =
    BuiltSet<PlacesDataSource_Enum>(const <PlacesDataSource_Enum>[
  _$placesDataSourceEnum_publicMvpSnapshot,
  _$placesDataSourceEnum_db,
]);

Serializer<PlacesDataLocationEngineEnum>
    _$placesDataLocationEngineEnumSerializer =
    _$PlacesDataLocationEngineEnumSerializer();
Serializer<PlacesDataSource_Enum> _$placesDataSourceEnumSerializer =
    _$PlacesDataSource_EnumSerializer();

class _$PlacesDataLocationEngineEnumSerializer
    implements PrimitiveSerializer<PlacesDataLocationEngineEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'postgis': 'postgis',
    'staticSnapshot': 'static_snapshot',
    'none': 'none',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'postgis': 'postgis',
    'static_snapshot': 'staticSnapshot',
    'none': 'none',
  };

  @override
  final Iterable<Type> types = const <Type>[PlacesDataLocationEngineEnum];
  @override
  final String wireName = 'PlacesDataLocationEngineEnum';

  @override
  Object serialize(Serializers serializers, PlacesDataLocationEngineEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  PlacesDataLocationEngineEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      PlacesDataLocationEngineEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$PlacesDataSource_EnumSerializer
    implements PrimitiveSerializer<PlacesDataSource_Enum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'publicMvpSnapshot': 'public_mvp_snapshot',
    'db': 'db',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'public_mvp_snapshot': 'publicMvpSnapshot',
    'db': 'db',
  };

  @override
  final Iterable<Type> types = const <Type>[PlacesDataSource_Enum];
  @override
  final String wireName = 'PlacesDataSource_Enum';

  @override
  Object serialize(Serializers serializers, PlacesDataSource_Enum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  PlacesDataSource_Enum deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      PlacesDataSource_Enum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$PlacesData extends PlacesData {
  @override
  final int count;
  @override
  final PlacesDataLocationEngineEnum locationEngine;
  @override
  final BuiltList<Place> places;
  @override
  final PlacesQuery query;
  @override
  final PlacesDataSource_Enum source_;

  factory _$PlacesData([void Function(PlacesDataBuilder)? updates]) =>
      (PlacesDataBuilder()..update(updates))._build();

  _$PlacesData._(
      {required this.count,
      required this.locationEngine,
      required this.places,
      required this.query,
      required this.source_})
      : super._();
  @override
  PlacesData rebuild(void Function(PlacesDataBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlacesDataBuilder toBuilder() => PlacesDataBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlacesData &&
        count == other.count &&
        locationEngine == other.locationEngine &&
        places == other.places &&
        query == other.query &&
        source_ == other.source_;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, count.hashCode);
    _$hash = $jc(_$hash, locationEngine.hashCode);
    _$hash = $jc(_$hash, places.hashCode);
    _$hash = $jc(_$hash, query.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlacesData')
          ..add('count', count)
          ..add('locationEngine', locationEngine)
          ..add('places', places)
          ..add('query', query)
          ..add('source_', source_))
        .toString();
  }
}

class PlacesDataBuilder implements Builder<PlacesData, PlacesDataBuilder> {
  _$PlacesData? _$v;

  int? _count;
  int? get count => _$this._count;
  set count(int? count) => _$this._count = count;

  PlacesDataLocationEngineEnum? _locationEngine;
  PlacesDataLocationEngineEnum? get locationEngine => _$this._locationEngine;
  set locationEngine(PlacesDataLocationEngineEnum? locationEngine) =>
      _$this._locationEngine = locationEngine;

  ListBuilder<Place>? _places;
  ListBuilder<Place> get places => _$this._places ??= ListBuilder<Place>();
  set places(ListBuilder<Place>? places) => _$this._places = places;

  PlacesQueryBuilder? _query;
  PlacesQueryBuilder get query => _$this._query ??= PlacesQueryBuilder();
  set query(PlacesQueryBuilder? query) => _$this._query = query;

  PlacesDataSource_Enum? _source_;
  PlacesDataSource_Enum? get source_ => _$this._source_;
  set source_(PlacesDataSource_Enum? source_) => _$this._source_ = source_;

  PlacesDataBuilder() {
    PlacesData._defaults(this);
  }

  PlacesDataBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _count = $v.count;
      _locationEngine = $v.locationEngine;
      _places = $v.places.toBuilder();
      _query = $v.query.toBuilder();
      _source_ = $v.source_;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlacesData other) {
    _$v = other as _$PlacesData;
  }

  @override
  void update(void Function(PlacesDataBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlacesData build() => _build();

  _$PlacesData _build() {
    _$PlacesData _$result;
    try {
      _$result = _$v ??
          _$PlacesData._(
            count: BuiltValueNullFieldError.checkNotNull(
                count, r'PlacesData', 'count'),
            locationEngine: BuiltValueNullFieldError.checkNotNull(
                locationEngine, r'PlacesData', 'locationEngine'),
            places: places.build(),
            query: query.build(),
            source_: BuiltValueNullFieldError.checkNotNull(
                source_, r'PlacesData', 'source_'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'places';
        places.build();
        _$failedField = 'query';
        query.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'PlacesData', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
