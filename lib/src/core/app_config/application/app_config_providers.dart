import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../data/app_config_repository.dart';
import '../data/public_app_config.dart';

final appConfigRepositoryProvider = Provider<AppConfigRepository>(
  (ref) => AppConfigRepository(ref.watch(dioClientProvider).dio),
);

/// Fetched once at app start (see `PoulseKoraApp`'s warm-up `ref.listen`, same
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
