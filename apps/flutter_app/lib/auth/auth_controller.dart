import 'package:flutter/foundation.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'logto_auth_gateway.dart';

enum LalaAuthStatus { disabled, signedOut, busy, signedIn, error }

@immutable
class LalaAuthState {
  const LalaAuthState({required this.status, this.me, this.errorMessage});

  const LalaAuthState.disabled() : this(status: LalaAuthStatus.disabled);

  const LalaAuthState.signedOut() : this(status: LalaAuthStatus.signedOut);

  const LalaAuthState.busy({LalaMe? me})
    : this(status: LalaAuthStatus.busy, me: me);

  const LalaAuthState.signedIn(LalaMe me)
    : this(status: LalaAuthStatus.signedIn, me: me);

  const LalaAuthState.error({LalaMe? me, required String message})
    : this(status: LalaAuthStatus.error, me: me, errorMessage: message);

  final LalaAuthStatus status;
  final LalaMe? me;
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

  final LalaAuthConfig config;
  final LalaAuthGateway _gateway;
  final LalaAccountApi _accountApi;
  LalaAuthState _state;
  bool _disposed = false;

  LalaAuthState get state => _state;

  Future<void> initialize() async {
    if (!config.enabled) {
      _setState(const LalaAuthState.disabled());
      return;
    }

    _setState(const LalaAuthState.busy());
    try {
      if (!await _gateway.isAuthenticated) {
        _setState(const LalaAuthState.signedOut());
        return;
      }
      await _loadAccount();
    } on Object {
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
      await _loadAccount();
    } on Object {
      _setState(const LalaAuthState.error(message: safeErrorMessage));
    }
  }

  Future<void> signOut() async {
    if (!config.enabled || _state.status == LalaAuthStatus.busy) {
      return;
    }

    final previousMe = _state.me;
    _setState(LalaAuthState.busy(me: previousMe));
    try {
      await _gateway.signOut();
      _setState(const LalaAuthState.signedOut());
    } on Object {
      _setState(LalaAuthState.error(me: previousMe, message: safeErrorMessage));
    }
  }

  Future<void> deleteAccount() async {
    final currentMe = _state.me;
    if (!config.enabled ||
        currentMe == null ||
        _state.status == LalaAuthStatus.busy) {
      return;
    }

    _setState(LalaAuthState.busy(me: currentMe));
    try {
      await _accountApi.deleteMe(confirmation: 'delete-my-account');
    } on Object {
      _setState(LalaAuthState.error(me: currentMe, message: safeErrorMessage));
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
        (_state.status == LalaAuthStatus.error && _state.me == null)) {
      return Future<String?>.value();
    }
    return _gateway.accessToken(config.apiAudience);
  }

  Future<void> _loadAccount() async {
    final me = await _accountApi.getMe();
    _setState(LalaAuthState.signedIn(me));
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
