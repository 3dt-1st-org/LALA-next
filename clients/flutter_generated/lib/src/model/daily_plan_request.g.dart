// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_plan_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DailyPlanRequest extends DailyPlanRequest {
  @override
  final String? language;
  @override
  final num lat;
  @override
  final num lng;
  @override
  final int? radiusM;

  factory _$DailyPlanRequest(
          [void Function(DailyPlanRequestBuilder)? updates]) =>
      (DailyPlanRequestBuilder()..update(updates))._build();

  _$DailyPlanRequest._(
      {this.language, required this.lat, required this.lng, this.radiusM})
      : super._();
  @override
  DailyPlanRequest rebuild(void Function(DailyPlanRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DailyPlanRequestBuilder toBuilder() =>
      DailyPlanRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DailyPlanRequest &&
        language == other.language &&
        lat == other.lat &&
        lng == other.lng &&
        radiusM == other.radiusM;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, language.hashCode);
    _$hash = $jc(_$hash, lat.hashCode);
    _$hash = $jc(_$hash, lng.hashCode);
    _$hash = $jc(_$hash, radiusM.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DailyPlanRequest')
          ..add('language', language)
          ..add('lat', lat)
          ..add('lng', lng)
          ..add('radiusM', radiusM))
        .toString();
  }
}

class DailyPlanRequestBuilder
    implements Builder<DailyPlanRequest, DailyPlanRequestBuilder> {
  _$DailyPlanRequest? _$v;

  String? _language;
  String? get language => _$this._language;
  set language(String? language) => _$this._language = language;

  num? _lat;
  num? get lat => _$this._lat;
  set lat(num? lat) => _$this._lat = lat;

  num? _lng;
  num? get lng => _$this._lng;
  set lng(num? lng) => _$this._lng = lng;

  int? _radiusM;
  int? get radiusM => _$this._radiusM;
  set radiusM(int? radiusM) => _$this._radiusM = radiusM;

  DailyPlanRequestBuilder() {
    DailyPlanRequest._defaults(this);
  }

  DailyPlanRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _language = $v.language;
      _lat = $v.lat;
      _lng = $v.lng;
      _radiusM = $v.radiusM;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DailyPlanRequest other) {
    _$v = other as _$DailyPlanRequest;
  }

  @override
  void update(void Function(DailyPlanRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DailyPlanRequest build() => _build();

  _$DailyPlanRequest _build() {
    final _$result = _$v ??
        _$DailyPlanRequest._(
          language: language,
          lat: BuiltValueNullFieldError.checkNotNull(
              lat, r'DailyPlanRequest', 'lat'),
          lng: BuiltValueNullFieldError.checkNotNull(
              lng, r'DailyPlanRequest', 'lng'),
          radiusM: radiusM,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
