import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers.dart';
import '../../settings/app_settings.dart' show sharedPreferencesProvider;
import '../data/announcement.dart';
import '../data/announcement_repository.dart';

final announcementRepositoryProvider = Provider<AnnouncementRepository>(
  (ref) => AnnouncementRepository(ref.watch(dioClientProvider).dio),
);

/// Fetched once at app start. `null` covers both "nothing is set" and "the
/// fetch failed" — this is a best-effort banner and must never surface an
/// error or block startup.
final announcementProvider = FutureProvider<Announcement?>((ref) async {
  try {
    return await ref.watch(announcementRepositoryProvider).fetchAnnouncement();
  } catch (_) {
    return null;
  }
});

/// Persists the id of the message the user chose to never see again.
/// Only the most recent such choice needs keeping — a later message with a
/// different id is unaffected by whatever was dismissed before it.
class AnnouncementDismissalStore {
  AnnouncementDismissalStore(this._prefs);
  final SharedPreferences _prefs;
  static const _dismissedForeverId = 'announcement.dismissedForeverId';

  String? read() => _prefs.getString(_dismissedForeverId);
  Future<void> write(String id) => _prefs.setString(_dismissedForeverId, id);
}

final announcementDismissalStoreProvider = Provider<AnnouncementDismissalStore>(
  (ref) => AnnouncementDismissalStore(ref.watch(sharedPreferencesProvider)),
);

/// The id most recently dismissed "forever", read once at startup so later
/// reads are synchronous (same pattern as `AppSettingsNotifier`).
class AnnouncementForeverDismissalNotifier extends Notifier<String?> {
  @override
  String? build() => ref.read(announcementDismissalStoreProvider).read();

  Future<void> dismissForever(String id) async {
    state = id;
    await ref.read(announcementDismissalStoreProvider).write(id);
  }
}

final announcementForeverDismissalProvider =
    NotifierProvider<AnnouncementForeverDismissalNotifier, String?>(
      AnnouncementForeverDismissalNotifier.new,
    );

/// The "x" alone — in-memory only, never persisted, so it resets on next launch.
class AnnouncementSessionDismissalNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void dismiss(String id) => state = id;
}

final announcementSessionDismissalProvider =
    NotifierProvider<AnnouncementSessionDismissalNotifier, String?>(
      AnnouncementSessionDismissalNotifier.new,
    );

/// The single source of truth `InfoBanner` renders from: null means "show
/// nothing". A brand-new announcement id always passes both checks below even
/// if some *other*, older id was dismissed forever or this session.
final visibleAnnouncementProvider = Provider<Announcement?>((ref) {
  final announcement = ref.watch(announcementProvider).value;
  if (announcement == null) return null;
  if (ref.watch(announcementSessionDismissalProvider) == announcement.id) {
    return null;
  }
  if (ref.watch(announcementForeverDismissalProvider) == announcement.id) {
    return null;
  }
  return announcement;
});
