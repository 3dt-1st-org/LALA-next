import 'package:flutter/foundation.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:logto_dart_sdk/logto_dart_sdk.dart';

import 'auth_controller.dart';

const String _nativeRedirectUri = 'cloud.lalanext.lala://callback';

@immutable
class LalaAuthConfig {
  const LalaAuthConfig({
    required this.endpoint,
    required this.appId,
    required this.apiAudience,
    required this.redirectUri,
    this.postLogoutRedirectUri,
  });

  factory LalaAuthConfig.fromEnvironment() {
    final defaultRedirectUri = kIsWeb
        ? Uri.base.resolve('/auth-callback.html').toString()
        : _nativeRedirectUri;
    const configuredRedirectUri = String.fromEnvironment('LOGTO_REDIRECT_URI');

    return LalaAuthConfig(
      endpoint: const String.fromEnvironment('LOGTO_ENDPOINT'),
      appId: kIsWeb
          ? const String.fromEnvironment('LOGTO_WEB_APP_ID')
          : const String.fromEnvironment('LOGTO_NATIVE_APP_ID'),
      apiAudience: const String.fromEnvironment('LOGTO_API_AUDIENCE'),
      redirectUri: configuredRedirectUri.trim().isEmpty
          ? defaultRedirectUri
          : configuredRedirectUri.trim(),
      postLogoutRedirectUri: _optionalEnvironmentValue(
        const String.fromEnvironment('LOGTO_POST_LOGOUT_REDIRECT_URI'),
      ),
    );
  }

  final String endpoint;
  final String appId;
  final String apiAudience;
  final String redirectUri;
  final String? postLogoutRedirectUri;

  bool get enabled =>
      _isHttpsUri(endpoint) &&
      appId.trim().isNotEmpty &&
      _isHttpsUri(apiAudience) &&
      redirectUri.trim().isNotEmpty;
}

abstract interface class LalaAuthGateway {
  Future<bool> get isAuthenticated;

  Future<void> signIn();

  Future<void> signOut();

  Future<String?> accessToken(String resource);
}

typedef LalaAuthControllerFactory =
    LalaAuthController Function(LalaAppAuthDependencies dependencies);

@immutable
class LalaAppAuthDependencies {
  const LalaAppAuthDependencies({required this.apiBaseUri});

  final Uri apiBaseUri;
}

LalaAuthController createLalaAuthController(
  LalaAppAuthDependencies dependencies,
) {
  final config = LalaAuthConfig.fromEnvironment();
  if (!config.enabled) {
    return LalaAuthController(
      config: config,
      gateway: const _DisabledAuthGateway(),
      accountApi: const _DisabledAccountApi(),
    );
  }

  final client = LogtoClient(
    config: LogtoConfig(
      endpoint: config.endpoint,
      appId: config.appId,
      resources: [config.apiAudience],
    ),
  );
  final gateway = LogtoAuthGateway(client, config: config);
  final apiClient = LalaApiClient(
    baseUri: dependencies.apiBaseUri,
    accessTokenProvider: () => gateway.accessToken(config.apiAudience),
  );
  return LalaAuthController(
    config: config,
    gateway: gateway,
    accountApi: LalaClientAccountApi(apiClient),
  );
}

class LogtoAuthGateway implements LalaAuthGateway {
  const LogtoAuthGateway(this._client, {required this.config});

  final LogtoClient _client;
  final LalaAuthConfig config;

  @override
  Future<bool> get isAuthenticated => _client.isAuthenticated;

  @override
  Future<void> signIn() => _client.signIn(config.redirectUri);

  @override
  Future<void> signOut() async {
    try {
      await _client.signOut(config.postLogoutRedirectUri ?? config.redirectUri);
    } on Object {
      if (await _client.isAuthenticated) {
        rethrow;
      }
    }
  }

  @override
  Future<String?> accessToken(String resource) async {
    if (!await _client.isAuthenticated) {
      return null;
    }
    final token = await _client.getAccessToken(resource: resource);
    return token?.token;
  }
}

class LalaClientAccountApi implements LalaAccountApi {
  const LalaClientAccountApi(this._client);

  final LalaApiClient _client;

  @override
  Future<LalaMe> getMe() async {
    final response = await _client.getMe();
    final me = response.data;
    if (!response.ok || me == null) {
      throw StateError('Missing account response.');
    }
    return me;
  }

  @override
  Future<void> deleteMe({required String confirmation}) {
    return _client.deleteMe(confirmation: confirmation);
  }
}

class _DisabledAuthGateway implements LalaAuthGateway {
  const _DisabledAuthGateway();

  @override
  Future<bool> get isAuthenticated => Future<bool>.value(false);

  @override
  Future<String?> accessToken(String resource) => Future<String?>.value();

  @override
  Future<void> signIn() => Future<void>.value();

  @override
  Future<void> signOut() => Future<void>.value();
}

class _DisabledAccountApi implements LalaAccountApi {
  const _DisabledAccountApi();

  @override
  Future<void> deleteMe({required String confirmation}) => Future<void>.value();

  @override
  Future<LalaMe> getMe() =>
      Future<LalaMe>.error(StateError('Account API is disabled.'));
}

String? _optionalEnvironmentValue(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _isHttpsUri(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}
