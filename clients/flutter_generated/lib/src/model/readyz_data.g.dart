// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'readyz_data.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ReadyzDataStatusEnum _$readyzDataStatusEnum_ok =
    const ReadyzDataStatusEnum._('ok');
const ReadyzDataStatusEnum _$readyzDataStatusEnum_degraded =
    const ReadyzDataStatusEnum._('degraded');

ReadyzDataStatusEnum _$readyzDataStatusEnumValueOf(String name) {
  switch (name) {
    case 'ok':
      return _$readyzDataStatusEnum_ok;
    case 'degraded':
      return _$readyzDataStatusEnum_degraded;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ReadyzDataStatusEnum> _$readyzDataStatusEnumValues =
    BuiltSet<ReadyzDataStatusEnum>(const <ReadyzDataStatusEnum>[
  _$readyzDataStatusEnum_ok,
  _$readyzDataStatusEnum_degraded,
]);

Serializer<ReadyzDataStatusEnum> _$readyzDataStatusEnumSerializer =
    _$ReadyzDataStatusEnumSerializer();

class _$ReadyzDataStatusEnumSerializer
    implements PrimitiveSerializer<ReadyzDataStatusEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'ok': 'ok',
    'degraded': 'degraded',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'ok': 'ok',
    'degraded': 'degraded',
  };

  @override
  final Iterable<Type> types = const <Type>[ReadyzDataStatusEnum];
  @override
  final String wireName = 'ReadyzDataStatusEnum';

  @override
  Object serialize(Serializers serializers, ReadyzDataStatusEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ReadyzDataStatusEnum deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ReadyzDataStatusEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ReadyzData extends ReadyzData {
  @override
  final ReadinessChecks checks;
  @override
  final RuntimeMode mode;
  @override
  final ReadyzDataStatusEnum status;

  factory _$ReadyzData([void Function(ReadyzDataBuilder)? updates]) =>
      (ReadyzDataBuilder()..update(updates))._build();

  _$ReadyzData._(
      {required this.checks, required this.mode, required this.status})
      : super._();
  @override
  ReadyzData rebuild(void Function(ReadyzDataBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ReadyzDataBuilder toBuilder() => ReadyzDataBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ReadyzData &&
        checks == other.checks &&
        mode == other.mode &&
        status == other.status;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, checks.hashCode);
    _$hash = $jc(_$hash, mode.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ReadyzData')
          ..add('checks', checks)
          ..add('mode', mode)
          ..add('status', status))
        .toString();
  }
}

class ReadyzDataBuilder implements Builder<ReadyzData, ReadyzDataBuilder> {
  _$ReadyzData? _$v;

  ReadinessChecksBuilder? _checks;
  ReadinessChecksBuilder get checks =>
      _$this._checks ??= ReadinessChecksBuilder();
  set checks(ReadinessChecksBuilder? checks) => _$this._checks = checks;

  RuntimeModeBuilder? _mode;
  RuntimeModeBuilder get mode => _$this._mode ??= RuntimeModeBuilder();
  set mode(RuntimeModeBuilder? mode) => _$this._mode = mode;

  ReadyzDataStatusEnum? _status;
  ReadyzDataStatusEnum? get status => _$this._status;
  set status(ReadyzDataStatusEnum? status) => _$this._status = status;

  ReadyzDataBuilder() {
    ReadyzData._defaults(this);
  }

  ReadyzDataBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _checks = $v.checks.toBuilder();
      _mode = $v.mode.toBuilder();
      _status = $v.status;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ReadyzData other) {
    _$v = other as _$ReadyzData;
  }

  @override
  void update(void Function(ReadyzDataBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ReadyzData build() => _build();

  _$ReadyzData _build() {
    _$ReadyzData _$result;
    try {
      _$result = _$v ??
          _$ReadyzData._(
            checks: checks.build(),
            mode: mode.build(),
            status: BuiltValueNullFieldError.checkNotNull(
                status, r'ReadyzData', 'status'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'checks';
        checks.build();
        _$failedField = 'mode';
        mode.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ReadyzData', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
