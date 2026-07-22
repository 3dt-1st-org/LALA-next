// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_success_envelope.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiSuccessEnvelope extends ApiSuccessEnvelope {
  @override
  final JsonObject data;
  @override
  final ApiError error;
  @override
  final ApiMeta meta;
  @override
  final bool ok;

  factory _$ApiSuccessEnvelope(
          [void Function(ApiSuccessEnvelopeBuilder)? updates]) =>
      (ApiSuccessEnvelopeBuilder()..update(updates))._build();

  _$ApiSuccessEnvelope._(
      {required this.data,
      required this.error,
      required this.meta,
      required this.ok})
      : super._();
  @override
  ApiSuccessEnvelope rebuild(
          void Function(ApiSuccessEnvelopeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiSuccessEnvelopeBuilder toBuilder() =>
      ApiSuccessEnvelopeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiSuccessEnvelope &&
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
    return (newBuiltValueToStringHelper(r'ApiSuccessEnvelope')
          ..add('data', data)
          ..add('error', error)
          ..add('meta', meta)
          ..add('ok', ok))
        .toString();
  }
}

class ApiSuccessEnvelopeBuilder
    implements Builder<ApiSuccessEnvelope, ApiSuccessEnvelopeBuilder> {
  _$ApiSuccessEnvelope? _$v;

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

  ApiSuccessEnvelopeBuilder() {
    ApiSuccessEnvelope._defaults(this);
  }

  ApiSuccessEnvelopeBuilder get _$this {
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
  void replace(ApiSuccessEnvelope other) {
    _$v = other as _$ApiSuccessEnvelope;
  }

  @override
  void update(void Function(ApiSuccessEnvelopeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiSuccessEnvelope build() => _build();

  _$ApiSuccessEnvelope _build() {
    _$ApiSuccessEnvelope _$result;
    try {
      _$result = _$v ??
          _$ApiSuccessEnvelope._(
            data: BuiltValueNullFieldError.checkNotNull(
                data, r'ApiSuccessEnvelope', 'data'),
            error: error.build(),
            meta: meta.build(),
            ok: BuiltValueNullFieldError.checkNotNull(
                ok, r'ApiSuccessEnvelope', 'ok'),
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
            r'ApiSuccessEnvelope', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
