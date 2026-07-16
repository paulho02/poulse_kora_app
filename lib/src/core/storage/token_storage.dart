import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the backend JWT access token (`fastapi-users` bearer token)
/// in the platform keychain/keystore.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'access_token';

  final FlutterSecureStorage _storage;

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _accessTokenKey, value: token);

  Future<void> clear() => _storage.delete(key: _accessTokenKey);
}
