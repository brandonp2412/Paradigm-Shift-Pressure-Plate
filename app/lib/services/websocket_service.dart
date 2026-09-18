import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/auth_payload.dart';
import '../models/bank.dart';
import '../models/floor_plan.dart';
import '../models/locker_reservation.dart';
import '../logging.dart';

/// Thrown when the server actively rejects the auth handshake (bad/expired
/// credentials), as opposed to a transient network failure. Callers use this
/// to decide between forcing a re-login vs. silently retrying.
class WsAuthRejectedException implements Exception {
  final String message;
  const WsAuthRejectedException(this.message);
  @override
  String toString() => 'WsAuthRejectedException: $message';
}

enum WsStatus { disconnected, connecting, connected }

/// A freshly minted credential set returned by [WebSocketService.onReauthRequired]
/// when the stored token has expired. Mirrors the original app's
/// `reauthenticateSession`, which re-mints the JWT (and uid/uidToken) from the
/// persisted credential.
class WsReauth {
  final String token;
  final String? uid;
  final String? uidToken;
  final String? idToken;
  final String? accessToken;
  const WsReauth({
    required this.token,
    this.uid,
    this.uidToken,
    this.idToken,
    this.accessToken,
  });
}

class WebSocketService {
  WebSocketChannel? _channel;
  WebSocket? _socket;
  bool _isConnected = false;
  bool _isAuthenticated = false;
  bool _disposed = false;
  final _responseController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _requestQueue = <_QueuedRequest>[];
  bool _pendingRequest = false;

  /// Accumulates raw socket text across frames. A single logical message can
  /// be split across multiple WebSocket frames, and one frame may also carry
  /// several CRLF-delimited messages, so we cannot assume frame == message.
  String _rxBuffer = '';

  /// Observable connection state for the UI (offline / reconnecting banners).
  final ValueNotifier<WsStatus> status = ValueNotifier<WsStatus>(
    WsStatus.disconnected,
  );

  static const Duration _pingInterval = Duration(seconds: 30);
  static const List<Duration> _backoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;

  /// Supplied by [AuthService]: mints a fresh credential set when the current
  /// token has expired or been rejected. Returns null when refresh is
  /// impossible (no stored credential), which forces a re-login.
  Future<WsReauth?> Function()? onReauthRequired;

  /// Supplied by [AuthService]: invoked when the reconnect loop determines the
  /// stored credential is permanently rejected (a real re-login is required).
  /// Lets the session layer clear the session and route to the login screen
  /// instead of leaving the user on a dead "offline" banner forever.
  void Function()? onSessionExpired;

  String? _lastSocketUri;
  String? _lastToken;
  String? _lastUid;
  String? _lastUidToken;
  String? _lastIdToken;
  String? _lastAccessToken;

  bool get isConnected => _isConnected;
  bool get isAuthenticated => _isAuthenticated;
  Stream<Map<String, dynamic>> get responses => _responseController.stream;

  Future<AuthPayload> connect({
    required String socketUri,
    required String token,
    String? uid,
    String? uidToken,
    String? idToken,
    String? accessToken,
  }) async {
    talker.info('Opening locker service WebSocket connection');
    _lastSocketUri = socketUri;
    _lastToken = token;
    _lastUid = uid;
    _lastUidToken = uidToken;
    _lastIdToken = idToken;
    _lastAccessToken = accessToken;
    _reconnectTimer?.cancel();
    _disconnect();
    status.value = WsStatus.connecting;

    try {
      final webSocket = await WebSocket.connect(
        socketUri,
        headers: {'Authorization': 'Bearer $token'},
      );
      // Protocol-level keepalive: also surfaces a dead peer (e.g. an idle
      // socket dropped by the OS/server) as an onDone so we can reconnect.
      webSocket.pingInterval = _pingInterval;
      _socket = webSocket;
      _channel = IOWebSocketChannel(webSocket);

      final completer = Completer<AuthPayload>();

      _channel!.stream.listen(
        (data) {
          if (_socket != webSocket) {
            return; // stale listener from a prior socket
          }
          if (data is String) {
            _handleMessage(data, completer);
          } else if (data is List<int>) {
            _handleMessage(utf8.decode(data), completer);
          }
        },
        onError: (error) {
          talker.handle(
            error,
            StackTrace.current,
            'Locker service WebSocket stream failed',
          );
          if (!completer.isCompleted) completer.completeError(error);
          if (_socket != webSocket) return;
          _onDropped();
        },
        onDone: () {
          talker.warning('Locker service WebSocket closed');
          if (!completer.isCompleted) {
            completer.completeError(
              StateError('WebSocket closed before auth response'),
            );
          }
          if (_socket != webSocket) return;
          _onDropped();
        },
        cancelOnError: false,
      );

      _isConnected = true;

      String authMsg;
      if (uid != null && uidToken != null) {
        final authHash = md5
            .convert(
              utf8.encode(
                (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
              ),
            )
            .toString();
        authMsg = jsonEncode({
          'uid': uid,
          'uidtoken': uidToken,
          'auth': authHash,
        });
      } else if (idToken != null && accessToken != null) {
        authMsg = jsonEncode({
          'id_token': idToken,
          'access_token': accessToken,
        });
      } else {
        _channel!.sink.close();
        throw StateError(
          'Auth requires either (uid+uidToken) or (idToken+accessToken)',
        );
      }

      _channel!.sink.add('POST /auth\r\n$authMsg\r\n');

      return await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('Auth handshake timed out'),
      );
    } catch (error, stackTrace) {
      talker.handle(
        error,
        stackTrace,
        'Locker service WebSocket connection failed',
      );
      // Any failure before reaching the authenticated state must clear the
      // "connecting" status — otherwise the UI banner spins "Reconnecting…"
      // forever. Only reset if no other path (e.g. _onDropped) already did.
      if (!_disposed && status.value == WsStatus.connecting) {
        status.value = WsStatus.disconnected;
      }
      rethrow;
    }
  }

  void _handleMessage(String raw, Completer<AuthPayload>? authCompleter) {
    // Buffer across frames and process whole CRLF-delimited messages only.
    // JSON bodies never contain a raw newline, so the newline is a safe
    // record separator. A trailing partial message (no newline yet) stays in
    // the buffer until the rest of it arrives in a later frame.
    _rxBuffer += raw;
    int idx;
    while ((idx = _rxBuffer.indexOf('\n')) != -1) {
      final chunk = _rxBuffer.substring(0, idx).trim();
      _rxBuffer = _rxBuffer.substring(idx + 1);
      if (chunk.isEmpty) continue;
      _processChunk(chunk, authCompleter);
    }
  }

  void _processChunk(String chunk, Completer<AuthPayload>? authCompleter) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(chunk) as Map<String, dynamic>;
    } on FormatException {
      return; // non-JSON keepalive, ignore
    } catch (_) {
      return; // not a JSON object, ignore
    }

    final type = json['type'] as String?;

    if (type == 'response' &&
        authCompleter != null &&
        !authCompleter.isCompleted) {
      if (json['result'] == true) {
        final info = json['info'] as Map<String, dynamic>? ?? {};
        _isAuthenticated = true;
        _reconnectAttempt = 0;
        status.value = WsStatus.connected;
        talker.info('Locker service WebSocket authenticated');
        authCompleter.complete(AuthPayload.fromJson(info));
      } else {
        authCompleter.completeError(
          WsAuthRejectedException(json['message']?.toString() ?? 'Auth failed'),
        );
      }
      return;
    }

    if (type == 'response') {
      // Bare acknowledgement frame ({"type":"response","result":...}) with no
      // payload. The server emits these around the substantive response; the
      // original app skips them and waits for the real frame, so we do too —
      // popping the queue here would mis-pair this with the pending request.
      if (json.length == 2 && json.containsKey('result')) {
        return;
      }
      // Normalise success signalling. Failures are marked with result:false
      // (plus a message); successful responses may omit `result` entirely. The
      // original treats any non-error response frame as success, so synthesize
      // result:true so callers (and _extractData) can rely on it.
      if (json['result'] != false) {
        json['result'] = true;
      }
      _handleResponse(json);
    } else {
      // Events (locker reserved/released, desk updates, …) and anything else.
      _responseController.add(json);
    }
  }

  void _handleResponse(Map<String, dynamic> json) {
    if (_requestQueue.isNotEmpty) {
      final queued = _requestQueue.removeAt(0);
      _pendingRequest = false;
      queued.completer.complete(json);
    }
    _processQueue();
  }

  Future<Map<String, dynamic>> _sendRequest(String message) async {
    if (!_isConnected || !_isAuthenticated || _channel == null) {
      // Connection may have dropped while idle; try once to bring it back
      // before failing, so user actions don't surface "Bad state: Not
      // connected" after the app has sat idle.
      final ok = await reconnect();
      if (!ok || _channel == null) {
        throw StateError('Not connected');
      }
    }
    final completer = Completer<Map<String, dynamic>>();
    _requestQueue.add(_QueuedRequest(message, completer));
    _processQueue();
    return completer.future.timeout(const Duration(seconds: 15));
  }

  void _processQueue() {
    if (_pendingRequest || _requestQueue.isEmpty) return;
    _pendingRequest = true;
    final req = _requestQueue.first;
    _channel!.sink.add(req.message);
  }

  Future<List<Bank>> getBankList() async {
    final resp = await _sendRequest('GET /slave-list\r\n');
    final data = _extractData(resp);
    if (data is List) {
      return data
          .map((e) => Bank.fromJson(e as Map<String, dynamic>))
          .where((b) => b.hasLockers)
          .toList();
    }
    return [];
  }

  Future<List<LockerReservation>> getReservations(int cid) async {
    final resp = await _sendRequest(
      'GET /res-list?cid=$cid&active=1&future=1&bankname=1\r\n',
    );
    final data = _extractData(resp);
    if (data is List) {
      return data
          .map((e) => LockerReservation.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> getLockerStatus(int cid) async {
    final resp = await _sendRequest(
      'GET /slave-lockstatus?cid=$cid&active=1&future=1\r\n',
    );
    return resp;
  }

  /// Every floor plan the user can see (`planid` + `deskloc`). The
  /// `/floorplan-list` response is a `List<Floor>` and carries no geometry — the
  /// lockers live in each plan's static floor-details file.
  Future<List<FloorPlan>> getFloorplanList() async {
    final resp = await _sendRequest('GET /floorplan-list\r\n');
    final data = _extractData(resp);
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(FloorPlan.fromJson)
          .toList();
    }
    return [];
  }

  /// Fetches a plan's static floor-details file from `<webUri>/floorplans/<deskLoc>`
  /// and returns its lockers. This is where the locker geometry (names + bank)
  /// actually lives — the socket `/floorplan*` calls don't include it. Requires
  /// the same bearer token as the socket (the files are auth-protected).
  Future<List<LockerPolygon>> _fetchFloorLockers(
    String webUri,
    String deskLoc,
  ) async {
    if (deskLoc.isEmpty || _lastToken == null) return const [];
    final base = webUri.endsWith('/')
        ? webUri.substring(0, webUri.length - 1)
        : webUri;
    final uri = Uri.parse('$base/floorplans/$deskLoc');
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set('Authorization', 'Bearer $_lastToken');
      request.headers.set('Accept', 'application/json');
      final response = await request.close();
      if (response.statusCode != 200) return const [];
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        return FloorPlan.lockersFromDetails(json);
      }
      return const [];
    } finally {
      client.close(force: true);
    }
  }

  /// Walks every floor plan and groups locker names by bank (`cid`). The result
  /// is a static-ish map of bank -> sorted locker keys (e.g. `{12: [L034, L035]}`),
  /// suitable for long-term caching.
  ///
  /// Note: floor-plan polygons identify only the bank, not the locker *type*, so
  /// this is per-bank, not per-section.
  Future<Map<int, List<String>>> buildLockerNameMap(String webUri) async {
    talker.info('Building locker-name map from floor plans');
    final listed = await getFloorplanList();
    final plans = <FloorPlan>[];
    for (final plan in listed) {
      try {
        final lockers = await _fetchFloorLockers(webUri, plan.deskLoc);
        if (lockers.isNotEmpty) {
          plans.add(FloorPlan(planId: plan.planId, lockerPolygons: lockers));
        }
      } catch (error, stackTrace) {
        talker.handle(error, stackTrace, 'Could not load a floor plan');
      }
    }
    return groupLockerNames(plans);
  }

  /// Groups locker names by bank (`cid`) across floor plans, deduped and sorted.
  /// Lockers with no `cid` can't be attributed to a bank and are dropped.
  @visibleForTesting
  static Map<int, List<String>> groupLockerNames(List<FloorPlan> plans) {
    final byBank = <int, Set<String>>{};
    for (final plan in plans) {
      for (final locker in plan.lockerPolygons) {
        final cid = locker.cid;
        if (cid == null) continue;
        byBank.putIfAbsent(cid, () => <String>{}).add(locker.id);
      }
    }
    return byBank.map((cid, keys) {
      final sorted = keys.toList()..sort();
      return MapEntry(cid, sorted);
    });
  }

  dynamic _extractData(Map<String, dynamic> resp) {
    if (resp['result'] == true) {
      return resp['info'] ?? resp['data'];
    }
    if (resp['result'] == false) {
      throw Exception(resp['message'] ?? 'Request failed');
    }
    final list = resp.values.whereType<List>().firstOrNull;
    return list;
  }

  Future<Map<String, dynamic>> createReservation(int cid, String type) async {
    // Match the original: omit `type` entirely for an any-locker reservation;
    // only send it when a specific section type was chosen. Sending an empty
    // string can be rejected by the controller.
    final body = jsonEncode({'cid': cid, if (type.isNotEmpty) 'type': type});
    return _sendRequest('POST /res-create\r\n$body\r\n');
  }

  Future<Map<String, dynamic>> releaseReservation(String resid) async {
    final body = jsonEncode({'resid': resid});
    return _sendRequest('POST /res-release\r\n$body\r\n');
  }

  Future<Map<String, dynamic>> unlockLocker(int cid, String key) async {
    final body = jsonEncode({'cid': cid, 'key': key});
    return _sendRequest('POST /locker-unlock\r\n$body\r\n');
  }

  /// Re-establish the connection using the credentials from the last
  /// [connect]. Returns true once connected + authenticated. Returns false on
  /// a transient failure (caller may retry). Rethrows
  /// [WsAuthRejectedException] so the caller can force a re-login.
  ///
  /// When [onReauthRequired] is wired, an expired token is silently refreshed
  /// and the connection retried — mirroring the original app, which never
  /// forces a re-login after idle. A re-login is only surfaced once the
  /// refresh itself fails or is exhausted.
  Future<bool> reconnect() async {
    if (_isConnected && _isAuthenticated) return true;
    if (_lastSocketUri == null || _lastToken == null) return false;

    // Proactive refresh: if the stored JWT has expired during idle, mint a
    // fresh one before opening the socket (mirrors the original's
    // JWTEvaluation pre-flight check in WebsocketSession.authorise). A
    // transient failure here (e.g. no network) returns false so the caller
    // keeps the session and retries; only a missing/rejected credential
    // surfaces as WsAuthRejectedException.
    if (onReauthRequired != null && _isTokenExpired(_lastToken!)) {
      final bool refreshed;
      try {
        refreshed = await _reauth();
      } catch (error, stackTrace) {
        talker.handle(
          error,
          stackTrace,
          'Expired-session refresh failed during reconnect',
        );
        return false; // transient refresh failure — keep session, retry later
      }
      if (!refreshed) {
        throw const WsAuthRejectedException(
          'Session expired and could not be refreshed',
        );
      }
    }

    try {
      await _connectWithLast();
      return _isConnected && _isAuthenticated;
    } on WsAuthRejectedException {
      // Reactive refresh: the server rejected the credentials. Try one silent
      // refresh + reconnect before surfacing the rejection to force a login.
      final bool refreshed;
      try {
        refreshed = onReauthRequired != null && await _reauth();
      } catch (error, stackTrace) {
        talker.handle(
          error,
          stackTrace,
          'Reactive session refresh failed during reconnect',
        );
        return false; // transient refresh failure — keep session, retry later
      }
      if (refreshed) {
        try {
          await _connectWithLast();
          return _isConnected && _isAuthenticated;
        } on WsAuthRejectedException {
          rethrow;
        } catch (error, stackTrace) {
          talker.handle(
            error,
            stackTrace,
            'Locker service reconnect failed after refresh',
          );
          return false;
        }
      }
      rethrow;
    } catch (error, stackTrace) {
      talker.handle(
        error,
        stackTrace,
        'Locker service WebSocket connection failed',
      );
      return false;
    }
  }

  /// Seeds the coordinates used by [reconnect]/[startAutoReconnect] without
  /// opening a socket, so the auto-reconnect loop is armed from a restored
  /// (possibly expired) controller *before* the first connect/refresh attempt.
  /// Without this, a transient failure during a cold-start refresh leaves the
  /// `_last*` fields null and the session stuck "offline" with no retries.
  /// No-op while a live connection exists — its own coordinates must win.
  void primeReconnect({
    required String socketUri,
    required String token,
    String? uid,
    String? uidToken,
    String? idToken,
    String? accessToken,
  }) {
    if (_isConnected && _isAuthenticated) return;
    _lastSocketUri = socketUri;
    _lastToken = token;
    _lastUid = uid;
    _lastUidToken = uidToken;
    _lastIdToken = idToken;
    _lastAccessToken = accessToken;
  }

  Future<void> _connectWithLast() => connect(
    socketUri: _lastSocketUri!,
    token: _lastToken!,
    uid: _lastUid,
    uidToken: _lastUidToken,
    idToken: _lastIdToken,
    accessToken: _lastAccessToken,
  );

  /// Asks [onReauthRequired] for a fresh credential set and adopts it.
  ///
  /// Returns false only when the callback reports that a login is required
  /// (null). A transient failure inside the callback (e.g. no network) is
  /// rethrown so callers keep the session and retry rather than forcing a
  /// re-login — mirroring the original, which re-mints and reconnects
  /// indefinitely and only logs out when the credential is genuinely rejected.
  /// The retry cadence is bounded by the backoff timer in [_scheduleReconnect],
  /// so there is no need for a hard attempt cap here.
  Future<bool> _reauth() async {
    final cb = onReauthRequired;
    if (cb == null) return false;
    final fresh = await cb();
    if (fresh == null) return false;
    _lastToken = fresh.token;
    _lastUid = fresh.uid;
    _lastUidToken = fresh.uidToken;
    _lastIdToken = fresh.idToken;
    _lastAccessToken = fresh.accessToken;
    return true;
  }

  /// Whether [token]'s `exp` has passed. Lets the session layer pre-flight an
  /// expired JWT before the first connect (mirrors the original's
  /// JWTEvaluation.isValid check in WebsocketSession.authorise).
  bool isJwtExpired(String token) => _isTokenExpired(token);

  /// Decodes a JWT and reports whether its `exp` has passed (with a small skew
  /// so we refresh just before the server would reject). Returns false when the
  /// token can't be parsed, deferring to the server's own validation.
  bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final payload =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! int) return false;
      final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return DateTime.now().isAfter(
        expiry.subtract(const Duration(seconds: 30)),
      );
    } catch (_) {
      return false;
    }
  }

  /// Called when an established connection drops. Schedules a backoff
  /// reconnect so an idle/networking blip recovers without user action.
  void _onDropped() {
    final wasUp = _isConnected || _isAuthenticated;
    _isConnected = false;
    _isAuthenticated = false;
    _pendingRequest = false;
    if (_disposed) return;
    status.value = WsStatus.disconnected;
    talker.warning('Locker service WebSocket disconnected');
    // Only auto-reconnect connections that had previously come up and have
    // reusable credentials.
    if (wasUp && _lastSocketUri != null && _lastToken != null) {
      _scheduleReconnect();
    }
  }

  /// Begin background reconnect attempts (used when an initial connect failed
  /// transiently, so no stream-level drop event was emitted to trigger them).
  void startAutoReconnect() {
    if (_disposed || (_isConnected && _isAuthenticated)) return;
    if (_lastSocketUri == null || _lastToken == null) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    final delay = _backoff[_reconnectAttempt.clamp(0, _backoff.length - 1)];
    _reconnectAttempt++;
    talker.info('Scheduling locker service reconnect in ${delay.inSeconds}s');
    _reconnectTimer = Timer(delay, () async {
      if (_disposed || (_isConnected && _isAuthenticated)) return;
      try {
        await reconnect();
      } on WsAuthRejectedException {
        // The stored credential is permanently rejected: stop the retry loop
        // and ask the session layer to force a clean re-login, rather than
        // leaving the user on a dead "offline" screen forever.
        onSessionExpired?.call();
        return;
      } catch (error, stackTrace) {
        talker.handle(
          error,
          stackTrace,
          'Scheduled locker service reconnect failed',
        );
      }
      if (!_disposed && !(_isConnected && _isAuthenticated)) {
        _scheduleReconnect();
      }
    });
  }

  void _disconnect() {
    _requestQueue.clear();
    _pendingRequest = false;
    _rxBuffer =
        ''; // drop any partial frame so it can't bleed into a new socket
    _channel?.sink.close();
    _channel = null;
    _socket = null;
    _isConnected = false;
    _isAuthenticated = false;
  }

  /// Tear down the active connection but keep the service reusable (e.g. on
  /// logout, before a subsequent login reuses the same instance).
  void close() {
    talker.info('Closing locker service WebSocket');
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;
    _disconnect();
    _lastSocketUri = null;
    _lastToken = null;
    _lastUid = null;
    _lastUidToken = null;
    _lastIdToken = null;
    _lastAccessToken = null;
    if (!_disposed) status.value = WsStatus.disconnected;
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _disconnect();
    status.dispose();
    _responseController.close();
  }
}

class _QueuedRequest {
  final String message;
  final Completer<Map<String, dynamic>> completer;
  _QueuedRequest(this.message, this.completer);
}
