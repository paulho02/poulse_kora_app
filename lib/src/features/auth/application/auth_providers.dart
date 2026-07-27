import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/settings/app_settings.dart';
import '../data/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dioClientProvider).dio);
});

/// Holds whether the user is authenticated (a token is present). No refresh
/// token flow exists, so this only checks token *presence*, never validity.
class AuthNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final token = await ref.watch(tokenStorageProvider).readAccessToken();
    return token != null;
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final token = await ref
          .read(authRepositoryProvider)
          .login(email: email, password: password);
      await ref.read(tokenStorageProvider).saveAccessToken(token);
      await _startCleanSession();
      return true;
    });
  }

  Future<void> register({
    required String email,
    required String password,
    required String username,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(authRepositoryProvider)
          .register(email: email, password: password, username: username);
      final token = await ref
          .read(authRepositoryProvider)
          .login(email: email, password: password);
      await ref.read(tokenStorageProvider).saveAccessToken(token);
      await _startCleanSession();
      return true;
    });
  }

  /// Wipe anything the previous session left behind. Signing in is the one moment
  /// we know a different account may be taking over the device, and unlike logout
  /// it always runs — a session that ended by token expiry or by the app being
  /// killed never got to clean up after itself.
  Future<void> _startCleanSession() async {
    await ref.read(jsonCacheProvider).clearAll();
    await ref.read(appSettingsProvider.notifier).reset();
  }

  /// Clears everything account-scoped, not just the token: cached API responses
  /// and local settings would otherwise carry over and show the previous user's
  /// feed and theme to whoever signs in next on this device.
  Future<void> logout() async {
    await ref.read(tokenStorageProvider).clear();
    await ref.read(jsonCacheProvider).clearAll();
    await ref.read(appSettingsProvider.notifier).reset();
    state = const AsyncData(false);
  }
}

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, bool>(
  AuthNotifier.new,
);
