// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'healthz_success_envelope.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$HealthzSuccessEnvelope extends HealthzSuccessEnvelope {
  @override
  final HealthzData data;
  @override
  final JsonObject? error;
  @override
  final ApiMeta meta;
  @override
  final bool ok;

  factory _$HealthzSuccessEnvelope(
          [void Function(HealthzSuccessEnvelopeBuilder)? updates]) =>
      (HealthzSuccessEnvelopeBuilder()..update(updates))._build();

  _$HealthzSuccessEnvelope._(
      {required this.data, this.error, required this.meta, required this.ok})
      : super._();
  @override
  HealthzSuccessEnvelope rebuild(
          void Function(HealthzSuccessEnvelopeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HealthzSuccessEnvelopeBuilder toBuilder() =>
      HealthzSuccessEnvelopeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HealthzSuccessEnvelope &&
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
    return (newBuiltValueToStringHelper(r'HealthzSuccessEnvelope')
          ..add('data', data)
          ..add('error', error)
          ..add('meta', meta)
          ..add('ok', ok))
        .toString();
  }
}

class HealthzSuccessEnvelopeBuilder
    implements Builder<HealthzSuccessEnvelope, HealthzSuccessEnvelopeBuilder> {
  _$HealthzSuccessEnvelope? _$v;

  HealthzDataBuilder? _data;
  HealthzDataBuilder get data => _$this._data ??= HealthzDataBuilder();
  set data(HealthzDataBuilder? data) => _$this._data = data;

  JsonObject? _error;
  JsonObject? get error => _$this._error;
  set error(JsonObject? error) => _$this._error = error;

  ApiMetaBuilder? _meta;
  ApiMetaBuilder get meta => _$this._meta ??= ApiMetaBuilder();
  set meta(ApiMetaBuilder? meta) => _$this._meta = meta;

  bool? _ok;
  bool? get ok => _$this._ok;
  set ok(bool? ok) => _$this._ok = ok;

  HealthzSuccessEnvelopeBuilder() {
    HealthzSuccessEnvelope._defaults(this);
  }

  HealthzSuccessEnvelopeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _data = $v.data.toBuilder();
      _error = $v.error;
      _meta = $v.meta.toBuilder();
      _ok = $v.ok;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HealthzSuccessEnvelope other) {
    _$v = other as _$HealthzSuccessEnvelope;
  }

  @override
  void update(void Function(HealthzSuccessEnvelopeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HealthzSuccessEnvelope build() => _build();

  _$HealthzSuccessEnvelope _build() {
    _$HealthzSuccessEnvelope _$result;
    try {
      _$result = _$v ??
          _$HealthzSuccessEnvelope._(
            data: data.build(),
            error: error,
            meta: meta.build(),
            ok: BuiltValueNullFieldError.checkNotNull(
                ok, r'HealthzSuccessEnvelope', 'ok'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'data';
        data.build();

        _$failedField = 'meta';
        meta.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'HealthzSuccessEnvelope', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
