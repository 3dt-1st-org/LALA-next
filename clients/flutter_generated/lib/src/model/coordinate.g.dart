// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'coordinate.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Coordinate extends Coordinate {
  @override
  final double lat;
  @override
  final double lng;

  factory _$Coordinate([void Function(CoordinateBuilder)? updates]) =>
      (CoordinateBuilder()..update(updates))._build();

  _$Coordinate._({required this.lat, required this.lng}) : super._();
  @override
  Coordinate rebuild(void Function(CoordinateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CoordinateBuilder toBuilder() => CoordinateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Coordinate && lat == other.lat && lng == other.lng;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, lat.hashCode);
    _$hash = $jc(_$hash, lng.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Coordinate')
          ..add('lat', lat)
          ..add('lng', lng))
        .toString();
  }
}

class CoordinateBuilder implements Builder<Coordinate, CoordinateBuilder> {
  _$Coordinate? _$v;

  double? _lat;
  double? get lat => _$this._lat;
  set lat(double? lat) => _$this._lat = lat;

  double? _lng;
  double? get lng => _$this._lng;
  set lng(double? lng) => _$this._lng = lng;

  CoordinateBuilder() {
    Coordinate._defaults(this);
  }

  CoordinateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _lat = $v.lat;
      _lng = $v.lng;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Coordinate other) {
    _$v = other as _$Coordinate;
  }

  @override
  void update(void Function(CoordinateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Coordinate build() => _build();

  _$Coordinate _build() {
    final _$result = _$v ??
        _$Coordinate._(
          lat: BuiltValueNullFieldError.checkNotNull(lat, r'Coordinate', 'lat'),
          lng: BuiltValueNullFieldError.checkNotNull(lng, r'Coordinate', 'lng'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
