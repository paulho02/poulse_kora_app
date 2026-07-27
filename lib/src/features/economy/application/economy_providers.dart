import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cached.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/providers.dart';
import '../data/economy.dart';
import '../data/economy_repository.dart';

final economyRepositoryProvider = Provider<EconomyRepository>((ref) {
  return EconomyRepository(
    ref.watch(dioClientProvider).dio,
    ref.watch(jsonCacheProvider),
  );
});

/// Shared source of truth for the posting economy (spendable tokens + live
/// price), mirroring [ReviewGateStatusNotifier]. Seeded from `GET
/// /posts/economy`, then patched locally after a review earns a token or a post
/// spends tokens, so the header status bar stays current without extra network
/// round-trips. Price is refreshed on load / pull-to-refresh — not real-time.
class EconomyNotifier extends Notifier<Cached<Economy>?> {
  @override
  Cached<Economy>? build() => null;

  Future<void> ensureLoaded() async {
    if (state != null) return;
    await refresh();
  }

  /// Swallows connectivity failures — this is fired from screen build/init, so an
  /// uncaught rejection offline would become an unhandled error the user can do
  /// nothing about. The status bar falls back to the cached figures instead, and
  /// the offline banner already explains why they may be behind.
  Future<void> refresh() async {
    try {
      state = await ref.read(economyRepositoryProvider).fetchEconomy();
    } catch (e) {
      if (!asRelayException(e).isConnectivityFailure) rethrow;
    }
  }

  /// Patch just the balance from an authoritative value returned by a review or
  /// create-post response (avoids a refetch just to update the token count).
  void setBalance(int tokenBalance) {
    final current = state;
    if (current != null) {
      state = current.map((e) => e.copyWith(tokenBalance: tokenBalance));
    }
  }
}

final economyProvider = NotifierProvider<EconomyNotifier, Cached<Economy>?>(
  EconomyNotifier.new,
);
