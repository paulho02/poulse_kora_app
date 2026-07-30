import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/app_settings.dart' show sharedPreferencesProvider;
import 'app_config.dart';

/// Lets a self-hosted deployment point the app at its own backend instead of
/// the official server (`AppConfig.apiBaseUrl`), with no rebuild required.
///
/// Read synchronously off the `SharedPreferences` instance warmed in `main()`
/// — same reasoning as `AppSettingsStore` — so the very first
/// `dioClientProvider` build already has the right base URL instead of
/// starting against the official one and swapping mid-flight.
@immutable
class ServerConfig {
  const ServerConfig({this.customBaseUrl});

  /// `null` means "use the official server".
  final String? customBaseUrl;

  bool get isCustom => customBaseUrl != null;

  String get baseUrl => customBaseUrl ?? AppConfig.apiBaseUrl;
}

/// Normalizes to a bare origin (no trailing slash) so it concatenates cleanly
/// with `AppConfig.apiPath`.
String normalizeServerUrl(String raw) {
  final trimmed = raw.trim();
  return trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

/// A URL is acceptable if it's the kind of thing a `Dio` `baseUrl` can
/// actually be built from: an http(s) scheme and a host.
bool isValidServerUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  return uri.host.isNotEmpty;
}

class ServerConfigStore {
  ServerConfigStore(this._prefs);

  final SharedPreferences _prefs;

  static const _customBaseUrlKey = 'server.customBaseUrl';

  ServerConfig read() =>
      ServerConfig(customBaseUrl: _prefs.getString(_customBaseUrlKey));

  Future<void> write(String? customBaseUrl) async {
    if (customBaseUrl == null) {
      await _prefs.remove(_customBaseUrlKey);
    } else {
      await _prefs.setString(_customBaseUrlKey, customBaseUrl);
    }
  }
}

/// Only ever changed from the login/register screens (see
/// `ServerSettingsButton`): once signed in there's no route back to them
/// (`app_router.dart`'s auth redirect bounces away), so a mid-session server
/// switch — which would strand any token against the wrong backend — isn't a
/// case this needs to handle.
class ServerConfigNotifier extends Notifier<ServerConfig> {
  @override
  ServerConfig build() => ref.read(serverConfigStoreProvider).read();

  Future<void> useOfficialServer() => _apply(null);

  Future<void> useCustomServer(String url) => _apply(normalizeServerUrl(url));

  Future<void> _apply(String? customBaseUrl) async {
    await ref.read(serverConfigStoreProvider).write(customBaseUrl);
    state = ServerConfig(customBaseUrl: customBaseUrl);
  }
}

final serverConfigStoreProvider = Provider<ServerConfigStore>(
  (ref) => ServerConfigStore(ref.watch(sharedPreferencesProvider)),
);

final serverConfigProvider =
    NotifierProvider<ServerConfigNotifier, ServerConfig>(
      ServerConfigNotifier.new,
    );
