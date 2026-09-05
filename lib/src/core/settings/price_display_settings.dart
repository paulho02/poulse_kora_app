import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart' show sharedPreferencesProvider;

/// Whether channel prices are shown while browsing.
///
/// Off by default, and deliberately so. Most of the time nobody is choosing a
/// channel by price — you post about a thing to the channel for that thing —
/// and a permanent column of numbers next to every channel would turn browsing
/// into reading a market board. The exception is the one mode this switch is
/// for: someone who wants to post, can't afford it yet, and is reviewing to
/// earn the difference. In that mode the price *is* what they are watching, and
/// what they actually want to know is not "what does it cost" but "can I afford
/// it yet" — which is why the tiles render the price against the balance rather
/// than on its own.
///
/// So this is less a preference than a mode switch, which is also why it is not
/// synced: like [LocaleSettingsStore] it has no server counterpart, and unlike
/// dark mode it is not cleared on logout (`AppSettingsNotifier.reset`) — it
/// describes how this device draws a list, not anything about an account.
class PriceDisplayStore {
  PriceDisplayStore(this._prefs);
  final SharedPreferences _prefs;

  static const _key = 'settings.showChannelPrices';

  bool read() => _prefs.getBool(_key) ?? false;

  Future<void> write(bool value) => _prefs.setBool(_key, value);
}

class ShowChannelPricesNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(priceDisplayStoreProvider).read();

  Future<void> set(bool value) async {
    if (state == value) return;
    state = value;
    await ref.read(priceDisplayStoreProvider).write(value);
  }

  Future<void> toggle() => set(!state);
}

final priceDisplayStoreProvider = Provider<PriceDisplayStore>(
  (ref) => PriceDisplayStore(ref.watch(sharedPreferencesProvider)),
);

/// Watched by the channels list, the composer's channel picker and the economy
/// explainer's switch, so all three agree on whether prices are on screen.
final showChannelPricesProvider =
    NotifierProvider<ShowChannelPricesNotifier, bool>(
      ShowChannelPricesNotifier.new,
    );
