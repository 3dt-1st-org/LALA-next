// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'healthz_data.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const HealthzDataServiceEnum _$healthzDataServiceEnum_lalaNextApi =
    const HealthzDataServiceEnum._('lalaNextApi');

HealthzDataServiceEnum _$healthzDataServiceEnumValueOf(String name) {
  switch (name) {
    case 'lalaNextApi':
      return _$healthzDataServiceEnum_lalaNextApi;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<HealthzDataServiceEnum> _$healthzDataServiceEnumValues =
    BuiltSet<HealthzDataServiceEnum>(const <HealthzDataServiceEnum>[
  _$healthzDataServiceEnum_lalaNextApi,
]);

const HealthzDataStatusEnum _$healthzDataStatusEnum_ok =
    const HealthzDataStatusEnum._('ok');

HealthzDataStatusEnum _$healthzDataStatusEnumValueOf(String name) {
  switch (name) {
    case 'ok':
      return _$healthzDataStatusEnum_ok;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<HealthzDataStatusEnum> _$healthzDataStatusEnumValues =
    BuiltSet<HealthzDataStatusEnum>(const <HealthzDataStatusEnum>[
  _$healthzDataStatusEnum_ok,
]);

Serializer<HealthzDataServiceEnum> _$healthzDataServiceEnumSerializer =
    _$HealthzDataServiceEnumSerializer();
Serializer<HealthzDataStatusEnum> _$healthzDataStatusEnumSerializer =
    _$HealthzDataStatusEnumSerializer();

class _$HealthzDataServiceEnumSerializer
    implements PrimitiveSerializer<HealthzDataServiceEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'lalaNextApi': 'lala-next-api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'lala-next-api': 'lalaNextApi',
  };

  @override
  final Iterable<Type> types = const <Type>[HealthzDataServiceEnum];
  @override
  final String wireName = 'HealthzDataServiceEnum';

  @override
  Object serialize(Serializers serializers, HealthzDataServiceEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  HealthzDataServiceEnum deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      HealthzDataServiceEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$HealthzDataStatusEnumSerializer
    implements PrimitiveSerializer<HealthzDataStatusEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'ok': 'ok',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'ok': 'ok',
  };

  @override
  final Iterable<Type> types = const <Type>[HealthzDataStatusEnum];
  @override
  final String wireName = 'HealthzDataStatusEnum';

  @override
  Object serialize(Serializers serializers, HealthzDataStatusEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  HealthzDataStatusEnum deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      HealthzDataStatusEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$HealthzData extends HealthzData {
  @override
  final HealthzDataServiceEnum service;
  @override
  final HealthzDataStatusEnum status;
  @override
  final String version;

  factory _$HealthzData([void Function(HealthzDataBuilder)? updates]) =>
      (HealthzDataBuilder()..update(updates))._build();

  _$HealthzData._(
      {required this.service, required this.status, required this.version})
      : super._();
  @override
  HealthzData rebuild(void Function(HealthzDataBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HealthzDataBuilder toBuilder() => HealthzDataBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HealthzData &&
        service == other.service &&
        status == other.status &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, service.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HealthzData')
          ..add('service', service)
          ..add('status', status)
          ..add('version', version))
        .toString();
  }
}

class HealthzDataBuilder implements Builder<HealthzData, HealthzDataBuilder> {
  _$HealthzData? _$v;

  HealthzDataServiceEnum? _service;
  HealthzDataServiceEnum? get service => _$this._service;
  set service(HealthzDataServiceEnum? service) => _$this._service = service;

  HealthzDataStatusEnum? _status;
  HealthzDataStatusEnum? get status => _$this._status;
  set status(HealthzDataStatusEnum? status) => _$this._status = status;

  String? _version;
  String? get version => _$this._version;
  set version(String? version) => _$this._version = version;

  HealthzDataBuilder() {
    HealthzData._defaults(this);
  }

  HealthzDataBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _service = $v.service;
      _status = $v.status;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HealthzData other) {
    _$v = other as _$HealthzData;
  }

  @override
  void update(void Function(HealthzDataBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HealthzData build() => _build();

  _$HealthzData _build() {
    final _$result = _$v ??
        _$HealthzData._(
          service: BuiltValueNullFieldError.checkNotNull(
              service, r'HealthzData', 'service'),
          status: BuiltValueNullFieldError.checkNotNull(
              status, r'HealthzData', 'status'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'HealthzData', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
