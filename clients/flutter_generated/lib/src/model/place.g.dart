// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'place.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const PlaceCategoryEnum _$placeCategoryEnum_attraction =
    const PlaceCategoryEnum._('attraction');
const PlaceCategoryEnum _$placeCategoryEnum_restaurant =
    const PlaceCategoryEnum._('restaurant');
const PlaceCategoryEnum _$placeCategoryEnum_event =
    const PlaceCategoryEnum._('event');
const PlaceCategoryEnum _$placeCategoryEnum_cultureVenue =
    const PlaceCategoryEnum._('cultureVenue');

PlaceCategoryEnum _$placeCategoryEnumValueOf(String name) {
  switch (name) {
    case 'attraction':
      return _$placeCategoryEnum_attraction;
    case 'restaurant':
      return _$placeCategoryEnum_restaurant;
    case 'event':
      return _$placeCategoryEnum_event;
    case 'cultureVenue':
      return _$placeCategoryEnum_cultureVenue;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<PlaceCategoryEnum> _$placeCategoryEnumValues =
    BuiltSet<PlaceCategoryEnum>(const <PlaceCategoryEnum>[
  _$placeCategoryEnum_attraction,
  _$placeCategoryEnum_restaurant,
  _$placeCategoryEnum_event,
  _$placeCategoryEnum_cultureVenue,
]);

const PlaceSource_Enum _$placeSourceEnum_publicMvpSnapshot =
    const PlaceSource_Enum._('publicMvpSnapshot');
const PlaceSource_Enum _$placeSourceEnum_db = const PlaceSource_Enum._('db');

PlaceSource_Enum _$placeSourceEnumValueOf(String name) {
  switch (name) {
    case 'publicMvpSnapshot':
      return _$placeSourceEnum_publicMvpSnapshot;
    case 'db':
      return _$placeSourceEnum_db;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<PlaceSource_Enum> _$placeSourceEnumValues =
    BuiltSet<PlaceSource_Enum>(const <PlaceSource_Enum>[
  _$placeSourceEnum_publicMvpSnapshot,
  _$placeSourceEnum_db,
]);

Serializer<PlaceCategoryEnum> _$placeCategoryEnumSerializer =
    _$PlaceCategoryEnumSerializer();
Serializer<PlaceSource_Enum> _$placeSourceEnumSerializer =
    _$PlaceSource_EnumSerializer();

class _$PlaceCategoryEnumSerializer
    implements PrimitiveSerializer<PlaceCategoryEnum> {
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
  final Iterable<Type> types = const <Type>[PlaceCategoryEnum];
  @override
  final String wireName = 'PlaceCategoryEnum';

  @override
  Object serialize(Serializers serializers, PlaceCategoryEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  PlaceCategoryEnum deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      PlaceCategoryEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$PlaceSource_EnumSerializer
    implements PrimitiveSerializer<PlaceSource_Enum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'publicMvpSnapshot': 'public_mvp_snapshot',
    'db': 'db',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'public_mvp_snapshot': 'publicMvpSnapshot',
    'db': 'db',
  };

  @override
  final Iterable<Type> types = const <Type>[PlaceSource_Enum];
  @override
  final String wireName = 'PlaceSource_Enum';

  @override
  Object serialize(Serializers serializers, PlaceSource_Enum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  PlaceSource_Enum deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      PlaceSource_Enum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$Place extends Place {
  @override
  final String? address;
  @override
  final PlaceCategoryEnum category;
  @override
  final int distanceM;
  @override
  final Date? eventEndDate;
  @override
  final Date? eventStartDate;
  @override
  final String? eventUrl;
  @override
  final String? imageUrl;
  @override
  final bool? isApproximateLocation;
  @override
  final bool? isOngoing;
  @override
  final double lat;
  @override
  final double lng;
  @override
  final String? name;
  @override
  final String? nameEn;
  @override
  final String? nameKo;
  @override
  final String? placeId;
  @override
  final String? regionEn;
  @override
  final String? regionKo;
  @override
  final PlaceScore? score;
  @override
  final PlaceSource_Enum source_;
  @override
  final String? upstreamSource;

  factory _$Place([void Function(PlaceBuilder)? updates]) =>
      (PlaceBuilder()..update(updates))._build();

  _$Place._(
      {this.address,
      required this.category,
      required this.distanceM,
      this.eventEndDate,
      this.eventStartDate,
      this.eventUrl,
      this.imageUrl,
      this.isApproximateLocation,
      this.isOngoing,
      required this.lat,
      required this.lng,
      this.name,
      this.nameEn,
      this.nameKo,
      this.placeId,
      this.regionEn,
      this.regionKo,
      this.score,
      required this.source_,
      this.upstreamSource})
      : super._();
  @override
  Place rebuild(void Function(PlaceBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlaceBuilder toBuilder() => PlaceBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Place &&
        address == other.address &&
        category == other.category &&
        distanceM == other.distanceM &&
        eventEndDate == other.eventEndDate &&
        eventStartDate == other.eventStartDate &&
        eventUrl == other.eventUrl &&
        imageUrl == other.imageUrl &&
        isApproximateLocation == other.isApproximateLocation &&
        isOngoing == other.isOngoing &&
        lat == other.lat &&
        lng == other.lng &&
        name == other.name &&
        nameEn == other.nameEn &&
        nameKo == other.nameKo &&
        placeId == other.placeId &&
        regionEn == other.regionEn &&
        regionKo == other.regionKo &&
        score == other.score &&
        source_ == other.source_ &&
        upstreamSource == other.upstreamSource;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, address.hashCode);
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, distanceM.hashCode);
    _$hash = $jc(_$hash, eventEndDate.hashCode);
    _$hash = $jc(_$hash, eventStartDate.hashCode);
    _$hash = $jc(_$hash, eventUrl.hashCode);
    _$hash = $jc(_$hash, imageUrl.hashCode);
    _$hash = $jc(_$hash, isApproximateLocation.hashCode);
    _$hash = $jc(_$hash, isOngoing.hashCode);
    _$hash = $jc(_$hash, lat.hashCode);
    _$hash = $jc(_$hash, lng.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, nameEn.hashCode);
    _$hash = $jc(_$hash, nameKo.hashCode);
    _$hash = $jc(_$hash, placeId.hashCode);
    _$hash = $jc(_$hash, regionEn.hashCode);
    _$hash = $jc(_$hash, regionKo.hashCode);
    _$hash = $jc(_$hash, score.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, upstreamSource.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Place')
          ..add('address', address)
          ..add('category', category)
          ..add('distanceM', distanceM)
          ..add('eventEndDate', eventEndDate)
          ..add('eventStartDate', eventStartDate)
          ..add('eventUrl', eventUrl)
          ..add('imageUrl', imageUrl)
          ..add('isApproximateLocation', isApproximateLocation)
          ..add('isOngoing', isOngoing)
          ..add('lat', lat)
          ..add('lng', lng)
          ..add('name', name)
          ..add('nameEn', nameEn)
          ..add('nameKo', nameKo)
          ..add('placeId', placeId)
          ..add('regionEn', regionEn)
          ..add('regionKo', regionKo)
          ..add('score', score)
          ..add('source_', source_)
          ..add('upstreamSource', upstreamSource))
        .toString();
  }
}

class PlaceBuilder implements Builder<Place, PlaceBuilder> {
  _$Place? _$v;

  String? _address;
  String? get address => _$this._address;
  set address(String? address) => _$this._address = address;

  PlaceCategoryEnum? _category;
  PlaceCategoryEnum? get category => _$this._category;
  set category(PlaceCategoryEnum? category) => _$this._category = category;

  int? _distanceM;
  int? get distanceM => _$this._distanceM;
  set distanceM(int? distanceM) => _$this._distanceM = distanceM;

  Date? _eventEndDate;
  Date? get eventEndDate => _$this._eventEndDate;
  set eventEndDate(Date? eventEndDate) => _$this._eventEndDate = eventEndDate;

  Date? _eventStartDate;
  Date? get eventStartDate => _$this._eventStartDate;
  set eventStartDate(Date? eventStartDate) =>
      _$this._eventStartDate = eventStartDate;

  String? _eventUrl;
  String? get eventUrl => _$this._eventUrl;
  set eventUrl(String? eventUrl) => _$this._eventUrl = eventUrl;

  String? _imageUrl;
  String? get imageUrl => _$this._imageUrl;
  set imageUrl(String? imageUrl) => _$this._imageUrl = imageUrl;

  bool? _isApproximateLocation;
  bool? get isApproximateLocation => _$this._isApproximateLocation;
  set isApproximateLocation(bool? isApproximateLocation) =>
      _$this._isApproximateLocation = isApproximateLocation;

  bool? _isOngoing;
  bool? get isOngoing => _$this._isOngoing;
  set isOngoing(bool? isOngoing) => _$this._isOngoing = isOngoing;

  double? _lat;
  double? get lat => _$this._lat;
  set lat(double? lat) => _$this._lat = lat;

  double? _lng;
  double? get lng => _$this._lng;
  set lng(double? lng) => _$this._lng = lng;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _nameEn;
  String? get nameEn => _$this._nameEn;
  set nameEn(String? nameEn) => _$this._nameEn = nameEn;

  String? _nameKo;
  String? get nameKo => _$this._nameKo;
  set nameKo(String? nameKo) => _$this._nameKo = nameKo;

  String? _placeId;
  String? get placeId => _$this._placeId;
  set placeId(String? placeId) => _$this._placeId = placeId;

  String? _regionEn;
  String? get regionEn => _$this._regionEn;
  set regionEn(String? regionEn) => _$this._regionEn = regionEn;

  String? _regionKo;
  String? get regionKo => _$this._regionKo;
  set regionKo(String? regionKo) => _$this._regionKo = regionKo;

  PlaceScoreBuilder? _score;
  PlaceScoreBuilder get score => _$this._score ??= PlaceScoreBuilder();
  set score(PlaceScoreBuilder? score) => _$this._score = score;

  PlaceSource_Enum? _source_;
  PlaceSource_Enum? get source_ => _$this._source_;
  set source_(PlaceSource_Enum? source_) => _$this._source_ = source_;

  String? _upstreamSource;
  String? get upstreamSource => _$this._upstreamSource;
  set upstreamSource(String? upstreamSource) =>
      _$this._upstreamSource = upstreamSource;

  PlaceBuilder() {
    Place._defaults(this);
  }

  PlaceBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _address = $v.address;
      _category = $v.category;
      _distanceM = $v.distanceM;
      _eventEndDate = $v.eventEndDate;
      _eventStartDate = $v.eventStartDate;
      _eventUrl = $v.eventUrl;
      _imageUrl = $v.imageUrl;
      _isApproximateLocation = $v.isApproximateLocation;
      _isOngoing = $v.isOngoing;
      _lat = $v.lat;
      _lng = $v.lng;
      _name = $v.name;
      _nameEn = $v.nameEn;
      _nameKo = $v.nameKo;
      _placeId = $v.placeId;
      _regionEn = $v.regionEn;
      _regionKo = $v.regionKo;
      _score = $v.score?.toBuilder();
      _source_ = $v.source_;
      _upstreamSource = $v.upstreamSource;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Place other) {
    _$v = other as _$Place;
  }

  @override
  void update(void Function(PlaceBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Place build() => _build();

  _$Place _build() {
    _$Place _$result;
    try {
      _$result = _$v ??
          _$Place._(
            address: address,
            category: BuiltValueNullFieldError.checkNotNull(
                category, r'Place', 'category'),
            distanceM: BuiltValueNullFieldError.checkNotNull(
                distanceM, r'Place', 'distanceM'),
            eventEndDate: eventEndDate,
            eventStartDate: eventStartDate,
            eventUrl: eventUrl,
            imageUrl: imageUrl,
            isApproximateLocation: isApproximateLocation,
            isOngoing: isOngoing,
            lat: BuiltValueNullFieldError.checkNotNull(lat, r'Place', 'lat'),
            lng: BuiltValueNullFieldError.checkNotNull(lng, r'Place', 'lng'),
            name: name,
            nameEn: nameEn,
            nameKo: nameKo,
            placeId: placeId,
            regionEn: regionEn,
            regionKo: regionKo,
            score: _score?.build(),
            source_: BuiltValueNullFieldError.checkNotNull(
                source_, r'Place', 'source_'),
            upstreamSource: upstreamSource,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'score';
        _score?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'Place', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
