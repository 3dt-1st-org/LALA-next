import 'package:flutter/foundation.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'logto_auth_gateway.dart';

enum LalaAuthStatus { disabled, signedOut, busy, signedIn, error }

enum LalaAccountSyncStatus { idle, syncing, ready, error }

@immutable
class LalaAuthProfile {
  const LalaAuthProfile({
    this.name,
    this.email,
    this.picture,
    this.emailVerified,
  });

  final String? name;
  final String? email;
  final String? picture;
  final bool? emailVerified;
}

@immutable
class LalaAuthState {
  const LalaAuthState({
    required this.status,
    this.authenticated = false,
    this.profile,
    this.me,
    this.accountSyncStatus = LalaAccountSyncStatus.idle,
    this.errorMessage,
  });

  const LalaAuthState.disabled() : this(status: LalaAuthStatus.disabled);

  const LalaAuthState.signedOut() : this(status: LalaAuthStatus.signedOut);

  const LalaAuthState.busy({
    bool authenticated = false,
    LalaAuthProfile? profile,
    LalaMe? me,
    LalaAccountSyncStatus accountSyncStatus = LalaAccountSyncStatus.idle,
  }) : this(
         status: LalaAuthStatus.busy,
         authenticated: authenticated,
         profile: profile,
         me: me,
         accountSyncStatus: accountSyncStatus,
       );

  const LalaAuthState.signedIn({
    LalaAuthProfile? profile,
    LalaMe? me,
    required LalaAccountSyncStatus accountSyncStatus,
    String? errorMessage,
  }) : this(
         status: LalaAuthStatus.signedIn,
         authenticated: true,
         profile: profile,
         me: me,
         accountSyncStatus: accountSyncStatus,
         errorMessage: errorMessage,
       );

  const LalaAuthState.error({
    bool authenticated = false,
    LalaAuthProfile? profile,
    LalaMe? me,
    LalaAccountSyncStatus accountSyncStatus = LalaAccountSyncStatus.idle,
    required String message,
  }) : this(
         status: LalaAuthStatus.error,
         authenticated: authenticated,
         profile: profile,
         me: me,
         accountSyncStatus: accountSyncStatus,
         errorMessage: message,
       );

  final LalaAuthStatus status;
  final bool authenticated;
  final LalaAuthProfile? profile;
  final LalaMe? me;
  final LalaAccountSyncStatus accountSyncStatus;
  final String? errorMessage;
}

abstract interface class LalaAccountApi {
  Future<LalaMe> getMe();

  Future<void> deleteMe({required String confirmation});
}

class LalaAuthController extends ChangeNotifier {
  LalaAuthController({
    required this.config,
    required LalaAuthGateway gateway,
    required LalaAccountApi accountApi,
  }) : // The public injection names intentionally differ from private storage.
       // ignore: prefer_initializing_formals
       _gateway = gateway,
       // ignore: prefer_initializing_formals
       _accountApi = accountApi,
       _state = config.enabled
           ? const LalaAuthState.busy()
           : const LalaAuthState.disabled();

  static const String safeErrorMessage =
      'We could not complete that account request. Please try again.';
  static const String safeAccountSyncErrorMessage =
      'We could not connect your LALA account. Please try again.';

  final LalaAuthConfig config;
  final LalaAuthGateway _gateway;
  final LalaAccountApi _accountApi;
  LalaAuthState _state;
  int _sessionRevision = 0;
  bool _disposed = false;

  LalaAuthState get state => _state;

  Future<void> initialize() async {
    if (!config.enabled) {
      _setState(const LalaAuthState.disabled());
      return;
    }

    _setState(const LalaAuthState.busy());
    try {
      final hasStoredSession = await _gateway.isAuthenticated;
      final hasUsableSession =
          hasStoredSession &&
          await _gateway.validateSession(config.apiAudience);
      if (!hasUsableSession) {
        _invalidateSession();
        _setState(const LalaAuthState.signedOut());
        return;
      }
      await _restoreAuthenticatedSession();
    } on Object {
      _invalidateSession();
      _setState(const LalaAuthState.error(message: safeErrorMessage));
    }
  }

  Future<void> signIn() async {
    if (!config.enabled || _state.status == LalaAuthStatus.busy) {
      return;
    }

    _setState(const LalaAuthState.busy());
    try {
      await _gateway.signIn();
    } on Object {
      _invalidateSession();
      _setState(const LalaAuthState.error(message: safeErrorMessage));
      return;
    }
    await _restoreAuthenticatedSession();
  }

  Future<void> signOut() async {
    if (!config.enabled || _state.status == LalaAuthStatus.busy) {
      return;
    }

    final previousState = _state;
    _invalidateSession();
    _setState(
      LalaAuthState.busy(
        authenticated: previousState.authenticated,
        profile: previousState.profile,
        me: previousState.me,
        accountSyncStatus: previousState.accountSyncStatus,
      ),
    );
    try {
      await _gateway.signOut();
      _setState(const LalaAuthState.signedOut());
    } on Object {
      final accountSyncStatus =
          previousState.accountSyncStatus == LalaAccountSyncStatus.syncing
          ? LalaAccountSyncStatus.error
          : previousState.accountSyncStatus;
      _setState(
        LalaAuthState.error(
          authenticated: previousState.authenticated,
          profile: previousState.profile,
          me: previousState.me,
          accountSyncStatus: accountSyncStatus,
          message: safeErrorMessage,
        ),
      );
    }
  }

  Future<void> deleteAccount() async {
    final currentMe = _state.me;
    if (!config.enabled ||
        !_state.authenticated ||
        currentMe == null ||
        _state.status == LalaAuthStatus.busy) {
      return;
    }

    final previousState = _state;
    _invalidateSession();
    _setState(
      LalaAuthState.busy(
        authenticated: true,
        profile: previousState.profile,
        me: currentMe,
        accountSyncStatus: previousState.accountSyncStatus,
      ),
    );
    try {
      await _accountApi.deleteMe(confirmation: 'delete-my-account');
    } on Object {
      _setState(
        LalaAuthState.error(
          authenticated: true,
          profile: previousState.profile,
          me: currentMe,
          accountSyncStatus: previousState.accountSyncStatus,
          message: safeErrorMessage,
        ),
      );
      return;
    }

    try {
      await _gateway.signOut();
    } on Object {
      // The account is gone; a hosted logout failure must not restore its UI.
    }
    _setState(const LalaAuthState.signedOut());
  }

  Future<String?> accessToken() {
    if (!config.enabled ||
        _state.status == LalaAuthStatus.signedOut ||
        _state.status == LalaAuthStatus.disabled ||
        (_state.status == LalaAuthStatus.error && !_state.authenticated)) {
      return Future<String?>.value();
    }
    return _gateway.accessToken(config.apiAudience);
  }

  Future<void> retryAccountSync() async {
    if (!config.enabled ||
        !_state.authenticated ||
        _state.status == LalaAuthStatus.busy ||
        _state.accountSyncStatus != LalaAccountSyncStatus.error) {
      return;
    }
    await _synchronizeAccount(_sessionRevision);
  }

  Future<void> _restoreAuthenticatedSession() async {
    final revision = ++_sessionRevision;
    LalaAuthProfile? profile;
    try {
      profile = await _gateway.profile;
    } on Object {
      // Profile display is optional and must not invalidate a Logto session.
    }
    if (!_isCurrentSession(revision)) {
      return;
    }
    await _synchronizeAccount(revision, profile: profile);
  }

  Future<void> _synchronizeAccount(
    int revision, {
    LalaAuthProfile? profile,
  }) async {
    if (!_isCurrentSession(revision)) {
      return;
    }
    final selectedProfile = profile ?? _state.profile;
    final previousMe = _state.me;
    _setState(
      LalaAuthState.signedIn(
        profile: selectedProfile,
        me: previousMe,
        accountSyncStatus: LalaAccountSyncStatus.syncing,
      ),
    );
    try {
      final me = await _accountApi.getMe();
      if (!_isCurrentSession(revision)) {
        return;
      }
      _setState(
        LalaAuthState.signedIn(
          profile: selectedProfile,
          me: me,
          accountSyncStatus: LalaAccountSyncStatus.ready,
        ),
      );
    } on Object {
      if (!_isCurrentSession(revision)) {
        return;
      }
      _setState(
        LalaAuthState.signedIn(
          profile: selectedProfile,
          me: previousMe,
          accountSyncStatus: LalaAccountSyncStatus.error,
          errorMessage: safeAccountSyncErrorMessage,
        ),
      );
    }
  }

  void _invalidateSession() {
    _sessionRevision += 1;
  }

  bool _isCurrentSession(int revision) {
    return !_disposed && revision == _sessionRevision;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _setState(LalaAuthState state) {
    if (_disposed) {
      return;
    }
    _state = state;
    notifyListeners();
  }
}
