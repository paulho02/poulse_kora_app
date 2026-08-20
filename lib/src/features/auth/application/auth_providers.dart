import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/settings/app_settings.dart';
import '../data/auth_repository.dart';
import '../data/google_sign_in_service.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dioClientProvider).dio);
});

/// Single instance: `GoogleSignIn.instance` is itself a singleton that must be
/// initialized exactly once, and the service memoizes that.
final googleSignInServiceProvider = Provider<GoogleSignInService>((ref) {
  return GoogleSignInService();
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

  /// Adopt an access token obtained out-of-band, by the Google flow.
  ///
  /// Takes the finished token rather than running the exchange itself, unlike
  /// [login]: that exchange can answer 409 `google_link_required`, which is a
  /// prompt ("this address already has a password account - upgrade it?") and
  /// not a failure. Routed through here it would land in `state.error` and every
  /// screen listening for errors would flash a snackbar for it. So
  /// `GoogleAuthSection` owns the exchange and the confirmation, and hands the
  /// result here once there is genuinely a session to start.
  Future<void> completeGoogleSignIn(String accessToken) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(tokenStorageProvider).saveAccessToken(accessToken);
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
    // Google keeps its own session, independent of our token. Left alone, the
    // next "Continue with Google" silently signs the same account back in with
    // no picker, which reads as the logout not having worked. Best-effort: a
    // failure here must not block clearing our own session.
    try {
      await ref.read(googleSignInServiceProvider).signOut();
    } catch (_) {
      // Nothing actionable — our own sign-out below is what matters.
    }
    await ref.read(tokenStorageProvider).clear();
    await ref.read(jsonCacheProvider).clearAll();
    await ref.read(appSettingsProvider.notifier).reset();
    state = const AsyncData(false);
  }
}

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, bool>(
  AuthNotifier.new,
);

/// Whether `authNotifierProvider` has resolved at least once — cold-start
/// token read done, either way.
///
/// Distinct from `authNotifierProvider.isLoading`: that flag is *also* true
/// during `login`/`register`, which sets `state = AsyncLoading()` again while
/// a request is in flight. `PoulseKoraApp` used to gate its splash screen on
/// `isLoading` directly, which meant it swapped `MaterialApp.router` out for
/// a bare splash `MaterialApp` on *every* login/register attempt, not just
/// cold start — tearing down the whole route tree (and whatever screen the
/// user was mid-interaction with) each time. This flips to `true` once and
/// never back, so it only ever gates the genuine first resolution.
class AuthReadyNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(authNotifierProvider, (previous, next) {
      if (!next.isLoading) state = true;
    });
    return !ref.read(authNotifierProvider).isLoading;
  }
}

final authReadyProvider = NotifierProvider<AuthReadyNotifier, bool>(
  AuthReadyNotifier.new,
);
