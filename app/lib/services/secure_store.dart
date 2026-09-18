import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper over [FlutterSecureStorage] for the credentials we must keep on
/// device to silently refresh an expired session (the account password for
/// password logins, the OIDC refresh token for SSO logins). These live in the
/// OS keystore (Android Keystore / iOS Keychain) rather than plain
/// SharedPreferences.
class SecureStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _password = 'floorsense.cred.password';
  static const _ssoRefreshToken = 'floorsense.cred.sso_refresh_token';

  static Future<void> writePassword(String? value) => _write(_password, value);
  static Future<String?> readPassword() => _storage.read(key: _password);

  static Future<void> writeSsoRefreshToken(String? value) =>
      _write(_ssoRefreshToken, value);
  static Future<String?> readSsoRefreshToken() =>
      _storage.read(key: _ssoRefreshToken);

  /// Wipes every stored credential (called on logout).
  static Future<void> clear() async {
    await _storage.delete(key: _password);
    await _storage.delete(key: _ssoRefreshToken);
  }

  static Future<void> _write(String key, String? value) => value == null
      ? _storage.delete(key: key)
      : _storage.write(key: key, value: value);
}
