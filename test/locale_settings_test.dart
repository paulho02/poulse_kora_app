import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poulse_kora_app/src/core/settings/app_settings.dart';
import 'package:poulse_kora_app/src/core/settings/locale_settings.dart';

void main() {
  group('resolveActiveLocale', () {
    test('an explicit override always wins, regardless of device locales', () {
      final locale = resolveActiveLocale(
        override: 'de',
        deviceLocales: const [Locale('en')],
      );
      expect(locale, const Locale('de'));
    });

    test('falls back to the first supported device locale', () {
      final locale = resolveActiveLocale(
        override: null,
        deviceLocales: const [Locale('fr'), Locale('de'), Locale('en')],
      );
      expect(locale, const Locale('de'));
    });

    test('ignores the region subtag and matches on language only', () {
      final locale = resolveActiveLocale(
        override: null,
        deviceLocales: const [Locale('de', 'AT')],
      );
      expect(locale, const Locale('de'));
    });

    test('defaults to English when nothing supported is available', () {
      final locale = resolveActiveLocale(
        override: null,
        deviceLocales: const [Locale('fr'), Locale('ja')],
      );
      expect(locale, const Locale('en'));
    });
  });

  group('LocaleSettingsStore / localeOverrideProvider', () {
    late ProviderContainer container;

    Future<void> setUpContainer([Map<String, Object> initial = const {}]) async {
      SharedPreferences.setMockInitialValues(initial);
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
    }

    test('defaults to null (follow device locale) with nothing persisted', () async {
      await setUpContainer();
      expect(container.read(localeOverrideProvider), isNull);
    });

    test('reads a persisted override synchronously on build', () async {
      await setUpContainer({'settings.localeOverride': 'de'});
      expect(container.read(localeOverrideProvider), 'de');
    });

    test('setOverride persists the choice and updates state', () async {
      await setUpContainer();
      await container
          .read(localeOverrideProvider.notifier)
          .setOverride('de');

      expect(container.read(localeOverrideProvider), 'de');

      final store = container.read(localeSettingsStoreProvider);
      expect(store.read(), 'de');
    });

    test('setOverride(null) clears the persisted choice', () async {
      await setUpContainer({'settings.localeOverride': 'de'});
      await container.read(localeOverrideProvider.notifier).setOverride(null);

      expect(container.read(localeOverrideProvider), isNull);
      expect(container.read(localeSettingsStoreProvider).read(), isNull);
    });
  });
}
