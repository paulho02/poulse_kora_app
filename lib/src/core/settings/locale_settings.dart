import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart' show sharedPreferencesProvider;

/// The locales this app ships copy for. Keep in sync with `lib/l10n/*.arb`
/// and the backend's `Settings.SUPPORTED_LOCALES` (see
/// `backend/app/core/config.py`) — adding a locale means adding it here, an
/// ARB file, and the backend setting.
const supportedAppLocales = [Locale('en'), Locale('de')];

/// Resolves device locale vs. a manual override in one place, so
/// [activeLocaleProvider]'s consumers (`MaterialApp` and the Dio interceptor
/// in `core/network/dio_client.dart`) can never disagree on which locale is
/// "active".
Locale resolveActiveLocale({
  required String? override,
  required Iterable<Locale> deviceLocales,
}) {
  if (override != null) return Locale(override);
  for (final device in deviceLocales) {
    for (final supported in supportedAppLocales) {
      if (supported.languageCode == device.languageCode) return supported;
    }
  }
  return const Locale('en');
}

/// Persists the manual language override in `SharedPreferences`. Deliberately
/// separate from `AppSettingsStore`/`AppSettings`: unlike `dark_mode`, this
/// preference has no server counterpart to sync, and — unlike dark mode — it
/// is NOT cleared on logout (see `AppSettingsNotifier.reset`), since language
/// is a device preference, not a per-account one.
class LocaleSettingsStore {
  LocaleSettingsStore(this._prefs);
  final SharedPreferences _prefs;

  static const _key = 'settings.localeOverride';

  /// null = follow the device locale.
  String? read() => _prefs.getString(_key);

  Future<void> write(String? code) async {
    if (code == null) {
      await _prefs.remove(_key);
    } else {
      await _prefs.setString(_key, code);
    }
  }
}

class LocaleOverrideNotifier extends Notifier<String?> {
  @override
  String? build() => ref.read(localeSettingsStoreProvider).read();

  Future<void> setOverride(String? code) async {
    state = code;
    await ref.read(localeSettingsStoreProvider).write(code);
  }
}

final localeSettingsStoreProvider = Provider<LocaleSettingsStore>(
  (ref) => LocaleSettingsStore(ref.watch(sharedPreferencesProvider)),
);

final localeOverrideProvider =
    NotifierProvider<LocaleOverrideNotifier, String?>(
      LocaleOverrideNotifier.new,
    );

/// The render source of truth for the active locale — watched by the app root
/// for `MaterialApp.router(locale: ...)` and read by `DioClient`'s
/// interceptor for the `Accept-Language` header.
final activeLocaleProvider = Provider<Locale>((ref) {
  final override = ref.watch(localeOverrideProvider);
  return resolveActiveLocale(
    override: override,
    deviceLocales: WidgetsBinding.instance.platformDispatcher.locales,
  );
});
