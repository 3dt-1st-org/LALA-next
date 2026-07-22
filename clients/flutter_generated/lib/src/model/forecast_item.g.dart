// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'forecast_item.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ForecastItem extends ForecastItem {
  @override
  final String icon;
  @override
  final String temp;
  @override
  final String time;

  factory _$ForecastItem([void Function(ForecastItemBuilder)? updates]) =>
      (ForecastItemBuilder()..update(updates))._build();

  _$ForecastItem._({required this.icon, required this.temp, required this.time})
      : super._();
  @override
  ForecastItem rebuild(void Function(ForecastItemBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ForecastItemBuilder toBuilder() => ForecastItemBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ForecastItem &&
        icon == other.icon &&
        temp == other.temp &&
        time == other.time;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, icon.hashCode);
    _$hash = $jc(_$hash, temp.hashCode);
    _$hash = $jc(_$hash, time.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ForecastItem')
          ..add('icon', icon)
          ..add('temp', temp)
          ..add('time', time))
        .toString();
  }
}

class ForecastItemBuilder
    implements Builder<ForecastItem, ForecastItemBuilder> {
  _$ForecastItem? _$v;

  String? _icon;
  String? get icon => _$this._icon;
  set icon(String? icon) => _$this._icon = icon;

  String? _temp;
  String? get temp => _$this._temp;
  set temp(String? temp) => _$this._temp = temp;

  String? _time;
  String? get time => _$this._time;
  set time(String? time) => _$this._time = time;

  ForecastItemBuilder() {
    ForecastItem._defaults(this);
  }

  ForecastItemBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _icon = $v.icon;
      _temp = $v.temp;
      _time = $v.time;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ForecastItem other) {
    _$v = other as _$ForecastItem;
  }

  @override
  void update(void Function(ForecastItemBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ForecastItem build() => _build();

  _$ForecastItem _build() {
    final _$result = _$v ??
        _$ForecastItem._(
          icon: BuiltValueNullFieldError.checkNotNull(
              icon, r'ForecastItem', 'icon'),
          temp: BuiltValueNullFieldError.checkNotNull(
              temp, r'ForecastItem', 'temp'),
          time: BuiltValueNullFieldError.checkNotNull(
              time, r'ForecastItem', 'time'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
