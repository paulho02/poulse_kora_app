import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:poulse_kora_app/src/core/settings/app_settings.dart';
import 'package:poulse_kora_app/src/core/tips/application/tip_providers.dart';

/// Covers the generalized, multi-key version of the "dismiss forever" pattern
/// already tested in `announcement_dismissal_test.dart` — same lifetime rules,
/// but for an arbitrary set of per-view tip keys rather than a single id.
void main() {
  late ProviderContainer container;

  Future<ProviderContainer> makeContainer({
    Map<String, Object> initialPrefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('starts empty with nothing persisted', () async {
    container = await makeContainer();
    expect(container.read(tipDismissalProvider), isEmpty);
  });

  test('a forever-dismissal survives a restart', () async {
    container = await makeContainer();
    await container
        .read(tipDismissalProvider.notifier)
        .dismissForever('tip.feed');
    container.dispose();

    // Same underlying prefs, fresh container — as if the app were relaunched.
    final prefs = await SharedPreferences.getInstance();
    final restarted = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(restarted.dispose);

    expect(restarted.read(tipDismissalProvider), {'tip.feed'});
  });

  test('dismissing one key does not affect another', () async {
    container = await makeContainer(
      initialPrefs: {
        'tips.dismissedForever': ['tip.feed'],
      },
    );
    await container
        .read(tipDismissalProvider.notifier)
        .dismissForever('tip.channels');

    final state = container.read(tipDismissalProvider);
    expect(state, {'tip.feed', 'tip.channels'});
  });

  test('dismissing an already-dismissed key is a no-op', () async {
    container = await makeContainer(
      initialPrefs: {
        'tips.dismissedForever': ['tip.feed'],
      },
    );
    await container
        .read(tipDismissalProvider.notifier)
        .dismissForever('tip.feed');

    expect(container.read(tipDismissalProvider), {'tip.feed'});
  });

  test('resetAll clears every persisted forever-dismissal, durably', () async {
    container = await makeContainer(
      initialPrefs: {
        'tips.dismissedForever': ['tip.feed', 'tip.channels'],
      },
    );
    await container.read(tipDismissalProvider.notifier).resetAll();
    expect(container.read(tipDismissalProvider), isEmpty);
    container.dispose();

    // The reset itself survives a restart — it isn't just wiped in memory.
    final prefs = await SharedPreferences.getInstance();
    final restarted = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(restarted.dispose);
    expect(restarted.read(tipDismissalProvider), isEmpty);
  });

  group('TipSessionDismissalNotifier', () {
    test('a session dismissal never survives a restart', () async {
      container = await makeContainer();
      container.read(tipSessionDismissalProvider.notifier).dismiss('tip.feed');
      expect(container.read(tipSessionDismissalProvider), {'tip.feed'});
      container.dispose();

      final prefs = await SharedPreferences.getInstance();
      final restarted = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(restarted.dispose);
      expect(restarted.read(tipSessionDismissalProvider), isEmpty);
    });

    test('resetAll clears an in-session dismissal without a restart', () async {
      container = await makeContainer();
      container.read(tipSessionDismissalProvider.notifier).dismiss('tip.feed');
      expect(container.read(tipSessionDismissalProvider), {'tip.feed'});

      container.read(tipSessionDismissalProvider.notifier).resetAll();
      expect(container.read(tipSessionDismissalProvider), isEmpty);
    });
  });
}
