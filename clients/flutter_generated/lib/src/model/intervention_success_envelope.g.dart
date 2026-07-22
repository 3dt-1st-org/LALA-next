// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intervention_success_envelope.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$InterventionSuccessEnvelope extends InterventionSuccessEnvelope {
  @override
  final InterventionData data;
  @override
  final ApiError error;
  @override
  final ApiMeta meta;
  @override
  final bool ok;

  factory _$InterventionSuccessEnvelope(
          [void Function(InterventionSuccessEnvelopeBuilder)? updates]) =>
      (InterventionSuccessEnvelopeBuilder()..update(updates))._build();

  _$InterventionSuccessEnvelope._(
      {required this.data,
      required this.error,
      required this.meta,
      required this.ok})
      : super._();
  @override
  InterventionSuccessEnvelope rebuild(
          void Function(InterventionSuccessEnvelopeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  InterventionSuccessEnvelopeBuilder toBuilder() =>
      InterventionSuccessEnvelopeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is InterventionSuccessEnvelope &&
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
    return (newBuiltValueToStringHelper(r'InterventionSuccessEnvelope')
          ..add('data', data)
          ..add('error', error)
          ..add('meta', meta)
          ..add('ok', ok))
        .toString();
  }
}

class InterventionSuccessEnvelopeBuilder
    implements
        Builder<InterventionSuccessEnvelope,
            InterventionSuccessEnvelopeBuilder> {
  _$InterventionSuccessEnvelope? _$v;

  InterventionDataBuilder? _data;
  InterventionDataBuilder get data =>
      _$this._data ??= InterventionDataBuilder();
  set data(InterventionDataBuilder? data) => _$this._data = data;

  ApiErrorBuilder? _error;
  ApiErrorBuilder get error => _$this._error ??= ApiErrorBuilder();
  set error(ApiErrorBuilder? error) => _$this._error = error;

  ApiMetaBuilder? _meta;
  ApiMetaBuilder get meta => _$this._meta ??= ApiMetaBuilder();
  set meta(ApiMetaBuilder? meta) => _$this._meta = meta;

  bool? _ok;
  bool? get ok => _$this._ok;
  set ok(bool? ok) => _$this._ok = ok;

  InterventionSuccessEnvelopeBuilder() {
    InterventionSuccessEnvelope._defaults(this);
  }

  InterventionSuccessEnvelopeBuilder get _$this {
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
  void replace(InterventionSuccessEnvelope other) {
    _$v = other as _$InterventionSuccessEnvelope;
  }

  @override
  void update(void Function(InterventionSuccessEnvelopeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  InterventionSuccessEnvelope build() => _build();

  _$InterventionSuccessEnvelope _build() {
    _$InterventionSuccessEnvelope _$result;
    try {
      _$result = _$v ??
          _$InterventionSuccessEnvelope._(
            data: data.build(),
            error: error.build(),
            meta: meta.build(),
            ok: BuiltValueNullFieldError.checkNotNull(
                ok, r'InterventionSuccessEnvelope', 'ok'),
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
            r'InterventionSuccessEnvelope', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
