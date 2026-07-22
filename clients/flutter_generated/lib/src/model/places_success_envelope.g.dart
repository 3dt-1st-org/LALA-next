// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'places_success_envelope.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PlacesSuccessEnvelope extends PlacesSuccessEnvelope {
  @override
  final PlacesData data;
  @override
  final ApiError error;
  @override
  final ApiMeta meta;
  @override
  final bool ok;

  factory _$PlacesSuccessEnvelope(
          [void Function(PlacesSuccessEnvelopeBuilder)? updates]) =>
      (PlacesSuccessEnvelopeBuilder()..update(updates))._build();

  _$PlacesSuccessEnvelope._(
      {required this.data,
      required this.error,
      required this.meta,
      required this.ok})
      : super._();
  @override
  PlacesSuccessEnvelope rebuild(
          void Function(PlacesSuccessEnvelopeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PlacesSuccessEnvelopeBuilder toBuilder() =>
      PlacesSuccessEnvelopeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PlacesSuccessEnvelope &&
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
    return (newBuiltValueToStringHelper(r'PlacesSuccessEnvelope')
          ..add('data', data)
          ..add('error', error)
          ..add('meta', meta)
          ..add('ok', ok))
        .toString();
  }
}

class PlacesSuccessEnvelopeBuilder
    implements Builder<PlacesSuccessEnvelope, PlacesSuccessEnvelopeBuilder> {
  _$PlacesSuccessEnvelope? _$v;

  PlacesDataBuilder? _data;
  PlacesDataBuilder get data => _$this._data ??= PlacesDataBuilder();
  set data(PlacesDataBuilder? data) => _$this._data = data;

  ApiErrorBuilder? _error;
  ApiErrorBuilder get error => _$this._error ??= ApiErrorBuilder();
  set error(ApiErrorBuilder? error) => _$this._error = error;

  ApiMetaBuilder? _meta;
  ApiMetaBuilder get meta => _$this._meta ??= ApiMetaBuilder();
  set meta(ApiMetaBuilder? meta) => _$this._meta = meta;

  bool? _ok;
  bool? get ok => _$this._ok;
  set ok(bool? ok) => _$this._ok = ok;

  PlacesSuccessEnvelopeBuilder() {
    PlacesSuccessEnvelope._defaults(this);
  }

  PlacesSuccessEnvelopeBuilder get _$this {
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
  void replace(PlacesSuccessEnvelope other) {
    _$v = other as _$PlacesSuccessEnvelope;
  }

  @override
  void update(void Function(PlacesSuccessEnvelopeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PlacesSuccessEnvelope build() => _build();

  _$PlacesSuccessEnvelope _build() {
    _$PlacesSuccessEnvelope _$result;
    try {
      _$result = _$v ??
          _$PlacesSuccessEnvelope._(
            data: data.build(),
            error: error.build(),
            meta: meta.build(),
            ok: BuiltValueNullFieldError.checkNotNull(
                ok, r'PlacesSuccessEnvelope', 'ok'),
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
            r'PlacesSuccessEnvelope', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
