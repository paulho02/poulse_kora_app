import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poulse_kora_app/src/core/storage/token_storage.dart';

/// Counts keystore hits. Reads are delayed a tick so the concurrency test
/// exercises the real overlap a cold start produces.
class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage([this.value]);

  String? value;
  int reads = 0;
  int writes = 0;
  int deletes = 0;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return value;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writes++;
    this.value = value;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deletes++;
    value = null;
  }
}

/// Always throws — stands in for a locked keystore or a cancelled biometric prompt.
class _FailingSecureStorage extends _FakeSecureStorage {
  bool shouldFail = true;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads++;
    if (shouldFail) throw StateError('keystore unavailable');
    return value;
  }
}

void main() {
  test('hits the keystore once, then serves from memory', () async {
    final storage = _FakeSecureStorage('jwt-abc');
    final tokens = TokenStorage(storage: storage);

    expect(await tokens.readAccessToken(), 'jwt-abc');
    expect(await tokens.readAccessToken(), 'jwt-abc');
    expect(await tokens.readAccessToken(), 'jwt-abc');

    expect(
      storage.reads,
      1,
      reason: 'the interceptor reads this on every request',
    );
  });

  test('caches "no token" too, instead of re-asking', () async {
    // `null` is a real value (signed out) and must not be mistaken for
    // "not loaded yet", or every request while logged out reopens the keystore.
    final storage = _FakeSecureStorage();
    final tokens = TokenStorage(storage: storage);

    expect(await tokens.readAccessToken(), isNull);
    expect(await tokens.readAccessToken(), isNull);

    expect(storage.reads, 1);
  });

  test('concurrent cold reads collapse into one keystore hit', () async {
    // A cold start fires feed + channels + economy near-simultaneously, before
    // any of them has filled the cache.
    final storage = _FakeSecureStorage('jwt-abc');
    final tokens = TokenStorage(storage: storage);

    final results = await Future.wait([
      tokens.readAccessToken(),
      tokens.readAccessToken(),
      tokens.readAccessToken(),
    ]);

    expect(results, ['jwt-abc', 'jwt-abc', 'jwt-abc']);
    expect(storage.reads, 1);
  });

  test('saving primes the cache without a read back', () async {
    final storage = _FakeSecureStorage();
    final tokens = TokenStorage(storage: storage);

    await tokens.saveAccessToken('fresh-jwt');

    expect(await tokens.readAccessToken(), 'fresh-jwt');
    expect(storage.writes, 1);
    expect(storage.reads, 0, reason: 'we just wrote it; nothing to go ask');
  });

  test('clearing drops the cached token', () async {
    final storage = _FakeSecureStorage('jwt-abc');
    final tokens = TokenStorage(storage: storage);
    expect(await tokens.readAccessToken(), 'jwt-abc');

    await tokens.clear();

    expect(
      await tokens.readAccessToken(),
      isNull,
      reason: 'a stale cached token would keep signing requests after logout',
    );
    expect(storage.deletes, 1);
    expect(
      storage.reads,
      1,
      reason: 'clear() already knows the answer is null',
    );
  });

  test('a failed read is retried, not cached as "no token"', () async {
    final storage = _FailingSecureStorage()..value = 'jwt-abc';
    final tokens = TokenStorage(storage: storage);

    await expectLater(tokens.readAccessToken(), throwsStateError);

    storage.shouldFail = false;
    expect(
      await tokens.readAccessToken(),
      'jwt-abc',
      reason: 'caching the failure would silently sign the user out',
    );
  });
}
