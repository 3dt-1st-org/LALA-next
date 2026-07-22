// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_deletion_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const AccountDeletionRequestConfirmationEnum
    _$accountDeletionRequestConfirmationEnum_deleteMyAccount =
    const AccountDeletionRequestConfirmationEnum._('deleteMyAccount');

AccountDeletionRequestConfirmationEnum
    _$accountDeletionRequestConfirmationEnumValueOf(String name) {
  switch (name) {
    case 'deleteMyAccount':
      return _$accountDeletionRequestConfirmationEnum_deleteMyAccount;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<AccountDeletionRequestConfirmationEnum>
    _$accountDeletionRequestConfirmationEnumValues = BuiltSet<
        AccountDeletionRequestConfirmationEnum>(const <AccountDeletionRequestConfirmationEnum>[
  _$accountDeletionRequestConfirmationEnum_deleteMyAccount,
]);

Serializer<AccountDeletionRequestConfirmationEnum>
    _$accountDeletionRequestConfirmationEnumSerializer =
    _$AccountDeletionRequestConfirmationEnumSerializer();

class _$AccountDeletionRequestConfirmationEnumSerializer
    implements PrimitiveSerializer<AccountDeletionRequestConfirmationEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'deleteMyAccount': 'delete-my-account',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'delete-my-account': 'deleteMyAccount',
  };

  @override
  final Iterable<Type> types = const <Type>[
    AccountDeletionRequestConfirmationEnum
  ];
  @override
  final String wireName = 'AccountDeletionRequestConfirmationEnum';

  @override
  Object serialize(Serializers serializers,
          AccountDeletionRequestConfirmationEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  AccountDeletionRequestConfirmationEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      AccountDeletionRequestConfirmationEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$AccountDeletionRequest extends AccountDeletionRequest {
  @override
  final AccountDeletionRequestConfirmationEnum confirmation;

  factory _$AccountDeletionRequest(
          [void Function(AccountDeletionRequestBuilder)? updates]) =>
      (AccountDeletionRequestBuilder()..update(updates))._build();

  _$AccountDeletionRequest._({required this.confirmation}) : super._();
  @override
  AccountDeletionRequest rebuild(
          void Function(AccountDeletionRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AccountDeletionRequestBuilder toBuilder() =>
      AccountDeletionRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AccountDeletionRequest &&
        confirmation == other.confirmation;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, confirmation.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AccountDeletionRequest')
          ..add('confirmation', confirmation))
        .toString();
  }
}

class AccountDeletionRequestBuilder
    implements Builder<AccountDeletionRequest, AccountDeletionRequestBuilder> {
  _$AccountDeletionRequest? _$v;

  AccountDeletionRequestConfirmationEnum? _confirmation;
  AccountDeletionRequestConfirmationEnum? get confirmation =>
      _$this._confirmation;
  set confirmation(AccountDeletionRequestConfirmationEnum? confirmation) =>
      _$this._confirmation = confirmation;

  AccountDeletionRequestBuilder() {
    AccountDeletionRequest._defaults(this);
  }

  AccountDeletionRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _confirmation = $v.confirmation;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AccountDeletionRequest other) {
    _$v = other as _$AccountDeletionRequest;
  }

  @override
  void update(void Function(AccountDeletionRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AccountDeletionRequest build() => _build();

  _$AccountDeletionRequest _build() {
    final _$result = _$v ??
        _$AccountDeletionRequest._(
          confirmation: BuiltValueNullFieldError.checkNotNull(
              confirmation, r'AccountDeletionRequest', 'confirmation'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
