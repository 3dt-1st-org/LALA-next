// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'me_success_envelope.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MeSuccessEnvelope extends MeSuccessEnvelope {
  @override
  final MeData data;
  @override
  final ApiError error;
  @override
  final ApiMeta meta;
  @override
  final bool ok;

  factory _$MeSuccessEnvelope(
          [void Function(MeSuccessEnvelopeBuilder)? updates]) =>
      (MeSuccessEnvelopeBuilder()..update(updates))._build();

  _$MeSuccessEnvelope._(
      {required this.data,
      required this.error,
      required this.meta,
      required this.ok})
      : super._();
  @override
  MeSuccessEnvelope rebuild(void Function(MeSuccessEnvelopeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MeSuccessEnvelopeBuilder toBuilder() =>
      MeSuccessEnvelopeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MeSuccessEnvelope &&
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
    return (newBuiltValueToStringHelper(r'MeSuccessEnvelope')
          ..add('data', data)
          ..add('error', error)
          ..add('meta', meta)
          ..add('ok', ok))
        .toString();
  }
}

class MeSuccessEnvelopeBuilder
    implements Builder<MeSuccessEnvelope, MeSuccessEnvelopeBuilder> {
  _$MeSuccessEnvelope? _$v;

  MeDataBuilder? _data;
  MeDataBuilder get data => _$this._data ??= MeDataBuilder();
  set data(MeDataBuilder? data) => _$this._data = data;

  ApiErrorBuilder? _error;
  ApiErrorBuilder get error => _$this._error ??= ApiErrorBuilder();
  set error(ApiErrorBuilder? error) => _$this._error = error;

  ApiMetaBuilder? _meta;
  ApiMetaBuilder get meta => _$this._meta ??= ApiMetaBuilder();
  set meta(ApiMetaBuilder? meta) => _$this._meta = meta;

  bool? _ok;
  bool? get ok => _$this._ok;
  set ok(bool? ok) => _$this._ok = ok;

  MeSuccessEnvelopeBuilder() {
    MeSuccessEnvelope._defaults(this);
  }

  MeSuccessEnvelopeBuilder get _$this {
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
  void replace(MeSuccessEnvelope other) {
    _$v = other as _$MeSuccessEnvelope;
  }

  @override
  void update(void Function(MeSuccessEnvelopeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MeSuccessEnvelope build() => _build();

  _$MeSuccessEnvelope _build() {
    _$MeSuccessEnvelope _$result;
    try {
      _$result = _$v ??
          _$MeSuccessEnvelope._(
            data: data.build(),
            error: error.build(),
            meta: meta.build(),
            ok: BuiltValueNullFieldError.checkNotNull(
                ok, r'MeSuccessEnvelope', 'ok'),
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
            r'MeSuccessEnvelope', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
