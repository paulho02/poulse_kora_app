import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/economy.dart';
import '../data/economy_repository.dart';

final economyRepositoryProvider = Provider<EconomyRepository>((ref) {
  return EconomyRepository(ref.watch(dioClientProvider).dio);
});

/// Shared source of truth for the posting economy (spendable tokens + live
/// price), mirroring [ReviewGateStatusNotifier]. Seeded from `GET
/// /posts/economy`, then patched locally after a review earns a token or a post
/// spends tokens, so the header status bar stays current without extra network
/// round-trips. Price is refreshed on load / pull-to-refresh — not real-time.
class EconomyNotifier extends Notifier<Economy?> {
  @override
  Economy? build() => null;

  Future<void> ensureLoaded() async {
    if (state != null) return;
    await refresh();
  }

  Future<void> refresh() async {
    state = await ref.read(economyRepositoryProvider).fetchEconomy();
  }

  /// Patch just the balance from an authoritative value returned by a review or
  /// create-post response (avoids a refetch just to update the token count).
  void setBalance(int tokenBalance) {
    final current = state;
    if (current != null) {
      state = current.copyWith(tokenBalance: tokenBalance);
    }
  }
}

final economyProvider = NotifierProvider<EconomyNotifier, Economy?>(
  EconomyNotifier.new,
);
