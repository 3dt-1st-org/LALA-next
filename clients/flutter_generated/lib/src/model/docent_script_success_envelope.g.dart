// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'docent_script_success_envelope.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DocentScriptSuccessEnvelope extends DocentScriptSuccessEnvelope {
  @override
  final DocentScriptData data;
  @override
  final ApiError error;
  @override
  final ApiMeta meta;
  @override
  final bool ok;

  factory _$DocentScriptSuccessEnvelope(
          [void Function(DocentScriptSuccessEnvelopeBuilder)? updates]) =>
      (DocentScriptSuccessEnvelopeBuilder()..update(updates))._build();

  _$DocentScriptSuccessEnvelope._(
      {required this.data,
      required this.error,
      required this.meta,
      required this.ok})
      : super._();
  @override
  DocentScriptSuccessEnvelope rebuild(
          void Function(DocentScriptSuccessEnvelopeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DocentScriptSuccessEnvelopeBuilder toBuilder() =>
      DocentScriptSuccessEnvelopeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DocentScriptSuccessEnvelope &&
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
    return (newBuiltValueToStringHelper(r'DocentScriptSuccessEnvelope')
          ..add('data', data)
          ..add('error', error)
          ..add('meta', meta)
          ..add('ok', ok))
        .toString();
  }
}

class DocentScriptSuccessEnvelopeBuilder
    implements
        Builder<DocentScriptSuccessEnvelope,
            DocentScriptSuccessEnvelopeBuilder> {
  _$DocentScriptSuccessEnvelope? _$v;

  DocentScriptDataBuilder? _data;
  DocentScriptDataBuilder get data =>
      _$this._data ??= DocentScriptDataBuilder();
  set data(DocentScriptDataBuilder? data) => _$this._data = data;

  ApiErrorBuilder? _error;
  ApiErrorBuilder get error => _$this._error ??= ApiErrorBuilder();
  set error(ApiErrorBuilder? error) => _$this._error = error;

  ApiMetaBuilder? _meta;
  ApiMetaBuilder get meta => _$this._meta ??= ApiMetaBuilder();
  set meta(ApiMetaBuilder? meta) => _$this._meta = meta;

  bool? _ok;
  bool? get ok => _$this._ok;
  set ok(bool? ok) => _$this._ok = ok;

  DocentScriptSuccessEnvelopeBuilder() {
    DocentScriptSuccessEnvelope._defaults(this);
  }

  DocentScriptSuccessEnvelopeBuilder get _$this {
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
  void replace(DocentScriptSuccessEnvelope other) {
    _$v = other as _$DocentScriptSuccessEnvelope;
  }

  @override
  void update(void Function(DocentScriptSuccessEnvelopeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DocentScriptSuccessEnvelope build() => _build();

  _$DocentScriptSuccessEnvelope _build() {
    _$DocentScriptSuccessEnvelope _$result;
    try {
      _$result = _$v ??
          _$DocentScriptSuccessEnvelope._(
            data: data.build(),
            error: error.build(),
            meta: meta.build(),
            ok: BuiltValueNullFieldError.checkNotNull(
                ok, r'DocentScriptSuccessEnvelope', 'ok'),
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
            r'DocentScriptSuccessEnvelope', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
