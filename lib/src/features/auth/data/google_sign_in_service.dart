import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_config.dart';

/// Thin wrapper over `GoogleSignIn.instance`, hiding two platform differences the
/// rest of the app should not have to care about.
///
/// 1. **How the client ID is passed.** Android wants it as `serverClientId` (that
///    is what audiences the ID token to our backend's client, which is what
///    `GOOGLE_CLIENT_IDS` accepts); the web plugin asserts `serverClientId` is
///    null and wants `clientId` instead.
/// 2. **How sign-in is started.** On Android we call [signIn] directly. On web
///    `supportsAuthenticate()` is false and `authenticate()` throws - Google
///    requires its own rendered button - so the flow starts from that widget and
///    the result arrives asynchronously on [idTokens]. See
///    `presentation/google_sign_in_button.dart`.
///
/// Only the ID token ever leaves this class: it is the one thing the backend can
/// verify, and the plugin's own docs are explicit that the account's `id`/`email`
/// must not be used to tell a server who signed in.
class GoogleSignInService {
  GoogleSignInService({GoogleSignIn? signIn})
    : _signIn = signIn ?? GoogleSignIn.instance;

  final GoogleSignIn _signIn;

  Future<void>? _initialization;

  /// Whether a client ID was baked into this build at all. The button is hidden
  /// unless this *and* the backend's `google_oauth_enabled` flag are true.
  bool get isConfigured => AppConfig.googleServerClientId.isNotEmpty;

  /// False on web, where sign-in must be started from Google's rendered button
  /// rather than from [signIn].
  bool get supportsDirectSignIn => _signIn.supportsAuthenticate();

  /// Idempotent: the plugin must be initialized exactly once, but both auth
  /// screens and the settings row can each be the first to need it.
  ///
  /// A *failed* initialization is deliberately not remembered. `initialize()`
  /// reaches into Play services, which is exactly what is unreliable in the
  /// minutes after an install, and memoizing the rejected future would leave
  /// Google sign-in broken for the whole process lifetime — every later caller
  /// would await the same stored failure without the plugin ever being asked
  /// again. Only a success is worth keeping.
  Future<void> ensureInitialized() async {
    final pending = _initialization;
    if (pending != null) return pending;
    final attempt = _initialize();
    _initialization = attempt;
    try {
      await attempt;
    } catch (_) {
      // Guard on identity: a concurrent caller may already have started a
      // fresh attempt, and clearing unconditionally would discard that one.
      if (identical(_initialization, attempt)) _initialization = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    final clientId = AppConfig.googleServerClientId;
    await _signIn.initialize(
      clientId: kIsWeb ? clientId : null,
      serverClientId: kIsWeb ? null : clientId,
    );
  }

  /// ID tokens from sign-ins this app did not start itself - i.e. the web
  /// button's.
  ///
  /// A fresh view over `authenticationEvents` on each access rather than a
  /// cached controller: that source is already broadcast, so every listener gets
  /// its own subscription, and there is no shared state to double-subscribe. An
  /// earlier version piped into a `StreamController` on every access, which made
  /// one web sign-in fire once per screen that had ever asked for this.
  ///
  /// Carries only real sign-in events: this service never calls
  /// `attemptLightweightAuthentication()`, so arriving at the login screen can
  /// never silently sign someone in via One Tap without them pressing anything.
  Stream<String> get idTokens => _signIn.authenticationEvents
      .where((event) => event is GoogleSignInAuthenticationEventSignIn)
      .cast<GoogleSignInAuthenticationEventSignIn>()
      .map((event) => event.user.authentication.idToken)
      .where((token) => token != null)
      .cast<String>();

  /// Runs the native sign-in flow and returns the ID token.
  ///
  /// Returns null when the user backs out, which is not an error and must not
  /// surface as one. Transient platform failures are retried (see
  /// [isTransientGoogleSignInError]); anything else is rethrown.
  Future<String?> signIn() {
    return retryTransientGoogleSignIn(() async {
      // Inside the retried body on purpose: initialization is the first thing
      // that touches Play services, so it fails for the same reasons and
      // deserves the same second chance. `ensureInitialized` no longer caches
      // a failure, so this really does re-run it.
      await ensureInitialized();
      try {
        final account = await _signIn.authenticate();
        return account.authentication.idToken;
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled) return null;
        rethrow;
      }
    });
  }

  /// Clears Google's own session.
  ///
  /// Called on logout: without it Google keeps the previous account selected and
  /// the next "Continue with Google" signs the same person straight back in with
  /// no account picker - which looks like the app ignoring the logout.
  Future<void> signOut() async {
    if (!isConfigured) return;
    await ensureInitialized();
    await _signIn.signOut();
  }
}

/// Whether [code] describes a platform hiccup rather than a verdict.
///
/// The two retryable codes are the ones that carry no information about the
/// request itself:
///
/// - [GoogleSignInExceptionCode.interrupted] is the plugin's rendering of
///   Credential Manager's `GetCredentialInterruptedException`, which Android
///   documents as a transient error the caller is expected to retry;
/// - [GoogleSignInExceptionCode.unknownError] is the catch-all the Android
///   implementation falls back to for every `GetCredentialException` it has no
///   specific case for, which includes Play services failing internally — an
///   `ActivityManager: ... com.google.android.gms sent binder code 1 ... got
///   error -32` in logcat is one of these reaching us.
///
/// Everything else is a decision, not a hiccup: `canceled` is the user saying
/// no, and the configuration/UI codes describe a build or a moment that will
/// fail again just as fast. Retrying those would only delay the error.
///
/// The enum is documented as open — new values are not a breaking change — so
/// this is an allow-list, and an unrecognised code is treated as permanent.
bool isTransientGoogleSignInError(GoogleSignInExceptionCode code) {
  return code == GoogleSignInExceptionCode.interrupted ||
      code == GoogleSignInExceptionCode.unknownError;
}

/// Runs [attempt] until it succeeds, fails permanently, or runs out of tries.
///
/// Exists because Google's own credential state for an app is rebuilt from
/// scratch on install, and the first sign-ins afterwards fail for reasons that
/// have nothing to do with the request — the same tap works seconds later. That
/// was previously left to the user to discover by pressing the button again
/// until it took; this does the pressing.
///
/// Only [GoogleSignInException]s are considered, and only the transient ones:
/// see [isTransientGoogleSignInError]. The backoff is short because the whole
/// budget is spent with the user watching a spinner, and bounded because a
/// failure that survives it is worth showing.
Future<T> retryTransientGoogleSignIn<T>(
  Future<T> Function() attempt, {
  int maxAttempts = 3,
  Duration backoff = const Duration(milliseconds: 300),
}) async {
  for (var tries = 1; ; tries++) {
    try {
      return await attempt();
    } on GoogleSignInException catch (e) {
      if (tries >= maxAttempts || !isTransientGoogleSignInError(e.code)) {
        rethrow;
      }
      await Future<void>.delayed(backoff * tries);
    }
  }
}
