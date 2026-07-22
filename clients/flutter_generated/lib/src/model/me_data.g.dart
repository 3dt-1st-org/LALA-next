// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'me_data.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MeData extends MeData {
  @override
  final bool authenticated;
  @override
  final DateTime createdAt;
  @override
  final String userId;

  factory _$MeData([void Function(MeDataBuilder)? updates]) =>
      (MeDataBuilder()..update(updates))._build();

  _$MeData._(
      {required this.authenticated,
      required this.createdAt,
      required this.userId})
      : super._();
  @override
  MeData rebuild(void Function(MeDataBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MeDataBuilder toBuilder() => MeDataBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MeData &&
        authenticated == other.authenticated &&
        createdAt == other.createdAt &&
        userId == other.userId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, authenticated.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, userId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MeData')
          ..add('authenticated', authenticated)
          ..add('createdAt', createdAt)
          ..add('userId', userId))
        .toString();
  }
}

class MeDataBuilder implements Builder<MeData, MeDataBuilder> {
  _$MeData? _$v;

  bool? _authenticated;
  bool? get authenticated => _$this._authenticated;
  set authenticated(bool? authenticated) =>
      _$this._authenticated = authenticated;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  String? _userId;
  String? get userId => _$this._userId;
  set userId(String? userId) => _$this._userId = userId;

  MeDataBuilder() {
    MeData._defaults(this);
  }

  MeDataBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _authenticated = $v.authenticated;
      _createdAt = $v.createdAt;
      _userId = $v.userId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MeData other) {
    _$v = other as _$MeData;
  }

  @override
  void update(void Function(MeDataBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MeData build() => _build();

  _$MeData _build() {
    final _$result = _$v ??
        _$MeData._(
          authenticated: BuiltValueNullFieldError.checkNotNull(
              authenticated, r'MeData', 'authenticated'),
          createdAt: BuiltValueNullFieldError.checkNotNull(
              createdAt, r'MeData', 'createdAt'),
          userId: BuiltValueNullFieldError.checkNotNull(
              userId, r'MeData', 'userId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
