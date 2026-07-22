// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_meta.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApiMeta extends ApiMeta {
  @override
  final String requestId;

  factory _$ApiMeta([void Function(ApiMetaBuilder)? updates]) =>
      (ApiMetaBuilder()..update(updates))._build();

  _$ApiMeta._({required this.requestId}) : super._();
  @override
  ApiMeta rebuild(void Function(ApiMetaBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApiMetaBuilder toBuilder() => ApiMetaBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApiMeta && requestId == other.requestId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, requestId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApiMeta')
          ..add('requestId', requestId))
        .toString();
  }
}

class ApiMetaBuilder implements Builder<ApiMeta, ApiMetaBuilder> {
  _$ApiMeta? _$v;

  String? _requestId;
  String? get requestId => _$this._requestId;
  set requestId(String? requestId) => _$this._requestId = requestId;

  ApiMetaBuilder() {
    ApiMeta._defaults(this);
  }

  ApiMetaBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _requestId = $v.requestId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApiMeta other) {
    _$v = other as _$ApiMeta;
  }

  @override
  void update(void Function(ApiMetaBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApiMeta build() => _build();

  _$ApiMeta _build() {
    final _$result = _$v ??
        _$ApiMeta._(
          requestId: BuiltValueNullFieldError.checkNotNull(
              requestId, r'ApiMeta', 'requestId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
