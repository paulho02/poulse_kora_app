import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../data/app_config_repository.dart';
import '../data/public_app_config.dart';

final appConfigRepositoryProvider = Provider<AppConfigRepository>(
  (ref) => AppConfigRepository(ref.watch(dioClientProvider).dio),
);

/// Fetched once at app start (see `PeerkolaApp`'s warm-up `ref.listen`, same
/// pattern as `announcementProvider`). `null` covers both "nothing set" and
/// "the fetch failed" - the router fails open (treats it as "verification not
/// currently enforced") rather than blocking startup on this.
final appConfigProvider = FutureProvider<PublicAppConfig?>((ref) async {
  try {
    return await ref.watch(appConfigRepositoryProvider).fetchConfig();
  } catch (_) {
    return null;
  }
});

/// Set the moment any request comes back `unverified_user` (see backend
/// `get_verified_user`) - proof positive that the backend enforces
/// verification *right now*, regardless of what [appConfigProvider] cached at
/// app start. Covers `REQUIRE_EMAIL_VERIFICATION` being turned on mid-session
/// (or turned on between app launches without a fresh `/config` fetch
/// happening to notice): without this, a blocked request had no way to get
/// the user to `/verify-email` at all - the router only reacts to
/// `appConfigProvider`/`profileProvider` actually changing value, and a stale
/// cached `false` never does. See `routing/app_router.dart`.
///
/// Deliberately one-way for the life of a session (reset only at session
/// boundaries, see `_invalidateSessionScoped`) rather than cleared once
/// `is_verified` flips true - it's ANDed with `profile.isVerified == false`
/// everywhere it's read, so a stuck `true` is harmless once verified, and
/// clearing it would just reopen the same race this exists to close.
class ServerConfirmedVerificationRequiredNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void markConfirmed() => state = true;
}

final serverConfirmedVerificationRequiredProvider =
    NotifierProvider<ServerConfirmedVerificationRequiredNotifier, bool>(
      ServerConfirmedVerificationRequiredNotifier.new,
    );
