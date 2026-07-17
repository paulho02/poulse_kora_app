import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
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
      return true;
    });
  }

  Future<void> logout() async {
    await ref.read(tokenStorageProvider).clear();
    state = const AsyncData(false);
  }
}

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, bool>(
  AuthNotifier.new,
);
