import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poulse_kora_app/src/core/settings/app_settings.dart';

/// Covers the push-vs-pull decision described in
/// `AppSettingsNotifier` / `ProfileNotifier._reconcileSettings`.
void main() {
  late ProviderContainer container;

  Future<void> setUpContainer([Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
  }

  group('AppSettings', () {
    test('defaults to light, clean, revision 0', () async {
      await setUpContainer();
      final settings = container.read(appSettingsProvider);
      expect(settings.darkMode, isFalse);
      expect(settings.dirty, isFalse);
      expect(settings.syncedRevision, 0);
      expect(settings.themeMode, ThemeMode.light);
    });

    test('reads a persisted preference synchronously on build', () async {
      // This is what lets the first frame paint in the right theme with no
      // network and no async gap.
      await setUpContainer({
        'settings.darkMode': true,
        'settings.dirty': false,
        'settings.syncedRevision': 3,
      });
      final settings = container.read(appSettingsProvider);
      expect(settings.darkMode, isTrue);
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.syncedRevision, 3);
    });

    test(
      'a local change applies immediately and marks the value dirty',
      () async {
        await setUpContainer();
        await container.read(appSettingsProvider.notifier).setDarkMode(true);

        final settings = container.read(appSettingsProvider);
        expect(
          settings.darkMode,
          isTrue,
          reason: 'must not wait on the network',
        );
        expect(settings.dirty, isTrue, reason: 'needs pushing on reconnect');
      },
    );

    test('a local change survives a restart while still pending', () async {
      await setUpContainer();
      await container.read(appSettingsProvider.notifier).setDarkMode(true);
      container.dispose();

      // Same prefs, fresh container — as if the app were killed while offline.
      final prefs = await SharedPreferences.getInstance();
      final restarted = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(restarted.dispose);

      final settings = restarted.read(appSettingsProvider);
      expect(settings.darkMode, isTrue);
      expect(settings.dirty, isTrue);
    });

    test('setting the same value again is a no-op', () async {
      await setUpContainer({
        'settings.darkMode': true,
        'settings.dirty': false,
        'settings.syncedRevision': 2,
      });
      await container.read(appSettingsProvider.notifier).setDarkMode(true);
      expect(
        container.read(appSettingsProvider).dirty,
        isFalse,
        reason: 'nothing changed, so there is nothing to push',
      );
    });

    test('a pull adopts the server value and clears dirty', () async {
      await setUpContainer();
      final notifier = container.read(appSettingsProvider.notifier);
      await notifier.setDarkMode(true);

      await notifier.adoptFromServer(darkMode: false, revision: 7);

      final settings = container.read(appSettingsProvider);
      expect(settings.darkMode, isFalse);
      expect(settings.dirty, isFalse);
      expect(settings.syncedRevision, 7);
    });

    test('a successful push clears dirty and advances the revision', () async {
      await setUpContainer();
      final notifier = container.read(appSettingsProvider.notifier);
      await notifier.setDarkMode(true);

      await notifier.markPushed(4);

      final settings = container.read(appSettingsProvider);
      expect(settings.darkMode, isTrue, reason: 'the local value is what won');
      expect(settings.dirty, isFalse);
      expect(settings.syncedRevision, 4);
    });

    test('reset wipes preferences so the next account starts clean', () async {
      await setUpContainer();
      final notifier = container.read(appSettingsProvider.notifier);
      await notifier.setDarkMode(true);
      await notifier.markPushed(9);

      await notifier.reset();

      final settings = container.read(appSettingsProvider);
      expect(settings.darkMode, isFalse);
      expect(settings.syncedRevision, 0);
    });
  });

  group('decideSettingsSync', () {
    test('clean local state pulls, even when it disagrees with the server', () {
      // No local edit to protect, so the server is authoritative — this is how a
      // change made on another device reaches this one.
      expect(
        decideSettingsSync(
          local: const AppSettings(darkMode: false, syncedRevision: 1),
          serverDarkMode: true,
          serverRevision: 5,
        ),
        SettingsSyncAction.pull,
      );
    });

    test(
      'dirty local state that already matches the server needs no request',
      () {
        expect(
          decideSettingsSync(
            local: const AppSettings(
              darkMode: true,
              dirty: true,
              syncedRevision: 5,
            ),
            serverDarkMode: true,
            serverRevision: 5,
          ),
          SettingsSyncAction.alreadyInSync,
        );
      },
    );

    test('dirty local state with matching revisions pushes', () {
      expect(
        decideSettingsSync(
          local: const AppSettings(
            darkMode: true,
            dirty: true,
            syncedRevision: 5,
          ),
          serverDarkMode: false,
          serverRevision: 5,
        ),
        SettingsSyncAction.push,
      );
    });

    test(
      'dirty local state still pushes when the server is ahead (local wins)',
      () {
        // Another device changed the setting while this one was offline. Reverting
        // the toggle the user just flipped here would be the more surprising
        // outcome, so the local value wins rather than the newer one.
        expect(
          decideSettingsSync(
            local: const AppSettings(
              darkMode: true,
              dirty: true,
              syncedRevision: 5,
            ),
            serverDarkMode: false,
            serverRevision: 9,
          ),
          SettingsSyncAction.push,
        );
      },
    );
  });
}
