// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'places_query.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const PlacesQueryCategoryEnum _$placesQueryCategoryEnum_all =
    const PlacesQueryCategoryEnum._('all');
const PlacesQueryCategoryEnum _$placesQueryCategoryEnum_attraction =
    const PlacesQueryCategoryEnum._('attraction');
const PlacesQueryCategoryEnum _$placesQueryCategoryEnum_restaurant =
    const PlacesQueryCategoryEnum._('restaurant');
const PlacesQueryCategoryEnum _$placesQueryCategoryEnum_event =
    const PlacesQueryCategoryEnum._('event');
const PlacesQueryCategoryEnum _$placesQueryCategoryEnum_cultureVenue =
    const PlacesQueryCategoryEnum._('cultureVenue');

PlacesQueryCategoryEnum _$placesQueryCategoryEnumValueOf(String name) {
  switch (name) {
    case 'all':
      return _$placesQueryCategoryEnum_all;
    case 'attraction':
      return _$placesQueryCategoryEnum_attraction;
    case 'restaurant':
      return _$placesQueryCategoryEnum_restaurant;
    case 'event':
      return _$placesQueryCategoryEnum_event;
    case 'cultureVenue':
      return _$placesQueryCategoryEnum_cultureVenue;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<PlacesQueryCategoryEnum> _$placesQueryCategoryEnumValues =
    BuiltSet<PlacesQueryCategoryEnum>(const <PlacesQueryCategoryEnum>[
  _$placesQueryCategoryEnum_all,
  _$placesQueryCategoryEnum_attraction,
  _$placesQueryCategoryEnum_restaurant,
  _$placesQueryCategoryEnum_event,
  _$placesQueryCategoryEnum_cultureVenue,
]);

const PlacesQueryLanguageEnum _$placesQueryLanguageEnum_ko =
    const PlacesQueryLanguageEnum._('ko');
const PlacesQueryLanguageEnum _$placesQueryLanguageEnum_en =
    const PlacesQueryLanguageEnum._('en');

PlacesQueryLanguageEnum _$placesQueryLanguageEnumValueOf(String name) {
  switch (name) {
    case 'ko':
      return _$placesQueryLanguageEnum_ko;
    case 'en':
      return _$placesQueryLanguageEnum_en;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<PlacesQueryLanguageEnum> _$placesQueryLanguageEnumValues =
    BuiltSet<PlacesQueryLanguageEnum>(const <PlacesQueryLanguageEnum>[
  _$placesQueryLanguageEnum_ko,
  _$placesQueryLanguageEnum_en,
]);

Serializer<PlacesQueryCategoryEnum> _$placesQueryCategoryEnumSerializer =
    _$PlacesQueryCategoryEnumSerializer();
Serializer<PlacesQueryLanguageEnum> _$placesQueryLanguageEnumSerializer =
    _$PlacesQueryLanguageEnumSerializer();

class _$PlacesQueryCategoryEnumSerializer
    implements PrimitiveSerializer<PlacesQueryCategoryEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'all': 'all',
    'attraction': 'attraction',
    'restaurant': 'restaurant',
    'event': 'event',
    'cultureVenue': 'culture_venue',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'all': 'all',
    'attraction': 'attraction',
    'restaurant': 'restaurant',
    'event': 'event',
    'culture_venue': 'cultureVenue',
  };

  @override
  final Iterable<Type> types = const <Type>[PlacesQueryCategoryEnum];
  @override
  final String wireName = 'PlacesQueryCategoryEnum';

  @override
  Object serialize(Serializers serializers, PlacesQueryCategoryEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  PlacesQueryCategoryEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      PlacesQueryCategoryEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$PlacesQueryLanguageEnumSerializer
    implements PrimitiveSerializer<PlacesQueryLanguageEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'ko': 'ko',
    'en': 'en',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'ko': 'ko',
    'en': 'en',
  };

  @override
  final Iterable<Type> types = const <Type>[PlacesQueryLanguageEnum];
  @override
  final String wireName = 'PlacesQueryLanguageEnum';

  @override
  Object serialize(Serializers serializers, PlacesQueryLanguageEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  PlacesQueryLanguageEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      PlacesQueryLanguageEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$PlacesQuery extends PlacesQuery {
  @override
  final PlacesQueryCategoryEnum category;
  @override
  final bool includeScores;
  @override
  final PlacesQueryLanguageEnum language;
  @override
  final double lat;
  @override
  final int limit;
  @override
  final double lng;
  @override
  final int radiusM;

  factory _$PlacesQuery([void Function(PlacesQueryBuilder)? updates]) =>
      (PlacesQueryBuilder()..update(updates))._build();

  _$PlacesQuery._(
      {required this.category,
      required this.includeScores,
      required this.language,
      required this.lat,
      required this.limit,
      required this.lng,
      required this.radiusM})
      : super._();
  @override
  PlacesQuery rebuild(void Function(PlacesQueryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlacesQueryBuilder toBuilder() => PlacesQueryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlacesQuery &&
        category == other.category &&
        includeScores == other.includeScores &&
        language == other.language &&
        lat == other.lat &&
        limit == other.limit &&
        lng == other.lng &&
        radiusM == other.radiusM;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, includeScores.hashCode);
    _$hash = $jc(_$hash, language.hashCode);
    _$hash = $jc(_$hash, lat.hashCode);
    _$hash = $jc(_$hash, limit.hashCode);
    _$hash = $jc(_$hash, lng.hashCode);
    _$hash = $jc(_$hash, radiusM.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PlacesQuery')
          ..add('category', category)
          ..add('includeScores', includeScores)
          ..add('language', language)
          ..add('lat', lat)
          ..add('limit', limit)
          ..add('lng', lng)
          ..add('radiusM', radiusM))
        .toString();
  }
}

class PlacesQueryBuilder implements Builder<PlacesQuery, PlacesQueryBuilder> {
  _$PlacesQuery? _$v;

  PlacesQueryCategoryEnum? _category;
  PlacesQueryCategoryEnum? get category => _$this._category;
  set category(PlacesQueryCategoryEnum? category) =>
      _$this._category = category;

  bool? _includeScores;
  bool? get includeScores => _$this._includeScores;
  set includeScores(bool? includeScores) =>
      _$this._includeScores = includeScores;

  PlacesQueryLanguageEnum? _language;
  PlacesQueryLanguageEnum? get language => _$this._language;
  set language(PlacesQueryLanguageEnum? language) =>
      _$this._language = language;

  double? _lat;
  double? get lat => _$this._lat;
  set lat(double? lat) => _$this._lat = lat;

  int? _limit;
  int? get limit => _$this._limit;
  set limit(int? limit) => _$this._limit = limit;

  double? _lng;
  double? get lng => _$this._lng;
  set lng(double? lng) => _$this._lng = lng;

  int? _radiusM;
  int? get radiusM => _$this._radiusM;
  set radiusM(int? radiusM) => _$this._radiusM = radiusM;

  PlacesQueryBuilder() {
    PlacesQuery._defaults(this);
  }

  PlacesQueryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _category = $v.category;
      _includeScores = $v.includeScores;
      _language = $v.language;
      _lat = $v.lat;
      _limit = $v.limit;
      _lng = $v.lng;
      _radiusM = $v.radiusM;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PlacesQuery other) {
    _$v = other as _$PlacesQuery;
  }

  @override
  void update(void Function(PlacesQueryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlacesQuery build() => _build();

  _$PlacesQuery _build() {
    final _$result = _$v ??
        _$PlacesQuery._(
          category: BuiltValueNullFieldError.checkNotNull(
              category, r'PlacesQuery', 'category'),
          includeScores: BuiltValueNullFieldError.checkNotNull(
              includeScores, r'PlacesQuery', 'includeScores'),
          language: BuiltValueNullFieldError.checkNotNull(
              language, r'PlacesQuery', 'language'),
          lat:
              BuiltValueNullFieldError.checkNotNull(lat, r'PlacesQuery', 'lat'),
          limit: BuiltValueNullFieldError.checkNotNull(
              limit, r'PlacesQuery', 'limit'),
          lng:
              BuiltValueNullFieldError.checkNotNull(lng, r'PlacesQuery', 'lng'),
          radiusM: BuiltValueNullFieldError.checkNotNull(
              radiusM, r'PlacesQuery', 'radiusM'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
