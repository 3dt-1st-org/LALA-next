// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_error.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiError extends ApiError {
  @override
  final String code;
  @override
  final JsonObject? details;
  @override
  final String message;
  @override
  final bool retryable;

  factory _$ApiError([void Function(ApiErrorBuilder)? updates]) =>
      (ApiErrorBuilder()..update(updates))._build();

  _$ApiError._(
      {required this.code,
      this.details,
      required this.message,
      required this.retryable})
      : super._();
  @override
  ApiError rebuild(void Function(ApiErrorBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiErrorBuilder toBuilder() => ApiErrorBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiError &&
        code == other.code &&
        details == other.details &&
        message == other.message &&
        retryable == other.retryable;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, details.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jc(_$hash, retryable.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApiError')
          ..add('code', code)
          ..add('details', details)
          ..add('message', message)
          ..add('retryable', retryable))
        .toString();
  }
}

class ApiErrorBuilder implements Builder<ApiError, ApiErrorBuilder> {
  _$ApiError? _$v;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  JsonObject? _details;
  JsonObject? get details => _$this._details;
  set details(JsonObject? details) => _$this._details = details;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  bool? _retryable;
  bool? get retryable => _$this._retryable;
  set retryable(bool? retryable) => _$this._retryable = retryable;

  ApiErrorBuilder() {
    ApiError._defaults(this);
  }

  ApiErrorBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _code = $v.code;
      _details = $v.details;
      _message = $v.message;
      _retryable = $v.retryable;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApiError other) {
    _$v = other as _$ApiError;
  }

  @override
  void update(void Function(ApiErrorBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiError build() => _build();

  _$ApiError _build() {
    final _$result = _$v ??
        _$ApiError._(
          code:
              BuiltValueNullFieldError.checkNotNull(code, r'ApiError', 'code'),
          details: details,
          message: BuiltValueNullFieldError.checkNotNull(
              message, r'ApiError', 'message'),
          retryable: BuiltValueNullFieldError.checkNotNull(
              retryable, r'ApiError', 'retryable'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
