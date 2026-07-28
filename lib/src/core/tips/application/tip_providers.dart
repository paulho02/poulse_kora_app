import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/app_settings.dart' show sharedPreferencesProvider;
import '../data/tip_dismissal_store.dart';

final tipDismissalStoreProvider = Provider<TipDismissalStore>(
  (ref) => TipDismissalStore(ref.watch(sharedPreferencesProvider)),
);

/// The set of tip keys dismissed "forever", read once at startup so later
/// reads are synchronous — same pattern as `AnnouncementForeverDismissalNotifier`.
class TipDismissalNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.read(tipDismissalStoreProvider).read();

  Future<void> dismissForever(String key) async {
    if (state.contains(key)) return;
    state = {...state, key};
    await ref.read(tipDismissalStoreProvider).write(state);
  }

  /// Backs "Reset tutorial hints" in Settings. Only clears the persisted
  /// half of dismissal — see `TipSessionDismissalNotifier.resetAll` for the
  /// other half, both of which the setting calls together.
  Future<void> resetAll() async {
    state = {};
    await ref.read(tipDismissalStoreProvider).clear();
  }
}

final tipDismissalProvider =
    NotifierProvider<TipDismissalNotifier, Set<String>>(
      TipDismissalNotifier.new,
    );

/// The "x" alone, per tip key — in-memory only, never persisted, so it
/// resets on next app launch same as `AnnouncementSessionDismissalNotifier`.
///
/// Kept as a provider rather than local `State` in `ViewTip` specifically so
/// "Reset tutorial hints" can bring a tip back on an already-mounted tab: each
/// tab's screen stays alive across switches (`StatefulShellRoute.indexedStack`),
/// so a plain `setState`-backed flag would never see the reset and the tip
/// would stay hidden until the next cold start.
class TipSessionDismissalNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void dismiss(String key) => state = {...state, key};

  void resetAll() => state = {};
}

final tipSessionDismissalProvider =
    NotifierProvider<TipSessionDismissalNotifier, Set<String>>(
      TipSessionDismissalNotifier.new,
    );

/// Clears both dismissal lifetimes so every tip reappears the next time its
/// tab is opened, without needing an app restart.
void resetAllTips(WidgetRef ref) {
  ref.read(tipDismissalProvider.notifier).resetAll();
  ref.read(tipSessionDismissalProvider.notifier).resetAll();
}
