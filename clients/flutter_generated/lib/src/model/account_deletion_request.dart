//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'account_deletion_request.g.dart';

/// AccountDeletionRequest
///
/// Properties:
/// * [confirmation] 
@BuiltValue()
abstract class AccountDeletionRequest implements Built<AccountDeletionRequest, AccountDeletionRequestBuilder> {
  @BuiltValueField(wireName: r'confirmation')
  AccountDeletionRequestConfirmationEnum get confirmation;
  // enum confirmationEnum {  delete-my-account,  };

  AccountDeletionRequest._();

  factory AccountDeletionRequest([void updates(AccountDeletionRequestBuilder b)]) = _$AccountDeletionRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AccountDeletionRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AccountDeletionRequest> get serializer => _$AccountDeletionRequestSerializer();
}

class _$AccountDeletionRequestSerializer implements PrimitiveSerializer<AccountDeletionRequest> {
  @override
  final Iterable<Type> types = const [AccountDeletionRequest, _$AccountDeletionRequest];

  @override
  final String wireName = r'AccountDeletionRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AccountDeletionRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'confirmation';
    yield serializers.serialize(
      object.confirmation,
      specifiedType: const FullType(AccountDeletionRequestConfirmationEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AccountDeletionRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AccountDeletionRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'confirmation':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AccountDeletionRequestConfirmationEnum),
          ) as AccountDeletionRequestConfirmationEnum;
          result.confirmation = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AccountDeletionRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AccountDeletionRequestBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

class AccountDeletionRequestConfirmationEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'delete-my-account')
  static const AccountDeletionRequestConfirmationEnum deleteMyAccount = _$accountDeletionRequestConfirmationEnum_deleteMyAccount;

  static Serializer<AccountDeletionRequestConfirmationEnum> get serializer => _$accountDeletionRequestConfirmationEnumSerializer;

  const AccountDeletionRequestConfirmationEnum._(String name): super(name);

  static BuiltSet<AccountDeletionRequestConfirmationEnum> get values => _$accountDeletionRequestConfirmationEnumValues;
  static AccountDeletionRequestConfirmationEnum valueOf(String name) => _$accountDeletionRequestConfirmationEnumValueOf(name);
}

