import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Central place for build-time / environment configuration.
class AppConfig {
  AppConfig._();

  static const String apiPath = '/api/v1';

  /// Override at build/run time with:
  ///   flutter run --dart-define=API_BASE_URL=https://api.example.com
  static const String _envApiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Base URL of the Peerkola backend (no trailing slash, no [apiPath]).
  ///
  /// Defaults to the backend's docker-compose dev setup. Android emulators
  /// can't reach the host via `localhost`, hence the `10.0.2.2` alias.
  static String get apiBaseUrl {
    if (_envApiBaseUrl.isNotEmpty) {
      // A scheme-less value (e.g. a Railway variable reference resolved
      // without its "https://" prefix surviving) would otherwise be treated
      // as a relative path and silently resolve against the app's own
      // origin instead of the backend — fail loudly rather than let that
      // happen quietly.
      final hasScheme =
          _envApiBaseUrl.startsWith('http://') ||
          _envApiBaseUrl.startsWith('https://');
      if (!hasScheme) {
        throw StateError(
          'API_BASE_URL must include a scheme (http:// or https://), '
          'got: "$_envApiBaseUrl"',
        );
      }
      return _envApiBaseUrl;
    }
    if (kIsWeb) return 'http://localhost:8000';
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }

  /// Google OAuth *web* client ID, used for Google sign-in.
  ///
  /// One value covers both platforms, but it is passed under different names:
  /// on Android as google_sign_in's `serverClientId` (which is what makes the
  /// resulting ID token audienced to this client, so the backend accepts it),
  /// and on web as `clientId` (the web plugin asserts `serverClientId == null`).
  /// See `features/auth/data/google_sign_in_service.dart`.
  ///
  /// Empty means "not configured", and the Google button is hidden - the
  /// backend's own `google_oauth_enabled` flag has to agree as well.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  /// Toggle the persistent "beta version" strip on/off. Override in
  /// `env.json` with `"BETA_DISCLAIMER_ENABLED": false` to switch it off,
  /// e.g. once the app leaves beta.
  static const bool betaDisclaimerEnabled = bool.fromEnvironment(
    'BETA_DISCLAIMER_ENABLED',
    defaultValue: true,
  );

  /// Whether the app offers pointing itself at a self-hosted backend
  /// (`core/config/server_config.dart`, `ServerSettingsButton`).
  ///
  /// Off by default: for the MVP there is only the official server, and a
  /// "which server?" choice on the login screen is a question nobody outside
  /// a self-hosting deployment can answer. Turn it on with
  /// `"CUSTOM_SERVER_ENABLED": true` in `env.json` once self-hosting is a
  /// case worth supporting.
  ///
  /// Kept a `const` (not a runtime lookup) so the sheet, the persisted
  /// override and everything behind them are dead-code-eliminated from a
  /// build that has this off — same reasoning as the `kIsWeb` guards beside
  /// it.
  static const bool customServerEnabled = bool.fromEnvironment(
    'CUSTOM_SERVER_ENABLED',
  );
}
