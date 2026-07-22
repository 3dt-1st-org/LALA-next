// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_error_envelope.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiErrorEnvelope extends ApiErrorEnvelope {
  @override
  final JsonObject? data;
  @override
  final ApiError error;
  @override
  final ApiMeta meta;
  @override
  final bool ok;

  factory _$ApiErrorEnvelope(
          [void Function(ApiErrorEnvelopeBuilder)? updates]) =>
      (ApiErrorEnvelopeBuilder()..update(updates))._build();

  _$ApiErrorEnvelope._(
      {this.data, required this.error, required this.meta, required this.ok})
      : super._();
  @override
  ApiErrorEnvelope rebuild(void Function(ApiErrorEnvelopeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiErrorEnvelopeBuilder toBuilder() =>
      ApiErrorEnvelopeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiErrorEnvelope &&
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
    return (newBuiltValueToStringHelper(r'ApiErrorEnvelope')
          ..add('data', data)
          ..add('error', error)
          ..add('meta', meta)
          ..add('ok', ok))
        .toString();
  }
}

class ApiErrorEnvelopeBuilder
    implements Builder<ApiErrorEnvelope, ApiErrorEnvelopeBuilder> {
  _$ApiErrorEnvelope? _$v;

  JsonObject? _data;
  JsonObject? get data => _$this._data;
  set data(JsonObject? data) => _$this._data = data;

  ApiErrorBuilder? _error;
  ApiErrorBuilder get error => _$this._error ??= ApiErrorBuilder();
  set error(ApiErrorBuilder? error) => _$this._error = error;

  ApiMetaBuilder? _meta;
  ApiMetaBuilder get meta => _$this._meta ??= ApiMetaBuilder();
  set meta(ApiMetaBuilder? meta) => _$this._meta = meta;

  bool? _ok;
  bool? get ok => _$this._ok;
  set ok(bool? ok) => _$this._ok = ok;

  ApiErrorEnvelopeBuilder() {
    ApiErrorEnvelope._defaults(this);
  }

  ApiErrorEnvelopeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _data = $v.data;
      _error = $v.error.toBuilder();
      _meta = $v.meta.toBuilder();
      _ok = $v.ok;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApiErrorEnvelope other) {
    _$v = other as _$ApiErrorEnvelope;
  }

  @override
  void update(void Function(ApiErrorEnvelopeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiErrorEnvelope build() => _build();

  _$ApiErrorEnvelope _build() {
    _$ApiErrorEnvelope _$result;
    try {
      _$result = _$v ??
          _$ApiErrorEnvelope._(
            data: data,
            error: error.build(),
            meta: meta.build(),
            ok: BuiltValueNullFieldError.checkNotNull(
                ok, r'ApiErrorEnvelope', 'ok'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'error';
        error.build();
        _$failedField = 'meta';
        meta.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ApiErrorEnvelope', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
