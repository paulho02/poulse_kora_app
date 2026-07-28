import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the backend JWT access token (`fastapi-users` bearer token)
/// in the platform keychain/keystore, and keeps it in memory once read.
///
/// The in-memory copy matters because the Dio interceptor attaches the token to
/// *every* outgoing request. Each keystore read crosses into native platform code
/// and decrypts, so without caching a single screen load pays that cost several
/// times over — for a value that cannot change between login and logout.
///
/// This doesn't meaningfully widen the token's exposure: it is already held in
/// memory the moment it's written into a request header.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'access_token';

  final FlutterSecureStorage _storage;

  /// Only meaningful once [_loaded] is true. `null` is a real value here — it
  /// means signed out — so it can't double as "not read yet".
  String? _cached;
  bool _loaded = false;

  /// Dedupes concurrent first reads. On a cold start the feed, channels and
  /// economy requests all fire at once; without this each would open the
  /// keystore before any of them had finished filling the cache.
  Future<String?>? _pendingRead;

  Future<String?> readAccessToken() {
    if (_loaded) return Future.value(_cached);
    return _pendingRead ??= _readAndCache();
  }

  Future<String?> _readAndCache() async {
    try {
      _cached = await _storage.read(key: _accessTokenKey);
      _loaded = true;
      return _cached;
    } finally {
      // Cleared on failure too, so a read that threw (locked keystore, user
      // cancelled biometrics) is retried rather than cached as "no token".
      _pendingRead = null;
    }
  }

  Future<void> saveAccessToken(String token) async {
    await _storage.write(key: _accessTokenKey, value: token);
    _cached = token;
    _loaded = true;
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    _cached = null;
    // Still "loaded" — we know there is no token, so don't go ask the keystore.
    _loaded = true;
  }
}
