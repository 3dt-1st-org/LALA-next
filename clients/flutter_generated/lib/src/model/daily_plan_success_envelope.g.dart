// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_plan_success_envelope.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DailyPlanSuccessEnvelope extends DailyPlanSuccessEnvelope {
  @override
  final DailyPlanData data;
  @override
  final ApiError error;
  @override
  final ApiMeta meta;
  @override
  final bool ok;

  factory _$DailyPlanSuccessEnvelope(
          [void Function(DailyPlanSuccessEnvelopeBuilder)? updates]) =>
      (DailyPlanSuccessEnvelopeBuilder()..update(updates))._build();

  _$DailyPlanSuccessEnvelope._(
      {required this.data,
      required this.error,
      required this.meta,
      required this.ok})
      : super._();
  @override
  DailyPlanSuccessEnvelope rebuild(
          void Function(DailyPlanSuccessEnvelopeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DailyPlanSuccessEnvelopeBuilder toBuilder() =>
      DailyPlanSuccessEnvelopeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DailyPlanSuccessEnvelope &&
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
    return (newBuiltValueToStringHelper(r'DailyPlanSuccessEnvelope')
          ..add('data', data)
          ..add('error', error)
          ..add('meta', meta)
          ..add('ok', ok))
        .toString();
  }
}

class DailyPlanSuccessEnvelopeBuilder
    implements
        Builder<DailyPlanSuccessEnvelope, DailyPlanSuccessEnvelopeBuilder> {
  _$DailyPlanSuccessEnvelope? _$v;

  DailyPlanDataBuilder? _data;
  DailyPlanDataBuilder get data => _$this._data ??= DailyPlanDataBuilder();
  set data(DailyPlanDataBuilder? data) => _$this._data = data;

  ApiErrorBuilder? _error;
  ApiErrorBuilder get error => _$this._error ??= ApiErrorBuilder();
  set error(ApiErrorBuilder? error) => _$this._error = error;

  ApiMetaBuilder? _meta;
  ApiMetaBuilder get meta => _$this._meta ??= ApiMetaBuilder();
  set meta(ApiMetaBuilder? meta) => _$this._meta = meta;

  bool? _ok;
  bool? get ok => _$this._ok;
  set ok(bool? ok) => _$this._ok = ok;

  DailyPlanSuccessEnvelopeBuilder() {
    DailyPlanSuccessEnvelope._defaults(this);
  }

  DailyPlanSuccessEnvelopeBuilder get _$this {
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
  void replace(DailyPlanSuccessEnvelope other) {
    _$v = other as _$DailyPlanSuccessEnvelope;
  }

  @override
  void update(void Function(DailyPlanSuccessEnvelopeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DailyPlanSuccessEnvelope build() => _build();

  _$DailyPlanSuccessEnvelope _build() {
    _$DailyPlanSuccessEnvelope _$result;
    try {
      _$result = _$v ??
          _$DailyPlanSuccessEnvelope._(
            data: data.build(),
            error: error.build(),
            meta: meta.build(),
            ok: BuiltValueNullFieldError.checkNotNull(
                ok, r'DailyPlanSuccessEnvelope', 'ok'),
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
            r'DailyPlanSuccessEnvelope', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
