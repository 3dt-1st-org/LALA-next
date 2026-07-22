//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'readiness_checks.g.dart';

/// ReadinessChecks
///
/// Properties:
/// * [apiKey] 
/// * [azureOpenaiDeployment] 
/// * [azureOpenaiEndpoint] 
/// * [azureOpenaiKey] 
/// * [azureSpeechEndpoint] 
/// * [azureSpeechKey] 
/// * [azureSpeechRegion] 
/// * [bearerToken] 
/// * [clientAuth] 
/// * [clientIdentity] 
/// * [db] 
/// * [guestAccess] 
/// * [identitySchema] 
/// * [jwtValidation] 
/// * [keyVault] 
/// * [liveAi] 
/// * [liveSpeech] 
/// * [logtoManagement] 
/// * [oauthAudience] 
/// * [oauthClientId] 
/// * [oauthIssuer] 
/// * [oauthJwksUrl] 
/// * [oauthRequiredScopes] 
/// * [postgis] 
/// * [publicContestAccess] 
/// * [publicDataServiceKey] 
/// * [publicDataSnapshot] 
/// * [staticSnapshotFallback] 
/// * [workerContracts] 
@BuiltValue()
abstract class ReadinessChecks implements Built<ReadinessChecks, ReadinessChecksBuilder> {
  @BuiltValueField(wireName: r'api_key')
  ReadinessChecksApiKeyEnum get apiKey;
  // enum apiKeyEnum {  configured,  skipped,  };

  @BuiltValueField(wireName: r'azure_openai_deployment')
  ReadinessChecksAzureOpenaiDeploymentEnum get azureOpenaiDeployment;
  // enum azureOpenaiDeploymentEnum {  configured,  skipped,  };

  @BuiltValueField(wireName: r'azure_openai_endpoint')
  ReadinessChecksAzureOpenaiEndpointEnum get azureOpenaiEndpoint;
  // enum azureOpenaiEndpointEnum {  configured,  skipped,  };

  @BuiltValueField(wireName: r'azure_openai_key')
  ReadinessChecksAzureOpenaiKeyEnum get azureOpenaiKey;
  // enum azureOpenaiKeyEnum {  configured,  skipped,  };

  @BuiltValueField(wireName: r'azure_speech_endpoint')
  ReadinessChecksAzureSpeechEndpointEnum get azureSpeechEndpoint;
  // enum azureSpeechEndpointEnum {  configured,  skipped,  };

  @BuiltValueField(wireName: r'azure_speech_key')
  ReadinessChecksAzureSpeechKeyEnum get azureSpeechKey;
  // enum azureSpeechKeyEnum {  configured,  skipped,  };

  @BuiltValueField(wireName: r'azure_speech_region')
  ReadinessChecksAzureSpeechRegionEnum get azureSpeechRegion;
  // enum azureSpeechRegionEnum {  configured,  skipped,  };

  @BuiltValueField(wireName: r'bearer_token')
  ReadinessChecksBearerTokenEnum get bearerToken;
  // enum bearerTokenEnum {  configured,  skipped,  };

  @BuiltValueField(wireName: r'client_auth')
  ReadinessChecksClientAuthEnum get clientAuth;
  // enum clientAuthEnum {  configured,  missing,  snapshot-fallback,  public-contest,  };

  @BuiltValueField(wireName: r'client_identity')
  ReadinessChecksClientIdentityEnum get clientIdentity;
  // enum clientIdentityEnum {  guest,  static,  transition,  oauth-configured,  snapshot-fallback,  public-contest,  missing,  };

  @BuiltValueField(wireName: r'db')
  ReadinessChecksDbEnum get db;
  // enum dbEnum {  configured,  skipped,  degraded,  };

  @BuiltValueField(wireName: r'guest_access')
  ReadinessChecksGuestAccessEnum get guestAccess;
  // enum guestAccessEnum {  enabled,  disabled,  };

  @BuiltValueField(wireName: r'identity_schema')
  ReadinessChecksIdentitySchemaEnum get identitySchema;
  // enum identitySchemaEnum {  configured,  skipped,  degraded,  };

  @BuiltValueField(wireName: r'jwt_validation')
  ReadinessChecksJwtValidationEnum get jwtValidation;
  // enum jwtValidationEnum {  configured,  partial,  skipped,  };

  @BuiltValueField(wireName: r'key_vault')
  ReadinessChecksKeyVaultEnum get keyVault;
  // enum keyVaultEnum {  configured,  skipped,  };

  @BuiltValueField(wireName: r'live_ai')
  ReadinessChecksLiveAiEnum get liveAi;
  // enum liveAiEnum {  enabled,  disabled,  };

  @BuiltValueField(wireName: r'live_speech')
  ReadinessChecksLiveSpeechEnum get liveSpeech;
  // enum liveSpeechEnum {  enabled,  disabled,  };

  @BuiltValueField(wireName: r'logto_management')
  ReadinessChecksLogtoManagementEnum get logtoManagement;
  // enum logtoManagementEnum {  configured,  partial,  skipped,  };

  @BuiltValueField(wireName: r'oauth_audience')
  ReadinessChecksOauthAudienceEnum get oauthAudience;
  // enum oauthAudienceEnum {  configured,  skipped,  };

  @BuiltValueField(wireName: r'oauth_client_id')
  ReadinessChecksOauthClientIdEnum get oauthClientId;
  // enum oauthClientIdEnum {  configured,  skipped,  };

  @BuiltValueField(wireName: r'oauth_issuer')
  ReadinessChecksOauthIssuerEnum get oauthIssuer;
  // enum oauthIssuerEnum {  configured,  skipped,  };

  @BuiltValueField(wireName: r'oauth_jwks_url')
  ReadinessChecksOauthJwksUrlEnum get oauthJwksUrl;
  // enum oauthJwksUrlEnum {  configured,  skipped,  };

  @BuiltValueField(wireName: r'oauth_required_scopes')
  ReadinessChecksOauthRequiredScopesEnum get oauthRequiredScopes;
  // enum oauthRequiredScopesEnum {  configured,  skipped,  };

  @BuiltValueField(wireName: r'postgis')
  ReadinessChecksPostgisEnum get postgis;
  // enum postgisEnum {  configured,  skipped,  degraded,  };

  @BuiltValueField(wireName: r'public_contest_access')
  ReadinessChecksPublicContestAccessEnum get publicContestAccess;
  // enum publicContestAccessEnum {  enabled,  disabled,  };

  @BuiltValueField(wireName: r'public_data_service_key')
  ReadinessChecksPublicDataServiceKeyEnum get publicDataServiceKey;
  // enum publicDataServiceKeyEnum {  configured,  skipped,  };

  @BuiltValueField(wireName: r'public_data_snapshot')
  ReadinessChecksPublicDataSnapshotEnum get publicDataSnapshot;
  // enum publicDataSnapshotEnum {  configured,  missing,  };

  @BuiltValueField(wireName: r'static_snapshot_fallback')
  ReadinessChecksStaticSnapshotFallbackEnum get staticSnapshotFallback;
  // enum staticSnapshotFallbackEnum {  enabled,  disabled,  };

  @BuiltValueField(wireName: r'worker_contracts')
  ReadinessChecksWorkerContractsEnum get workerContracts;
  // enum workerContractsEnum {  configured,  missing,  degraded,  };

  ReadinessChecks._();

  factory ReadinessChecks([void updates(ReadinessChecksBuilder b)]) = _$ReadinessChecks;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReadinessChecksBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReadinessChecks> get serializer => _$ReadinessChecksSerializer();
}

class _$ReadinessChecksSerializer implements PrimitiveSerializer<ReadinessChecks> {
  @override
  final Iterable<Type> types = const [ReadinessChecks, _$ReadinessChecks];

  @override
  final String wireName = r'ReadinessChecks';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReadinessChecks object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'api_key';
    yield serializers.serialize(
      object.apiKey,
      specifiedType: const FullType(ReadinessChecksApiKeyEnum),
    );
    yield r'azure_openai_deployment';
    yield serializers.serialize(
      object.azureOpenaiDeployment,
      specifiedType: const FullType(ReadinessChecksAzureOpenaiDeploymentEnum),
    );
    yield r'azure_openai_endpoint';
    yield serializers.serialize(
      object.azureOpenaiEndpoint,
      specifiedType: const FullType(ReadinessChecksAzureOpenaiEndpointEnum),
    );
    yield r'azure_openai_key';
    yield serializers.serialize(
      object.azureOpenaiKey,
      specifiedType: const FullType(ReadinessChecksAzureOpenaiKeyEnum),
    );
    yield r'azure_speech_endpoint';
    yield serializers.serialize(
      object.azureSpeechEndpoint,
      specifiedType: const FullType(ReadinessChecksAzureSpeechEndpointEnum),
    );
    yield r'azure_speech_key';
    yield serializers.serialize(
      object.azureSpeechKey,
      specifiedType: const FullType(ReadinessChecksAzureSpeechKeyEnum),
    );
    yield r'azure_speech_region';
    yield serializers.serialize(
      object.azureSpeechRegion,
      specifiedType: const FullType(ReadinessChecksAzureSpeechRegionEnum),
    );
    yield r'bearer_token';
    yield serializers.serialize(
      object.bearerToken,
      specifiedType: const FullType(ReadinessChecksBearerTokenEnum),
    );
    yield r'client_auth';
    yield serializers.serialize(
      object.clientAuth,
      specifiedType: const FullType(ReadinessChecksClientAuthEnum),
    );
    yield r'client_identity';
    yield serializers.serialize(
      object.clientIdentity,
      specifiedType: const FullType(ReadinessChecksClientIdentityEnum),
    );
    yield r'db';
    yield serializers.serialize(
      object.db,
      specifiedType: const FullType(ReadinessChecksDbEnum),
    );
    yield r'guest_access';
    yield serializers.serialize(
      object.guestAccess,
      specifiedType: const FullType(ReadinessChecksGuestAccessEnum),
    );
    yield r'identity_schema';
    yield serializers.serialize(
      object.identitySchema,
      specifiedType: const FullType(ReadinessChecksIdentitySchemaEnum),
    );
    yield r'jwt_validation';
    yield serializers.serialize(
      object.jwtValidation,
      specifiedType: const FullType(ReadinessChecksJwtValidationEnum),
    );
    yield r'key_vault';
    yield serializers.serialize(
      object.keyVault,
      specifiedType: const FullType(ReadinessChecksKeyVaultEnum),
    );
    yield r'live_ai';
    yield serializers.serialize(
      object.liveAi,
      specifiedType: const FullType(ReadinessChecksLiveAiEnum),
    );
    yield r'live_speech';
    yield serializers.serialize(
      object.liveSpeech,
      specifiedType: const FullType(ReadinessChecksLiveSpeechEnum),
    );
    yield r'logto_management';
    yield serializers.serialize(
      object.logtoManagement,
      specifiedType: const FullType(ReadinessChecksLogtoManagementEnum),
    );
    yield r'oauth_audience';
    yield serializers.serialize(
      object.oauthAudience,
      specifiedType: const FullType(ReadinessChecksOauthAudienceEnum),
    );
    yield r'oauth_client_id';
    yield serializers.serialize(
      object.oauthClientId,
      specifiedType: const FullType(ReadinessChecksOauthClientIdEnum),
    );
    yield r'oauth_issuer';
    yield serializers.serialize(
      object.oauthIssuer,
      specifiedType: const FullType(ReadinessChecksOauthIssuerEnum),
    );
    yield r'oauth_jwks_url';
    yield serializers.serialize(
      object.oauthJwksUrl,
      specifiedType: const FullType(ReadinessChecksOauthJwksUrlEnum),
    );
    yield r'oauth_required_scopes';
    yield serializers.serialize(
      object.oauthRequiredScopes,
      specifiedType: const FullType(ReadinessChecksOauthRequiredScopesEnum),
    );
    yield r'postgis';
    yield serializers.serialize(
      object.postgis,
      specifiedType: const FullType(ReadinessChecksPostgisEnum),
    );
    yield r'public_contest_access';
    yield serializers.serialize(
      object.publicContestAccess,
      specifiedType: const FullType(ReadinessChecksPublicContestAccessEnum),
    );
    yield r'public_data_service_key';
    yield serializers.serialize(
      object.publicDataServiceKey,
      specifiedType: const FullType(ReadinessChecksPublicDataServiceKeyEnum),
    );
    yield r'public_data_snapshot';
    yield serializers.serialize(
      object.publicDataSnapshot,
      specifiedType: const FullType(ReadinessChecksPublicDataSnapshotEnum),
    );
    yield r'static_snapshot_fallback';
    yield serializers.serialize(
      object.staticSnapshotFallback,
      specifiedType: const FullType(ReadinessChecksStaticSnapshotFallbackEnum),
    );
    yield r'worker_contracts';
    yield serializers.serialize(
      object.workerContracts,
      specifiedType: const FullType(ReadinessChecksWorkerContractsEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ReadinessChecks object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ReadinessChecksBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'api_key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksApiKeyEnum),
          ) as ReadinessChecksApiKeyEnum;
          result.apiKey = valueDes;
          break;
        case r'azure_openai_deployment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksAzureOpenaiDeploymentEnum),
          ) as ReadinessChecksAzureOpenaiDeploymentEnum;
          result.azureOpenaiDeployment = valueDes;
          break;
        case r'azure_openai_endpoint':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksAzureOpenaiEndpointEnum),
          ) as ReadinessChecksAzureOpenaiEndpointEnum;
          result.azureOpenaiEndpoint = valueDes;
          break;
        case r'azure_openai_key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksAzureOpenaiKeyEnum),
          ) as ReadinessChecksAzureOpenaiKeyEnum;
          result.azureOpenaiKey = valueDes;
          break;
        case r'azure_speech_endpoint':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksAzureSpeechEndpointEnum),
          ) as ReadinessChecksAzureSpeechEndpointEnum;
          result.azureSpeechEndpoint = valueDes;
          break;
        case r'azure_speech_key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksAzureSpeechKeyEnum),
          ) as ReadinessChecksAzureSpeechKeyEnum;
          result.azureSpeechKey = valueDes;
          break;
        case r'azure_speech_region':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksAzureSpeechRegionEnum),
          ) as ReadinessChecksAzureSpeechRegionEnum;
          result.azureSpeechRegion = valueDes;
          break;
        case r'bearer_token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksBearerTokenEnum),
          ) as ReadinessChecksBearerTokenEnum;
          result.bearerToken = valueDes;
          break;
        case r'client_auth':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksClientAuthEnum),
          ) as ReadinessChecksClientAuthEnum;
          result.clientAuth = valueDes;
          break;
        case r'client_identity':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksClientIdentityEnum),
          ) as ReadinessChecksClientIdentityEnum;
          result.clientIdentity = valueDes;
          break;
        case r'db':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksDbEnum),
          ) as ReadinessChecksDbEnum;
          result.db = valueDes;
          break;
        case r'guest_access':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksGuestAccessEnum),
          ) as ReadinessChecksGuestAccessEnum;
          result.guestAccess = valueDes;
          break;
        case r'identity_schema':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksIdentitySchemaEnum),
          ) as ReadinessChecksIdentitySchemaEnum;
          result.identitySchema = valueDes;
          break;
        case r'jwt_validation':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksJwtValidationEnum),
          ) as ReadinessChecksJwtValidationEnum;
          result.jwtValidation = valueDes;
          break;
        case r'key_vault':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksKeyVaultEnum),
          ) as ReadinessChecksKeyVaultEnum;
          result.keyVault = valueDes;
          break;
        case r'live_ai':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksLiveAiEnum),
          ) as ReadinessChecksLiveAiEnum;
          result.liveAi = valueDes;
          break;
        case r'live_speech':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksLiveSpeechEnum),
          ) as ReadinessChecksLiveSpeechEnum;
          result.liveSpeech = valueDes;
          break;
        case r'logto_management':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksLogtoManagementEnum),
          ) as ReadinessChecksLogtoManagementEnum;
          result.logtoManagement = valueDes;
          break;
        case r'oauth_audience':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksOauthAudienceEnum),
          ) as ReadinessChecksOauthAudienceEnum;
          result.oauthAudience = valueDes;
          break;
        case r'oauth_client_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksOauthClientIdEnum),
          ) as ReadinessChecksOauthClientIdEnum;
          result.oauthClientId = valueDes;
          break;
        case r'oauth_issuer':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksOauthIssuerEnum),
          ) as ReadinessChecksOauthIssuerEnum;
          result.oauthIssuer = valueDes;
          break;
        case r'oauth_jwks_url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksOauthJwksUrlEnum),
          ) as ReadinessChecksOauthJwksUrlEnum;
          result.oauthJwksUrl = valueDes;
          break;
        case r'oauth_required_scopes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksOauthRequiredScopesEnum),
          ) as ReadinessChecksOauthRequiredScopesEnum;
          result.oauthRequiredScopes = valueDes;
          break;
        case r'postgis':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksPostgisEnum),
          ) as ReadinessChecksPostgisEnum;
          result.postgis = valueDes;
          break;
        case r'public_contest_access':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksPublicContestAccessEnum),
          ) as ReadinessChecksPublicContestAccessEnum;
          result.publicContestAccess = valueDes;
          break;
        case r'public_data_service_key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksPublicDataServiceKeyEnum),
          ) as ReadinessChecksPublicDataServiceKeyEnum;
          result.publicDataServiceKey = valueDes;
          break;
        case r'public_data_snapshot':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksPublicDataSnapshotEnum),
          ) as ReadinessChecksPublicDataSnapshotEnum;
          result.publicDataSnapshot = valueDes;
          break;
        case r'static_snapshot_fallback':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksStaticSnapshotFallbackEnum),
          ) as ReadinessChecksStaticSnapshotFallbackEnum;
          result.staticSnapshotFallback = valueDes;
          break;
        case r'worker_contracts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReadinessChecksWorkerContractsEnum),
          ) as ReadinessChecksWorkerContractsEnum;
          result.workerContracts = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReadinessChecks deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReadinessChecksBuilder();
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

class ReadinessChecksApiKeyEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksApiKeyEnum configured = _$readinessChecksApiKeyEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksApiKeyEnum skipped = _$readinessChecksApiKeyEnum_skipped;

  static Serializer<ReadinessChecksApiKeyEnum> get serializer => _$readinessChecksApiKeyEnumSerializer;

  const ReadinessChecksApiKeyEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksApiKeyEnum> get values => _$readinessChecksApiKeyEnumValues;
  static ReadinessChecksApiKeyEnum valueOf(String name) => _$readinessChecksApiKeyEnumValueOf(name);
}

class ReadinessChecksAzureOpenaiDeploymentEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksAzureOpenaiDeploymentEnum configured = _$readinessChecksAzureOpenaiDeploymentEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksAzureOpenaiDeploymentEnum skipped = _$readinessChecksAzureOpenaiDeploymentEnum_skipped;

  static Serializer<ReadinessChecksAzureOpenaiDeploymentEnum> get serializer => _$readinessChecksAzureOpenaiDeploymentEnumSerializer;

  const ReadinessChecksAzureOpenaiDeploymentEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksAzureOpenaiDeploymentEnum> get values => _$readinessChecksAzureOpenaiDeploymentEnumValues;
  static ReadinessChecksAzureOpenaiDeploymentEnum valueOf(String name) => _$readinessChecksAzureOpenaiDeploymentEnumValueOf(name);
}

class ReadinessChecksAzureOpenaiEndpointEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksAzureOpenaiEndpointEnum configured = _$readinessChecksAzureOpenaiEndpointEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksAzureOpenaiEndpointEnum skipped = _$readinessChecksAzureOpenaiEndpointEnum_skipped;

  static Serializer<ReadinessChecksAzureOpenaiEndpointEnum> get serializer => _$readinessChecksAzureOpenaiEndpointEnumSerializer;

  const ReadinessChecksAzureOpenaiEndpointEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksAzureOpenaiEndpointEnum> get values => _$readinessChecksAzureOpenaiEndpointEnumValues;
  static ReadinessChecksAzureOpenaiEndpointEnum valueOf(String name) => _$readinessChecksAzureOpenaiEndpointEnumValueOf(name);
}

class ReadinessChecksAzureOpenaiKeyEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksAzureOpenaiKeyEnum configured = _$readinessChecksAzureOpenaiKeyEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksAzureOpenaiKeyEnum skipped = _$readinessChecksAzureOpenaiKeyEnum_skipped;

  static Serializer<ReadinessChecksAzureOpenaiKeyEnum> get serializer => _$readinessChecksAzureOpenaiKeyEnumSerializer;

  const ReadinessChecksAzureOpenaiKeyEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksAzureOpenaiKeyEnum> get values => _$readinessChecksAzureOpenaiKeyEnumValues;
  static ReadinessChecksAzureOpenaiKeyEnum valueOf(String name) => _$readinessChecksAzureOpenaiKeyEnumValueOf(name);
}

class ReadinessChecksAzureSpeechEndpointEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksAzureSpeechEndpointEnum configured = _$readinessChecksAzureSpeechEndpointEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksAzureSpeechEndpointEnum skipped = _$readinessChecksAzureSpeechEndpointEnum_skipped;

  static Serializer<ReadinessChecksAzureSpeechEndpointEnum> get serializer => _$readinessChecksAzureSpeechEndpointEnumSerializer;

  const ReadinessChecksAzureSpeechEndpointEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksAzureSpeechEndpointEnum> get values => _$readinessChecksAzureSpeechEndpointEnumValues;
  static ReadinessChecksAzureSpeechEndpointEnum valueOf(String name) => _$readinessChecksAzureSpeechEndpointEnumValueOf(name);
}

class ReadinessChecksAzureSpeechKeyEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksAzureSpeechKeyEnum configured = _$readinessChecksAzureSpeechKeyEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksAzureSpeechKeyEnum skipped = _$readinessChecksAzureSpeechKeyEnum_skipped;

  static Serializer<ReadinessChecksAzureSpeechKeyEnum> get serializer => _$readinessChecksAzureSpeechKeyEnumSerializer;

  const ReadinessChecksAzureSpeechKeyEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksAzureSpeechKeyEnum> get values => _$readinessChecksAzureSpeechKeyEnumValues;
  static ReadinessChecksAzureSpeechKeyEnum valueOf(String name) => _$readinessChecksAzureSpeechKeyEnumValueOf(name);
}

class ReadinessChecksAzureSpeechRegionEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksAzureSpeechRegionEnum configured = _$readinessChecksAzureSpeechRegionEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksAzureSpeechRegionEnum skipped = _$readinessChecksAzureSpeechRegionEnum_skipped;

  static Serializer<ReadinessChecksAzureSpeechRegionEnum> get serializer => _$readinessChecksAzureSpeechRegionEnumSerializer;

  const ReadinessChecksAzureSpeechRegionEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksAzureSpeechRegionEnum> get values => _$readinessChecksAzureSpeechRegionEnumValues;
  static ReadinessChecksAzureSpeechRegionEnum valueOf(String name) => _$readinessChecksAzureSpeechRegionEnumValueOf(name);
}

class ReadinessChecksBearerTokenEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksBearerTokenEnum configured = _$readinessChecksBearerTokenEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksBearerTokenEnum skipped = _$readinessChecksBearerTokenEnum_skipped;

  static Serializer<ReadinessChecksBearerTokenEnum> get serializer => _$readinessChecksBearerTokenEnumSerializer;

  const ReadinessChecksBearerTokenEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksBearerTokenEnum> get values => _$readinessChecksBearerTokenEnumValues;
  static ReadinessChecksBearerTokenEnum valueOf(String name) => _$readinessChecksBearerTokenEnumValueOf(name);
}

class ReadinessChecksClientAuthEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksClientAuthEnum configured = _$readinessChecksClientAuthEnum_configured;
  @BuiltValueEnumConst(wireName: r'missing')
  static const ReadinessChecksClientAuthEnum missing = _$readinessChecksClientAuthEnum_missing;
  @BuiltValueEnumConst(wireName: r'snapshot-fallback')
  static const ReadinessChecksClientAuthEnum snapshotFallback = _$readinessChecksClientAuthEnum_snapshotFallback;
  @BuiltValueEnumConst(wireName: r'public-contest')
  static const ReadinessChecksClientAuthEnum publicContest = _$readinessChecksClientAuthEnum_publicContest;

  static Serializer<ReadinessChecksClientAuthEnum> get serializer => _$readinessChecksClientAuthEnumSerializer;

  const ReadinessChecksClientAuthEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksClientAuthEnum> get values => _$readinessChecksClientAuthEnumValues;
  static ReadinessChecksClientAuthEnum valueOf(String name) => _$readinessChecksClientAuthEnumValueOf(name);
}

class ReadinessChecksClientIdentityEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'guest')
  static const ReadinessChecksClientIdentityEnum guest = _$readinessChecksClientIdentityEnum_guest;
  @BuiltValueEnumConst(wireName: r'static')
  static const ReadinessChecksClientIdentityEnum static_ = _$readinessChecksClientIdentityEnum_static_;
  @BuiltValueEnumConst(wireName: r'transition')
  static const ReadinessChecksClientIdentityEnum transition = _$readinessChecksClientIdentityEnum_transition;
  @BuiltValueEnumConst(wireName: r'oauth-configured')
  static const ReadinessChecksClientIdentityEnum oauthConfigured = _$readinessChecksClientIdentityEnum_oauthConfigured;
  @BuiltValueEnumConst(wireName: r'snapshot-fallback')
  static const ReadinessChecksClientIdentityEnum snapshotFallback = _$readinessChecksClientIdentityEnum_snapshotFallback;
  @BuiltValueEnumConst(wireName: r'public-contest')
  static const ReadinessChecksClientIdentityEnum publicContest = _$readinessChecksClientIdentityEnum_publicContest;
  @BuiltValueEnumConst(wireName: r'missing')
  static const ReadinessChecksClientIdentityEnum missing = _$readinessChecksClientIdentityEnum_missing;

  static Serializer<ReadinessChecksClientIdentityEnum> get serializer => _$readinessChecksClientIdentityEnumSerializer;

  const ReadinessChecksClientIdentityEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksClientIdentityEnum> get values => _$readinessChecksClientIdentityEnumValues;
  static ReadinessChecksClientIdentityEnum valueOf(String name) => _$readinessChecksClientIdentityEnumValueOf(name);
}

class ReadinessChecksDbEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksDbEnum configured = _$readinessChecksDbEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksDbEnum skipped = _$readinessChecksDbEnum_skipped;
  @BuiltValueEnumConst(wireName: r'degraded')
  static const ReadinessChecksDbEnum degraded = _$readinessChecksDbEnum_degraded;

  static Serializer<ReadinessChecksDbEnum> get serializer => _$readinessChecksDbEnumSerializer;

  const ReadinessChecksDbEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksDbEnum> get values => _$readinessChecksDbEnumValues;
  static ReadinessChecksDbEnum valueOf(String name) => _$readinessChecksDbEnumValueOf(name);
}

class ReadinessChecksGuestAccessEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'enabled')
  static const ReadinessChecksGuestAccessEnum enabled = _$readinessChecksGuestAccessEnum_enabled;
  @BuiltValueEnumConst(wireName: r'disabled')
  static const ReadinessChecksGuestAccessEnum disabled = _$readinessChecksGuestAccessEnum_disabled;

  static Serializer<ReadinessChecksGuestAccessEnum> get serializer => _$readinessChecksGuestAccessEnumSerializer;

  const ReadinessChecksGuestAccessEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksGuestAccessEnum> get values => _$readinessChecksGuestAccessEnumValues;
  static ReadinessChecksGuestAccessEnum valueOf(String name) => _$readinessChecksGuestAccessEnumValueOf(name);
}

class ReadinessChecksIdentitySchemaEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksIdentitySchemaEnum configured = _$readinessChecksIdentitySchemaEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksIdentitySchemaEnum skipped = _$readinessChecksIdentitySchemaEnum_skipped;
  @BuiltValueEnumConst(wireName: r'degraded')
  static const ReadinessChecksIdentitySchemaEnum degraded = _$readinessChecksIdentitySchemaEnum_degraded;

  static Serializer<ReadinessChecksIdentitySchemaEnum> get serializer => _$readinessChecksIdentitySchemaEnumSerializer;

  const ReadinessChecksIdentitySchemaEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksIdentitySchemaEnum> get values => _$readinessChecksIdentitySchemaEnumValues;
  static ReadinessChecksIdentitySchemaEnum valueOf(String name) => _$readinessChecksIdentitySchemaEnumValueOf(name);
}

class ReadinessChecksJwtValidationEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksJwtValidationEnum configured = _$readinessChecksJwtValidationEnum_configured;
  @BuiltValueEnumConst(wireName: r'partial')
  static const ReadinessChecksJwtValidationEnum partial = _$readinessChecksJwtValidationEnum_partial;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksJwtValidationEnum skipped = _$readinessChecksJwtValidationEnum_skipped;

  static Serializer<ReadinessChecksJwtValidationEnum> get serializer => _$readinessChecksJwtValidationEnumSerializer;

  const ReadinessChecksJwtValidationEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksJwtValidationEnum> get values => _$readinessChecksJwtValidationEnumValues;
  static ReadinessChecksJwtValidationEnum valueOf(String name) => _$readinessChecksJwtValidationEnumValueOf(name);
}

class ReadinessChecksKeyVaultEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksKeyVaultEnum configured = _$readinessChecksKeyVaultEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksKeyVaultEnum skipped = _$readinessChecksKeyVaultEnum_skipped;

  static Serializer<ReadinessChecksKeyVaultEnum> get serializer => _$readinessChecksKeyVaultEnumSerializer;

  const ReadinessChecksKeyVaultEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksKeyVaultEnum> get values => _$readinessChecksKeyVaultEnumValues;
  static ReadinessChecksKeyVaultEnum valueOf(String name) => _$readinessChecksKeyVaultEnumValueOf(name);
}

class ReadinessChecksLiveAiEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'enabled')
  static const ReadinessChecksLiveAiEnum enabled = _$readinessChecksLiveAiEnum_enabled;
  @BuiltValueEnumConst(wireName: r'disabled')
  static const ReadinessChecksLiveAiEnum disabled = _$readinessChecksLiveAiEnum_disabled;

  static Serializer<ReadinessChecksLiveAiEnum> get serializer => _$readinessChecksLiveAiEnumSerializer;

  const ReadinessChecksLiveAiEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksLiveAiEnum> get values => _$readinessChecksLiveAiEnumValues;
  static ReadinessChecksLiveAiEnum valueOf(String name) => _$readinessChecksLiveAiEnumValueOf(name);
}

class ReadinessChecksLiveSpeechEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'enabled')
  static const ReadinessChecksLiveSpeechEnum enabled = _$readinessChecksLiveSpeechEnum_enabled;
  @BuiltValueEnumConst(wireName: r'disabled')
  static const ReadinessChecksLiveSpeechEnum disabled = _$readinessChecksLiveSpeechEnum_disabled;

  static Serializer<ReadinessChecksLiveSpeechEnum> get serializer => _$readinessChecksLiveSpeechEnumSerializer;

  const ReadinessChecksLiveSpeechEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksLiveSpeechEnum> get values => _$readinessChecksLiveSpeechEnumValues;
  static ReadinessChecksLiveSpeechEnum valueOf(String name) => _$readinessChecksLiveSpeechEnumValueOf(name);
}

class ReadinessChecksLogtoManagementEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksLogtoManagementEnum configured = _$readinessChecksLogtoManagementEnum_configured;
  @BuiltValueEnumConst(wireName: r'partial')
  static const ReadinessChecksLogtoManagementEnum partial = _$readinessChecksLogtoManagementEnum_partial;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksLogtoManagementEnum skipped = _$readinessChecksLogtoManagementEnum_skipped;

  static Serializer<ReadinessChecksLogtoManagementEnum> get serializer => _$readinessChecksLogtoManagementEnumSerializer;

  const ReadinessChecksLogtoManagementEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksLogtoManagementEnum> get values => _$readinessChecksLogtoManagementEnumValues;
  static ReadinessChecksLogtoManagementEnum valueOf(String name) => _$readinessChecksLogtoManagementEnumValueOf(name);
}

class ReadinessChecksOauthAudienceEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksOauthAudienceEnum configured = _$readinessChecksOauthAudienceEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksOauthAudienceEnum skipped = _$readinessChecksOauthAudienceEnum_skipped;

  static Serializer<ReadinessChecksOauthAudienceEnum> get serializer => _$readinessChecksOauthAudienceEnumSerializer;

  const ReadinessChecksOauthAudienceEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksOauthAudienceEnum> get values => _$readinessChecksOauthAudienceEnumValues;
  static ReadinessChecksOauthAudienceEnum valueOf(String name) => _$readinessChecksOauthAudienceEnumValueOf(name);
}

class ReadinessChecksOauthClientIdEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksOauthClientIdEnum configured = _$readinessChecksOauthClientIdEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksOauthClientIdEnum skipped = _$readinessChecksOauthClientIdEnum_skipped;

  static Serializer<ReadinessChecksOauthClientIdEnum> get serializer => _$readinessChecksOauthClientIdEnumSerializer;

  const ReadinessChecksOauthClientIdEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksOauthClientIdEnum> get values => _$readinessChecksOauthClientIdEnumValues;
  static ReadinessChecksOauthClientIdEnum valueOf(String name) => _$readinessChecksOauthClientIdEnumValueOf(name);
}

class ReadinessChecksOauthIssuerEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksOauthIssuerEnum configured = _$readinessChecksOauthIssuerEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksOauthIssuerEnum skipped = _$readinessChecksOauthIssuerEnum_skipped;

  static Serializer<ReadinessChecksOauthIssuerEnum> get serializer => _$readinessChecksOauthIssuerEnumSerializer;

  const ReadinessChecksOauthIssuerEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksOauthIssuerEnum> get values => _$readinessChecksOauthIssuerEnumValues;
  static ReadinessChecksOauthIssuerEnum valueOf(String name) => _$readinessChecksOauthIssuerEnumValueOf(name);
}

class ReadinessChecksOauthJwksUrlEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksOauthJwksUrlEnum configured = _$readinessChecksOauthJwksUrlEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksOauthJwksUrlEnum skipped = _$readinessChecksOauthJwksUrlEnum_skipped;

  static Serializer<ReadinessChecksOauthJwksUrlEnum> get serializer => _$readinessChecksOauthJwksUrlEnumSerializer;

  const ReadinessChecksOauthJwksUrlEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksOauthJwksUrlEnum> get values => _$readinessChecksOauthJwksUrlEnumValues;
  static ReadinessChecksOauthJwksUrlEnum valueOf(String name) => _$readinessChecksOauthJwksUrlEnumValueOf(name);
}

class ReadinessChecksOauthRequiredScopesEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksOauthRequiredScopesEnum configured = _$readinessChecksOauthRequiredScopesEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksOauthRequiredScopesEnum skipped = _$readinessChecksOauthRequiredScopesEnum_skipped;

  static Serializer<ReadinessChecksOauthRequiredScopesEnum> get serializer => _$readinessChecksOauthRequiredScopesEnumSerializer;

  const ReadinessChecksOauthRequiredScopesEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksOauthRequiredScopesEnum> get values => _$readinessChecksOauthRequiredScopesEnumValues;
  static ReadinessChecksOauthRequiredScopesEnum valueOf(String name) => _$readinessChecksOauthRequiredScopesEnumValueOf(name);
}

class ReadinessChecksPostgisEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksPostgisEnum configured = _$readinessChecksPostgisEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksPostgisEnum skipped = _$readinessChecksPostgisEnum_skipped;
  @BuiltValueEnumConst(wireName: r'degraded')
  static const ReadinessChecksPostgisEnum degraded = _$readinessChecksPostgisEnum_degraded;

  static Serializer<ReadinessChecksPostgisEnum> get serializer => _$readinessChecksPostgisEnumSerializer;

  const ReadinessChecksPostgisEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksPostgisEnum> get values => _$readinessChecksPostgisEnumValues;
  static ReadinessChecksPostgisEnum valueOf(String name) => _$readinessChecksPostgisEnumValueOf(name);
}

class ReadinessChecksPublicContestAccessEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'enabled')
  static const ReadinessChecksPublicContestAccessEnum enabled = _$readinessChecksPublicContestAccessEnum_enabled;
  @BuiltValueEnumConst(wireName: r'disabled')
  static const ReadinessChecksPublicContestAccessEnum disabled = _$readinessChecksPublicContestAccessEnum_disabled;

  static Serializer<ReadinessChecksPublicContestAccessEnum> get serializer => _$readinessChecksPublicContestAccessEnumSerializer;

  const ReadinessChecksPublicContestAccessEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksPublicContestAccessEnum> get values => _$readinessChecksPublicContestAccessEnumValues;
  static ReadinessChecksPublicContestAccessEnum valueOf(String name) => _$readinessChecksPublicContestAccessEnumValueOf(name);
}

class ReadinessChecksPublicDataServiceKeyEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksPublicDataServiceKeyEnum configured = _$readinessChecksPublicDataServiceKeyEnum_configured;
  @BuiltValueEnumConst(wireName: r'skipped')
  static const ReadinessChecksPublicDataServiceKeyEnum skipped = _$readinessChecksPublicDataServiceKeyEnum_skipped;

  static Serializer<ReadinessChecksPublicDataServiceKeyEnum> get serializer => _$readinessChecksPublicDataServiceKeyEnumSerializer;

  const ReadinessChecksPublicDataServiceKeyEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksPublicDataServiceKeyEnum> get values => _$readinessChecksPublicDataServiceKeyEnumValues;
  static ReadinessChecksPublicDataServiceKeyEnum valueOf(String name) => _$readinessChecksPublicDataServiceKeyEnumValueOf(name);
}

class ReadinessChecksPublicDataSnapshotEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksPublicDataSnapshotEnum configured = _$readinessChecksPublicDataSnapshotEnum_configured;
  @BuiltValueEnumConst(wireName: r'missing')
  static const ReadinessChecksPublicDataSnapshotEnum missing = _$readinessChecksPublicDataSnapshotEnum_missing;

  static Serializer<ReadinessChecksPublicDataSnapshotEnum> get serializer => _$readinessChecksPublicDataSnapshotEnumSerializer;

  const ReadinessChecksPublicDataSnapshotEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksPublicDataSnapshotEnum> get values => _$readinessChecksPublicDataSnapshotEnumValues;
  static ReadinessChecksPublicDataSnapshotEnum valueOf(String name) => _$readinessChecksPublicDataSnapshotEnumValueOf(name);
}

class ReadinessChecksStaticSnapshotFallbackEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'enabled')
  static const ReadinessChecksStaticSnapshotFallbackEnum enabled = _$readinessChecksStaticSnapshotFallbackEnum_enabled;
  @BuiltValueEnumConst(wireName: r'disabled')
  static const ReadinessChecksStaticSnapshotFallbackEnum disabled = _$readinessChecksStaticSnapshotFallbackEnum_disabled;

  static Serializer<ReadinessChecksStaticSnapshotFallbackEnum> get serializer => _$readinessChecksStaticSnapshotFallbackEnumSerializer;

  const ReadinessChecksStaticSnapshotFallbackEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksStaticSnapshotFallbackEnum> get values => _$readinessChecksStaticSnapshotFallbackEnumValues;
  static ReadinessChecksStaticSnapshotFallbackEnum valueOf(String name) => _$readinessChecksStaticSnapshotFallbackEnumValueOf(name);
}

class ReadinessChecksWorkerContractsEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'configured')
  static const ReadinessChecksWorkerContractsEnum configured = _$readinessChecksWorkerContractsEnum_configured;
  @BuiltValueEnumConst(wireName: r'missing')
  static const ReadinessChecksWorkerContractsEnum missing = _$readinessChecksWorkerContractsEnum_missing;
  @BuiltValueEnumConst(wireName: r'degraded')
  static const ReadinessChecksWorkerContractsEnum degraded = _$readinessChecksWorkerContractsEnum_degraded;

  static Serializer<ReadinessChecksWorkerContractsEnum> get serializer => _$readinessChecksWorkerContractsEnumSerializer;

  const ReadinessChecksWorkerContractsEnum._(String name): super(name);

  static BuiltSet<ReadinessChecksWorkerContractsEnum> get values => _$readinessChecksWorkerContractsEnumValues;
  static ReadinessChecksWorkerContractsEnum valueOf(String name) => _$readinessChecksWorkerContractsEnumValueOf(name);
}

