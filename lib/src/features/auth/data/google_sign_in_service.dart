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
  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
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
  /// surface as one. Any other [GoogleSignInException] is rethrown.
  Future<String?> signIn() async {
    await ensureInitialized();
    try {
      final account = await _signIn.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
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
