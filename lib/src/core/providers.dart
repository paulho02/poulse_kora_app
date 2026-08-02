import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cache/json_cache.dart';
import 'config/server_config.dart';
import 'network/connectivity.dart';
import 'network/dio_client.dart';
import 'settings/app_settings.dart';
import 'settings/locale_settings.dart';
import 'storage/token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final jsonCacheProvider = Provider<JsonCache>(
  (ref) => JsonCache(ref.watch(sharedPreferencesProvider)),
);

/// Set by `dioClientProvider`'s 401 handler. Lives here as a mutable hook rather
/// than a direct `authNotifierProvider` read because `core/` must not depend on a
/// feature — and because reading auth from inside the client that auth configures
/// would be a provider cycle.
final onUnauthorizedProvider = Provider<Future<void> Function()>(
  (ref) => () async {},
);

final dioClientProvider = Provider<DioClient>((ref) {
  return DioClient(
    ref.watch(tokenStorageProvider),
    baseUrl: ref.watch(serverConfigProvider).baseUrl,
    connectivity: ref.watch(connectivityProvider.notifier),
    onUnauthorized: () => ref.read(onUnauthorizedProvider)(),
    localeCode: () => ref.read(activeLocaleProvider).languageCode,
  );
});
