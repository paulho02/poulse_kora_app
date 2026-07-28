import 'package:shared_preferences/shared_preferences.dart';

/// Persists which per-view tips (see `presentation/view_tip.dart`) the user
/// has permanently dismissed via "Don't show again".
///
/// Same shape as `AnnouncementDismissalStore`
/// (`core/announcements/application/announcement_providers.dart`), generalized
/// from one hardcoded id to an arbitrary set of tip keys, since there's one
/// tip per tab rather than a single global announcement.
class TipDismissalStore {
  TipDismissalStore(this._prefs);
  final SharedPreferences _prefs;
  static const _dismissedForeverKeys = 'tips.dismissedForever';

  Set<String> read() =>
      (_prefs.getStringList(_dismissedForeverKeys) ?? const []).toSet();

  Future<void> write(Set<String> keys) =>
      _prefs.setStringList(_dismissedForeverKeys, keys.toList());

  Future<void> clear() => _prefs.remove(_dismissedForeverKeys);
}
