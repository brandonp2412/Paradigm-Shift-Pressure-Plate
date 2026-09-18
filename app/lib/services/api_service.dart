import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/controller.dart';
import '../models/site.dart';
import '../models/verify_container.dart';
import '../logging.dart';

class ApiService {
  static const String baseUrl = 'https://api.smartalock.com';

  String? _token;

  set token(String? t) => _token = t;

  Map<String, String> get _authHeader =>
      _token != null ? {'Authorization': 'Bearer $_token'} : {};

  Map<String, dynamic> _parseResponse(http.Response resp) {
    try {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      final preview = resp.body.length > 300
          ? '${resp.body.substring(0, 300)}...'
          : resp.body;
      throw ApiException(
        'Server returned HTTP ${resp.statusCode} with non-JSON body',
        statusCode: resp.statusCode,
        body: preview,
      );
    }
  }

  Future<VerifyContainer> validateUsername(String username) async {
    talker.debug('Requesting account configuration');
    final uri = Uri.parse(
      '$baseUrl/config',
    ).replace(queryParameters: {'username': username});
    final resp = await http.get(uri);
    final json = _parseResponse(resp);
    return VerifyContainer.fromJson(json);
  }

  Future<String> loginPassword(
    String username,
    String password, {
    String? sitekey,
  }) async {
    talker.debug('Requesting password login');
    final body = <String, String>{'username': username, 'password': password};
    if (sitekey != null) body['sitekey'] = sitekey;

    final resp = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );
    final json = _parseResponse(resp);
    if (json['token'] != null) {
      _token = json['token'] as String;
      return _token!;
    }
    throw ApiException(
      json['message'] ?? 'Login failed',
      statusCode: resp.statusCode,
    );
  }

  Future<Controller> loginToSite(
    String username,
    String password,
    String sitekey,
  ) async {
    talker.debug('Requesting site controller for password login');
    final resp = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': username, 'password': password, 'sitekey': sitekey},
    );
    final json = _parseResponse(resp);
    if (json['token'] == null) {
      throw ApiException(
        json['message'] ?? 'Site login failed',
        statusCode: resp.statusCode,
      );
    }
    final ctrl = Controller.fromJson(json);
    _token = ctrl.token;
    return ctrl;
  }

  Future<String> ssoGetToken(
    String username,
    String accessToken,
    String idToken,
  ) async {
    talker.debug('Requesting SSO login');
    final resp = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'username': username,
        'access_token': accessToken,
        'id_token': idToken,
      },
    );
    final json = _parseResponse(resp);
    if (json['token'] != null) {
      _token = json['token'] as String;
      return _token!;
    }
    throw ApiException(
      json['message'] ?? 'SSO login failed',
      statusCode: resp.statusCode,
    );
  }

  Future<Controller> ssoLoginToSite(
    String username,
    String accessToken,
    String idToken,
    String sitekey,
  ) async {
    talker.debug('Requesting site controller for SSO login');
    final resp = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'username': username,
        'access_token': accessToken,
        'id_token': idToken,
        'sitekey': sitekey,
      },
    );
    final json = _parseResponse(resp);
    if (json['token'] == null) {
      throw ApiException(
        json['message'] ?? 'SSO site login failed',
        statusCode: resp.statusCode,
      );
    }
    final ctrl = Controller.fromJson(json);
    _token = ctrl.token;
    return ctrl;
  }

  Future<List<Site>> getSiteList() async {
    talker.debug('Loading available sites');
    final resp = await http.get(
      Uri.parse('$baseUrl/site/list'),
      headers: _authHeader,
    );
    final json = _parseResponse(resp);
    final sites =
        (json['info'] as List?)
            ?.map((e) => Site.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return sites;
  }

  /// Refreshes an expired SSO session through the smartalock backend, which
  /// brokers the OIDC refresh against the identity provider. The provider's app
  /// is a confidential client (smartalock holds the secret), so a direct
  /// refresh from the device is rejected — refreshing must go through the
  /// backend. Mirrors the original app's `LoginClient.ssoRefresh`:
  /// `POST /oidc/token` with the refresh_token grant. `offline_access` must be
  /// re-requested so a rotated refresh_token comes back. Returns the fresh
  /// token response (access_token, id_token, and a rotated refresh_token).
  Future<Map<String, dynamic>> refreshSsoToken(
    String username,
    String refreshToken, {
    String redirectUri = 'https://api.smartalock.com/oidc/callback',
    String scope = 'openid email profile offline_access',
  }) async {
    talker.debug('Refreshing SSO session');
    final resp = await http.post(
      Uri.parse('$baseUrl/oidc/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'username': username,
        'refresh_token': refreshToken,
        'redirect_uri': redirectUri,
        'scope': scope,
      },
    );
    final json = _parseResponse(resp);
    if (resp.statusCode != 200 || json['access_token'] == null) {
      throw ApiException(
        json['message'] ?? 'OIDC refresh failed',
        statusCode: resp.statusCode,
      );
    }
    return json;
  }

  Future<Map<String, dynamic>> exchangeOidcToken(
    String username,
    String code,
    String codeVerifier,
    String redirectUri,
    String state,
  ) async {
    talker.debug('Exchanging OIDC authorization code');
    final resp = await http.post(
      Uri.parse('$baseUrl/oidc/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'username': username,
        'code': code,
        'code_verifier': codeVerifier,
        'redirect_uri': redirectUri,
        'state': state,
      },
    );
    return _parseResponse(resp);
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? body;

  const ApiException(this.message, {this.statusCode, this.body});

  @override
  String toString() {
    final parts = [message];
    if (statusCode != null) parts.add('(HTTP $statusCode)');
    if (body != null) parts.add('\n$body');
    return parts.join(' ');
  }
}
