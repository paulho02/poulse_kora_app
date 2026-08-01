import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Central place for build-time / environment configuration.
class AppConfig {
  AppConfig._();

  static const String apiPath = '/api/v1';

  /// Override at build/run time with:
  ///   flutter run --dart-define=API_BASE_URL=https://api.example.com
  static const String _envApiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Base URL of the Poulse Kora backend (no trailing slash, no [apiPath]).
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

  /// Toggle the persistent "beta version" strip on/off. Override in
  /// `env.json` with `"BETA_DISCLAIMER_ENABLED": false` to switch it off,
  /// e.g. once the app leaves beta.
  static const bool betaDisclaimerEnabled = bool.fromEnvironment(
    'BETA_DISCLAIMER_ENABLED',
    defaultValue: true,
  );
}
