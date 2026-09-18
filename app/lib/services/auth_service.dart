import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/auth_payload.dart';
import '../models/controller.dart';
import '../models/verify_container.dart';
import 'api_service.dart';
import 'secure_store.dart';
import 'websocket_service.dart';
import '../logging.dart';

enum AuthState {
  initial,
  validating,
  passwordLogin,
  ssoLogin,
  siteSelect,
  authenticated,
  error,
}

class AuthService extends ChangeNotifier {
  final ApiService _api = ApiService();
  final WebSocketService _ws = WebSocketService();
  StreamSubscription<Map<String, dynamic>>? _wsEvents;
  Future<void>? _inFlightLockerRefresh;

  AuthService() {
    // Surface live connection state (offline / reconnecting) to the UI.
    _ws.status.addListener(_onWsStatusChanged);
    // Let the socket silently re-mint an expired token instead of dropping the
    // user back to the login screen after idle.
    _ws.onReauthRequired = _reauthenticate;
    // When the reconnect loop proves the stored credential is dead, clear the
    // session so the app routes to login (instead of spinning "offline").
    _ws.onSessionExpired = _handleSessionExpired;
    _wsEvents = _ws.responses.listen(_onWsEvent);
  }

  /// Invoked by [WebSocketService] when background reconnection determines the
  /// stored credential is permanently rejected. Clearing the session flips
  /// [state] to [AuthState.initial] and notifies listeners; the app root routes
  /// to the login screen.
  void _handleSessionExpired() {
    talker.warning('Session credentials were rejected; signing out');
    logout();
  }

  void _onWsStatusChanged() {
    notifyListeners();
    if (_ws.status.value == WsStatus.connected && _authPayload != null) {
      unawaited(refreshLockerReservations());
    }
  }

  void _onWsEvent(Map<String, dynamic> event) {
    if (isLockerReservationChangeEvent(event)) {
      unawaited(refreshLockerReservations());
    }
  }

  AuthState _state = AuthState.initial;
  String? _errorMessage;
  String? _email;
  VerifyContainer? _verifyResult;
  Controller? _controller;
  AuthPayload? _authPayload;

  String? _ssoAccessToken;
  String? _ssoIdToken;

  // Persisted credentials used to refresh an expired session (see
  // [_reauthenticate]). The password and SSO refresh token are kept in the OS
  // keystore via [SecureStore]; the rest live in the session blob.
  String? _password;
  String? _sitekey;
  String? _ssoRefreshToken;
  String? _ssoTokenEndpoint;
  String? _ssoClientId;

  ApiService get api => _api;
  AuthState get state => _state;
  String? get errorMessage => _errorMessage;
  String? get email => _email;
  VerifyContainer? get verifyResult => _verifyResult;
  Controller? get controller => _controller;
  AuthPayload? get authPayload => _authPayload;
  WebSocketService get ws => _ws;

  Future<void> validateUsername(String email) async {
    talker.info('Validating sign-in identifier');
    _email = email;
    _state = AuthState.validating;
    _errorMessage = null;
    notifyListeners();

    try {
      _verifyResult = await _api.validateUsername(email);
      if (_verifyResult!.isSSO) {
        _state = AuthState.ssoLogin;
      } else {
        _state = AuthState.passwordLogin;
      }
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Username validation failed');
      _errorMessage = error.toString();
      _state = AuthState.error;
    }
    notifyListeners();
  }

  Future<bool> loginPassword(String email, String password) async {
    talker.info('Starting password sign-in');
    _state = AuthState.passwordLogin;
    _errorMessage = null;
    notifyListeners();

    try {
      await _api.loginPassword(email, password);
      _state = AuthState.siteSelect;
      notifyListeners();
      return true;
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Password sign-in failed');
      _errorMessage = error.toString();
      _state = AuthState.error;
      notifyListeners();
      return false;
    }
  }

  Future<bool> loginSSO(
    String email,
    String accessToken,
    String idToken, {
    String? refreshToken,
    String? tokenEndpoint,
    String? clientId,
  }) async {
    talker.info('Starting SSO sign-in');
    _errorMessage = null;
    notifyListeners();

    try {
      await _api.ssoGetToken(email, accessToken, idToken);
      _ssoAccessToken = accessToken;
      _ssoIdToken = idToken;
      // Stash the OIDC refresh context so an expired SSO session can be
      // refreshed silently later (see [_reauthenticate]).
      _ssoRefreshToken = refreshToken;
      _ssoTokenEndpoint = tokenEndpoint;
      _ssoClientId = clientId;
      _state = AuthState.siteSelect;
      notifyListeners();
      return true;
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'SSO sign-in failed');
      _errorMessage = error.toString();
      _state = AuthState.error;
      notifyListeners();
      return false;
    }
  }

  Future<bool> loginToSiteWithPassword(
    String email,
    String password,
    String sitekey,
  ) async {
    talker.info('Signing in to selected site with password');
    _errorMessage = null;
    notifyListeners();

    try {
      _controller = await _api.loginToSite(email, password, sitekey);
      _password = password;
      _sitekey = sitekey;
      await _connectWebSocket();
      _state = AuthState.authenticated;
      notifyListeners();
      return true;
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Site password sign-in failed');
      _errorMessage = error.toString();
      _state = AuthState.error;
      notifyListeners();
      return false;
    }
  }

  Future<bool> ssoLoginToSite(
    String email,
    String accessToken,
    String idToken,
    String sitekey,
  ) async {
    talker.info('Signing in to selected site with SSO');
    _errorMessage = null;
    notifyListeners();

    try {
      _controller = await _api.ssoLoginToSite(
        email,
        accessToken,
        idToken,
        sitekey,
      );
      _ssoAccessToken = accessToken;
      _ssoIdToken = idToken;
      _sitekey = sitekey;
      await _connectWebSocket();
      _state = AuthState.authenticated;
      notifyListeners();
      return true;
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Site SSO sign-in failed');
      _errorMessage = error.toString();
      _state = AuthState.error;
      notifyListeners();
      return false;
    }
  }

  Future<void> _connectWebSocket() async {
    talker.info('Connecting locker service WebSocket');
    final ctrl = _controller!;
    // Arm the auto-reconnect loop with the current coordinates *before* any
    // refresh/connect attempt, so a transient failure here still leaves a
    // working retry loop (it re-mints the token each attempt) instead of a dead
    // "offline" state with no retries — the cold-start bug that stranded users.
    _ws.primeReconnect(
      socketUri: ctrl.socketURI,
      token: ctrl.token,
      uid: ctrl.uid,
      uidToken: ctrl.uidToken,
      idToken: _ssoIdToken,
      accessToken: _ssoAccessToken,
    );
    // Pre-flight the JWT exactly like the original (WebsocketSession.authorise
    // → JWTEvaluation.isValid): never open the socket with a token we already
    // know is expired. A session restored after long idle gets a fresh token
    // here so it comes up online instead of flashing "offline".
    if (_ws.isJwtExpired(ctrl.token)) {
      final fresh = await _reauthenticate();
      if (fresh == null) {
        throw const WsAuthRejectedException(
          'Session expired and could not be refreshed',
        );
      }
    }
    // _reauthenticate() may have replaced the controller with a fresh one.
    final connectCtrl = _controller!;
    _authPayload = await _ws.connect(
      socketUri: connectCtrl.socketURI,
      token: connectCtrl.token,
      uid: connectCtrl.uid,
      uidToken: connectCtrl.uidToken,
      idToken: _ssoIdToken,
      accessToken: _ssoAccessToken,
    );
    await _saveSession();
    talker.info('Locker service WebSocket authenticated');

    if (!_authPayload!.hasLockers) {
      _errorMessage = 'This site does not have lockers enabled';
    }
  }

  /// Refreshes the current user's locker reservations across all banks.
  ///
  /// The original FloorSense client uses controller id 0 for this query and
  /// re-fetches it after locker-reserved/released events. Keeping this separate
  /// from the auth handshake prevents the home screen from showing a stale
  /// locker after a reservation changes in another client.
  Future<void> refreshLockerReservations() {
    if (_authPayload == null || !_ws.isConnected || !_ws.isAuthenticated) {
      return Future.value();
    }
    return _inFlightLockerRefresh ??= _doRefreshLockerReservations()
        .whenComplete(() => _inFlightLockerRefresh = null);
  }

  Future<void> _doRefreshLockerReservations() async {
    try {
      final reservations = await _ws.getReservations(0);
      final current = _authPayload;
      if (current == null) return;
      _authPayload = current.copyWith(reservations: reservations);
      talker.info('Refreshed current-user locker reservations');
      notifyListeners();
    } catch (error, stackTrace) {
      talker.handle(
        error,
        stackTrace,
        'Could not refresh current-user locker reservations',
      );
    }
  }

  Future<void> _saveSession() async {
    if (_controller == null) return;
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'controller': _controller!.toJson(),
      'email': _email ?? '',
      if (_sitekey != null) 'sitekey': _sitekey,
      if (_ssoAccessToken != null) 'sso_access_token': _ssoAccessToken,
      if (_ssoIdToken != null) 'sso_id_token': _ssoIdToken,
      if (_ssoTokenEndpoint != null) 'sso_token_endpoint': _ssoTokenEndpoint,
      if (_ssoClientId != null) 'sso_client_id': _ssoClientId,
    };
    await prefs.setString('floorsense.session', jsonEncode(data));
    // Secrets used to refresh the session go to the OS keystore, not prefs.
    await SecureStore.writePassword(_password);
    await SecureStore.writeSsoRefreshToken(_ssoRefreshToken);
  }

  /// Holds the single in-flight refresh so concurrent callers dedupe onto it.
  Future<WsReauth?>? _inFlightReauth;

  /// Re-mints an expired token from the persisted credential, mirroring the
  /// original app's `reauthenticateSession`. Returns a fresh [WsReauth] for the
  /// socket, or null if no usable credential is stored (forcing a re-login).
  /// Wired to [WebSocketService.onReauthRequired] in the constructor.
  ///
  /// Serialized: concurrent callers (e.g. the cold-start pre-flight and a
  /// reconnect firing at the same time) share a single in-flight refresh. This
  /// matters because the provider's refresh tokens are single-use / rotating —
  /// two parallel refreshes would race, the second replaying a token the first
  /// already rotated away, and the server would reject it and force a logout.
  /// Mirrors the original's `ReAuthenticator.isRefreshing` guard.
  Future<WsReauth?> _reauthenticate() {
    return _inFlightReauth ??= _doReauthenticate().whenComplete(
      () => _inFlightReauth = null,
    );
  }

  Future<WsReauth?> _doReauthenticate() async {
    final hasPassword = _password != null && _sitekey != null && _email != null;
    // SSO can only silently re-auth with a refresh token: the stored access
    // token lives ~1h and is almost always expired by the time we re-auth, so
    // replaying it just fails. The refresh is brokered by the smartalock
    // backend, so all we need is the email + refresh token; otherwise fall
    // through to a clean re-login.
    final hasSso =
        _email != null && _sitekey != null && _ssoRefreshToken != null;
    // No usable credential to refresh with — a real login is unavoidable.
    if (!hasPassword && !hasSso) {
      talker.warning(
        'Session refresh unavailable: no stored refresh credential',
      );
      return null;
    }

    try {
      talker.info('Refreshing expired locker service session');
      if (hasPassword) {
        // Password session: re-login to mint a fresh JWT (+ uid/uidToken).
        _controller = await _api.loginToSite(_email!, _password!, _sitekey!);
      } else {
        // SSO session: refresh the OIDC tokens via the smartalock backend
        // (mirrors the original's LoginClient.ssoRefresh), then re-login to
        // mint a fresh controller JWT. We only get here with a refresh token.
        final refreshed = await _api.refreshSsoToken(
          _email!,
          _ssoRefreshToken!,
        );
        _ssoAccessToken =
            (refreshed['access_token'] as String?) ?? _ssoAccessToken;
        _ssoIdToken = (refreshed['id_token'] as String?) ?? _ssoIdToken;
        // The provider rotates the refresh token on each use; persist the new
        // one (done by _saveSession below) or the next refresh fails.
        _ssoRefreshToken =
            (refreshed['refresh_token'] as String?) ?? _ssoRefreshToken;
        if (_ssoAccessToken == null || _ssoIdToken == null) return null;
        _controller = await _api.ssoLoginToSite(
          _email!,
          _ssoAccessToken!,
          _ssoIdToken!,
          _sitekey!,
        );
      }
    } on ApiException catch (e) {
      // A 4xx on the credential refresh/login means the stored credential
      // itself is rejected — an expired/revoked refresh token surfaces as
      // OAuth 400 (invalid_grant), a changed password as 401/403. Retrying
      // can't help, so force a clean re-login. Everything else (5xx, timeouts,
      // no status code = network failure, 429 rate-limit) is transient:
      // rethrow so the caller keeps the session and retries rather than
      // logging the user out on a blip.
      final code = e.statusCode;
      if (code == 400 || code == 401 || code == 403) {
        talker.warning('Session refresh rejected by server (HTTP $code)');
        return null;
      }
      talker.handle(e, StackTrace.current, 'Session refresh request failed');
      rethrow;
    }

    await _saveSession();
    final ctrl = _controller!;
    return WsReauth(
      token: ctrl.token,
      uid: ctrl.uid,
      uidToken: ctrl.uidToken,
      idToken: _ssoIdToken,
      accessToken: _ssoAccessToken,
    );
  }

  Future<bool> tryRestoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionJson = prefs.getString('floorsense.session');
    if (sessionJson == null) {
      talker.info('No saved session to restore');
      return false;
    }
    talker.info('Restoring saved locker service session');

    try {
      final data = jsonDecode(sessionJson) as Map<String, dynamic>;
      final ctrlJson = data['controller'] as Map<String, dynamic>?;
      if (ctrlJson == null) return false;

      _email = data['email'] as String?;
      _sitekey = data['sitekey'] as String?;
      _ssoAccessToken = data['sso_access_token'] as String?;
      _ssoIdToken = data['sso_id_token'] as String?;
      _ssoTokenEndpoint = data['sso_token_endpoint'] as String?;
      _ssoClientId = data['sso_client_id'] as String?;
      _password = await SecureStore.readPassword();
      _ssoRefreshToken = await SecureStore.readSsoRefreshToken();
      _controller = Controller.fromJson(ctrlJson);

      try {
        await _connectWebSocket();
      } on WsAuthRejectedException {
        // Credentials genuinely rejected (and the silent refresh in
        // reconnect() couldn't recover) — drop the session and re-login.
        await prefs.remove('floorsense.session');
        await SecureStore.clear();
        _controller = null;
        _authPayload = null;
        return false;
      } catch (_) {
        // Transient/network failure: keep the session and let the WebSocket
        // auto-reconnect in the background rather than forcing a full login.
        _ws.startAutoReconnect();
        _state = AuthState.authenticated;
        notifyListeners();
        return true;
      }
      _state = AuthState.authenticated;
      notifyListeners();
      return true;
    } catch (_) {
      talker.warning('Saved session was invalid and has been cleared');
      await prefs.remove('floorsense.session');
      await SecureStore.clear();
      _controller = null;
      return false;
    }
  }

  Future<void> logout() async {
    talker.info('Signing out and clearing stored session');
    _ws.close();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('floorsense.session');
    await SecureStore.clear();
    _controller = null;
    _email = null;
    _verifyResult = null;
    _errorMessage = null;
    _ssoAccessToken = null;
    _ssoIdToken = null;
    _password = null;
    _sitekey = null;
    _ssoRefreshToken = null;
    _ssoTokenEndpoint = null;
    _ssoClientId = null;
    _authPayload = null;
    _state = AuthState.initial;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _ws.status.removeListener(_onWsStatusChanged);
    _wsEvents?.cancel();
    _ws.dispose();
    super.dispose();
  }
}

@visibleForTesting
bool isLockerReservationChangeEvent(Map<String, dynamic> event) {
  final code = (event['code'] as num?)?.toInt();
  return event['type'] == 'event' && (code == 33 || code == 34);
}

String generateCodeVerifier() {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  final random = Random.secure();
  return List.generate(64, (_) => chars[random.nextInt(chars.length)]).join();
}

String generateCodeChallenge(String codeVerifier) {
  final bytes = utf8.encode(codeVerifier);
  final digest = sha256.convert(bytes);
  return base64Url.encode(digest.bytes).replaceAll('=', '');
}

String generateState() {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
}
