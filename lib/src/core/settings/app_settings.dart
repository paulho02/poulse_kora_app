import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local user preferences, plus the bookkeeping needed to reconcile them
/// with the server after being offline.
///
/// This — not the server profile — is what the UI renders from. Deriving the
/// theme from a network call means the app can't honour a preference it already
/// knows while offline, which is the bug this type exists to fix.
@immutable
class AppSettings {
  const AppSettings({
    this.darkMode = false,
    this.dirty = false,
    this.syncedRevision = 0,
  });

  final bool darkMode;

  /// Set on every local change, cleared only after a successful push.
  ///
  /// This is the field that answers "push or pull?" on reconnect. Asking
  /// "which value is newer?" first would need trustworthy clocks on both sides;
  /// asking "did *I* change this since my last sync?" needs neither.
  final bool dirty;

  /// The `settings_revision` this local copy was last reconciled against.
  /// Compared with the server's to detect a change made on another device.
  final int syncedRevision;

  AppSettings copyWith({bool? darkMode, bool? dirty, int? syncedRevision}) =>
      AppSettings(
        darkMode: darkMode ?? this.darkMode,
        dirty: dirty ?? this.dirty,
        syncedRevision: syncedRevision ?? this.syncedRevision,
      );

  ThemeMode get themeMode => darkMode ? ThemeMode.dark : ThemeMode.light;
}

/// What to do with local settings when we reach the server.
enum SettingsSyncAction {
  /// Take the server's values; the local copy has no unsent changes.
  pull,

  /// Send the local values; they contain a change the server hasn't seen.
  push,

  /// Both sides already agree — only the bookkeeping needs updating.
  alreadyInSync,
}

/// Decide push vs pull for a set of local settings against the server's.
///
/// The question deliberately asked first is "did *this device* change something
/// since its last successful sync?" — a local dirty flag — and not "which value
/// is newer?". The latter would require the device and server clocks to agree,
/// which nothing guarantees.
///
/// [serverRevision] only matters for the conflict case: it detects that another
/// device also changed the setting while this one was offline. The resolution is
/// still local-wins, because reverting a toggle the user just flipped on the
/// device in their hand is the more surprising failure for a single-user
/// preference. Kept as a parameter so the conflict remains visible and easy to
/// give a different policy (or a prompt) later.
SettingsSyncAction decideSettingsSync({
  required AppSettings local,
  required bool serverDarkMode,
  required int serverRevision,
}) {
  if (!local.dirty) return SettingsSyncAction.pull;
  if (local.darkMode == serverDarkMode) return SettingsSyncAction.alreadyInSync;
  return SettingsSyncAction.push;
}

/// Persists [AppSettings] in `SharedPreferences`.
///
/// Reads are synchronous (the prefs instance is warmed in `main()`), which is
/// what lets the very first frame paint in the right theme with no flash.
class AppSettingsStore {
  AppSettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _darkMode = 'settings.darkMode';
  static const _dirty = 'settings.dirty';
  static const _syncedRevision = 'settings.syncedRevision';

  AppSettings read() => AppSettings(
        darkMode: _prefs.getBool(_darkMode) ?? false,
        dirty: _prefs.getBool(_dirty) ?? false,
        syncedRevision: _prefs.getInt(_syncedRevision) ?? 0,
      );

  Future<void> write(AppSettings settings) async {
    await _prefs.setBool(_darkMode, settings.darkMode);
    await _prefs.setBool(_dirty, settings.dirty);
    await _prefs.setInt(_syncedRevision, settings.syncedRevision);
  }

  Future<void> clear() async {
    await _prefs.remove(_darkMode);
    await _prefs.remove(_dirty);
    await _prefs.remove(_syncedRevision);
  }
}

/// The render source of truth for preferences. Never touches the network —
/// syncing is layered on top in `features/profile/application/settings_sync.dart`.
class AppSettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(appSettingsStoreProvider).read();

  /// Applies a local change immediately and marks it as needing a push.
  /// The UI updates on this call alone — a failed or absent network round-trip
  /// does not roll it back.
  Future<void> setDarkMode(bool value) async {
    if (state.darkMode == value) return;
    await _persist(state.copyWith(darkMode: value, dirty: true));
  }

  /// Adopt the server's values (a pull). Clears the dirty flag: after this the
  /// local copy *is* the server copy.
  Future<void> adoptFromServer({
    required bool darkMode,
    required int revision,
  }) async {
    await _persist(AppSettings(
      darkMode: darkMode,
      dirty: false,
      syncedRevision: revision,
    ));
  }

  /// Record that our local values reached the server at [revision] (a push).
  Future<void> markPushed(int revision) async {
    await _persist(state.copyWith(dirty: false, syncedRevision: revision));
  }

  /// Wipe on logout so the next account starts from its own server state
  /// rather than inheriting this one's theme.
  Future<void> reset() async {
    await ref.read(appSettingsStoreProvider).clear();
    state = const AppSettings();
  }

  Future<void> _persist(AppSettings next) async {
    state = next;
    await ref.read(appSettingsStoreProvider).write(next);
  }
}

/// Overridden in `main()` with the warmed `SharedPreferences` instance.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden in main()');
});

final appSettingsStoreProvider = Provider<AppSettingsStore>(
  (ref) => AppSettingsStore(ref.watch(sharedPreferencesProvider)),
);

final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);
