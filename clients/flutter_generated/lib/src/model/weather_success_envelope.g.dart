// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather_success_envelope.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WeatherSuccessEnvelope extends WeatherSuccessEnvelope {
  @override
  final WeatherData data;
  @override
  final ApiError error;
  @override
  final ApiMeta meta;
  @override
  final bool ok;

  factory _$WeatherSuccessEnvelope(
          [void Function(WeatherSuccessEnvelopeBuilder)? updates]) =>
      (WeatherSuccessEnvelopeBuilder()..update(updates))._build();

  _$WeatherSuccessEnvelope._(
      {required this.data,
      required this.error,
      required this.meta,
      required this.ok})
      : super._();
  @override
  WeatherSuccessEnvelope rebuild(
          void Function(WeatherSuccessEnvelopeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WeatherSuccessEnvelopeBuilder toBuilder() =>
      WeatherSuccessEnvelopeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WeatherSuccessEnvelope &&
        data == other.data &&
        error == other.error &&
        meta == other.meta &&
        ok == other.ok;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, data.hashCode);
    _$hash = $jc(_$hash, error.hashCode);
    _$hash = $jc(_$hash, meta.hashCode);
    _$hash = $jc(_$hash, ok.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WeatherSuccessEnvelope')
          ..add('data', data)
          ..add('error', error)
          ..add('meta', meta)
          ..add('ok', ok))
        .toString();
  }
}

class WeatherSuccessEnvelopeBuilder
    implements Builder<WeatherSuccessEnvelope, WeatherSuccessEnvelopeBuilder> {
  _$WeatherSuccessEnvelope? _$v;

  WeatherDataBuilder? _data;
  WeatherDataBuilder get data => _$this._data ??= WeatherDataBuilder();
  set data(WeatherDataBuilder? data) => _$this._data = data;

  ApiErrorBuilder? _error;
  ApiErrorBuilder get error => _$this._error ??= ApiErrorBuilder();
  set error(ApiErrorBuilder? error) => _$this._error = error;

  ApiMetaBuilder? _meta;
  ApiMetaBuilder get meta => _$this._meta ??= ApiMetaBuilder();
  set meta(ApiMetaBuilder? meta) => _$this._meta = meta;

  bool? _ok;
  bool? get ok => _$this._ok;
  set ok(bool? ok) => _$this._ok = ok;

  WeatherSuccessEnvelopeBuilder() {
    WeatherSuccessEnvelope._defaults(this);
  }

  WeatherSuccessEnvelopeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _data = $v.data.toBuilder();
      _error = $v.error.toBuilder();
      _meta = $v.meta.toBuilder();
      _ok = $v.ok;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WeatherSuccessEnvelope other) {
    _$v = other as _$WeatherSuccessEnvelope;
  }

  @override
  void update(void Function(WeatherSuccessEnvelopeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WeatherSuccessEnvelope build() => _build();

  _$WeatherSuccessEnvelope _build() {
    _$WeatherSuccessEnvelope _$result;
    try {
      _$result = _$v ??
          _$WeatherSuccessEnvelope._(
            data: data.build(),
            error: error.build(),
            meta: meta.build(),
            ok: BuiltValueNullFieldError.checkNotNull(
                ok, r'WeatherSuccessEnvelope', 'ok'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'data';
        data.build();
        _$failedField = 'error';
        error.build();
        _$failedField = 'meta';
        meta.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'WeatherSuccessEnvelope', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
