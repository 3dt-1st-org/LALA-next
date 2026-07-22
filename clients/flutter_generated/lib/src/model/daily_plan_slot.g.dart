// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_plan_slot.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DailyPlanSlot extends DailyPlanSlot {
  @override
  final String period;
  @override
  final Place? place;
  @override
  final String title;
  @override
  final String? weatherHint;

  factory _$DailyPlanSlot([void Function(DailyPlanSlotBuilder)? updates]) =>
      (DailyPlanSlotBuilder()..update(updates))._build();

  _$DailyPlanSlot._(
      {required this.period, this.place, required this.title, this.weatherHint})
      : super._();
  @override
  DailyPlanSlot rebuild(void Function(DailyPlanSlotBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DailyPlanSlotBuilder toBuilder() => DailyPlanSlotBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DailyPlanSlot &&
        period == other.period &&
        place == other.place &&
        title == other.title &&
        weatherHint == other.weatherHint;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, period.hashCode);
    _$hash = $jc(_$hash, place.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, weatherHint.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DailyPlanSlot')
          ..add('period', period)
          ..add('place', place)
          ..add('title', title)
          ..add('weatherHint', weatherHint))
        .toString();
  }
}

class DailyPlanSlotBuilder
    implements Builder<DailyPlanSlot, DailyPlanSlotBuilder> {
  _$DailyPlanSlot? _$v;

  String? _period;
  String? get period => _$this._period;
  set period(String? period) => _$this._period = period;

  PlaceBuilder? _place;
  PlaceBuilder get place => _$this._place ??= PlaceBuilder();
  set place(PlaceBuilder? place) => _$this._place = place;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _weatherHint;
  String? get weatherHint => _$this._weatherHint;
  set weatherHint(String? weatherHint) => _$this._weatherHint = weatherHint;

  DailyPlanSlotBuilder() {
    DailyPlanSlot._defaults(this);
  }

  DailyPlanSlotBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _period = $v.period;
      _place = $v.place?.toBuilder();
      _title = $v.title;
      _weatherHint = $v.weatherHint;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DailyPlanSlot other) {
    _$v = other as _$DailyPlanSlot;
  }

  @override
  void update(void Function(DailyPlanSlotBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DailyPlanSlot build() => _build();

  _$DailyPlanSlot _build() {
    _$DailyPlanSlot _$result;
    try {
      _$result = _$v ??
          _$DailyPlanSlot._(
            period: BuiltValueNullFieldError.checkNotNull(
                period, r'DailyPlanSlot', 'period'),
            place: _place?.build(),
            title: BuiltValueNullFieldError.checkNotNull(
                title, r'DailyPlanSlot', 'title'),
            weatherHint: weatherHint,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'place';
        _place?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'DailyPlanSlot', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
