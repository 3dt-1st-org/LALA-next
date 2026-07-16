import 'package:flutter/foundation.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:logto_dart_sdk/logto_dart_sdk.dart';

import 'auth_controller.dart';

const String _nativeRedirectUri = 'cloud.lalanext.lala://callback';
const String _nativeRedirectScheme = 'cloud.lalanext.lala';

typedef LalaEnvironmentValue = String Function(String name);

@immutable
class LalaAuthConfig {
  const LalaAuthConfig({
    required this.endpoint,
    required this.appId,
    required this.apiAudience,
    required this.redirectUri,
    this.postLogoutRedirectUri,
    this.isWeb = false,
  });

  factory LalaAuthConfig.fromEnvironment({
    bool? isWeb,
    Uri? baseUri,
    LalaEnvironmentValue? environmentValue,
  }) {
    final selectedIsWeb = isWeb ?? kIsWeb;
    final selectedBaseUri = baseUri ?? Uri.base;
    final read = environmentValue ?? _compileTimeEnvironmentValue;
    final endpoint = read('LOGTO_ENDPOINT').trim();
    final appId = read(
      selectedIsWeb ? 'LOGTO_WEB_APP_ID' : 'LOGTO_NATIVE_APP_ID',
    ).trim();
    final apiAudience = read('LOGTO_API_AUDIENCE').trim();
    final configuredRedirectUri = read('LOGTO_REDIRECT_URI').trim();
    final postLogoutRedirectUri = read('LOGTO_POST_LOGOUT_REDIRECT_URI').trim();
    final defaultRedirectUri = selectedIsWeb
        ? selectedBaseUri.resolve('/auth-callback.html').toString()
        : _nativeRedirectUri;

    return LalaAuthConfig(
      endpoint: endpoint,
      appId: appId,
      apiAudience: apiAudience,
      redirectUri: configuredRedirectUri.isEmpty
          ? defaultRedirectUri
          : configuredRedirectUri,
      postLogoutRedirectUri: postLogoutRedirectUri.isEmpty
          ? null
          : postLogoutRedirectUri,
      isWeb: selectedIsWeb,
    );
  }

  final String endpoint;
  final String appId;
  final String apiAudience;
  final String redirectUri;
  final String? postLogoutRedirectUri;
  final bool isWeb;

  bool get enabled =>
      _isHttpsUri(endpoint) &&
      appId.isNotEmpty &&
      _isHttpsUri(apiAudience) &&
      _isValidRedirectUri(redirectUri, isWeb: isWeb) &&
      (postLogoutRedirectUri == null ||
          _isValidRedirectUri(postLogoutRedirectUri!, isWeb: isWeb));
}

abstract interface class LalaAuthGateway {
  Future<bool> get isAuthenticated;

  Future<LalaAuthProfile?> get profile;

  Future<bool> validateSession(String resource);

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

  final client = LogtoClient(config: createLogtoSdkConfig(config));
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
  Future<LalaAuthProfile?> get profile async {
    final claims = await _client.idTokenClaims;
    if (claims == null) {
      return null;
    }
    final values = claims.toJson();
    return LalaAuthProfile(
      name: _normalizedString(values['name']),
      email: _normalizedString(values['email']),
      picture: _normalizedString(values['picture']),
      emailVerified: _normalizedBool(values['email_verified']),
    );
  }

  @override
  Future<bool> validateSession(String resource) async {
    return await accessToken(resource) != null;
  }

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
  Future<LalaAuthProfile?> get profile => Future<LalaAuthProfile?>.value();

  @override
  Future<bool> validateSession(String resource) => Future<bool>.value(false);

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

String _compileTimeEnvironmentValue(String name) {
  return switch (name) {
    'LOGTO_ENDPOINT' => const String.fromEnvironment('LOGTO_ENDPOINT'),
    'LOGTO_WEB_APP_ID' => const String.fromEnvironment('LOGTO_WEB_APP_ID'),
    'LOGTO_NATIVE_APP_ID' => const String.fromEnvironment(
      'LOGTO_NATIVE_APP_ID',
    ),
    'LOGTO_API_AUDIENCE' => const String.fromEnvironment('LOGTO_API_AUDIENCE'),
    'LOGTO_REDIRECT_URI' => const String.fromEnvironment('LOGTO_REDIRECT_URI'),
    'LOGTO_POST_LOGOUT_REDIRECT_URI' => const String.fromEnvironment(
      'LOGTO_POST_LOGOUT_REDIRECT_URI',
    ),
    _ => throw ArgumentError.value(name, 'name', 'Unknown environment value.'),
  };
}

@visibleForTesting
LogtoConfig createLogtoSdkConfig(LalaAuthConfig config) {
  return LogtoConfig(
    endpoint: config.endpoint,
    appId: config.appId,
    resources: [config.apiAudience],
    scopes: [LogtoUserScope.email.value],
  );
}

String? _normalizedString(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

bool? _normalizedBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return bool.tryParse(value.trim());
  }
  return null;
}

bool _isHttpsUri(String value) {
  final uri = Uri.tryParse(value);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}

bool _isValidRedirectUri(String value, {required bool isWeb}) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty || uri.hasFragment) {
    return false;
  }
  if (!isWeb) {
    return uri.scheme == _nativeRedirectScheme;
  }
  if (uri.scheme == 'https') {
    return true;
  }
  return uri.scheme == 'http' &&
      (uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1');
}
