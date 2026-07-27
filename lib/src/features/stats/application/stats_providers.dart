import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cached.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/providers.dart';
import '../data/global_stats.dart';
import '../data/stats_repository.dart';
import '../data/user_stats.dart';

final statsRepositoryProvider = Provider<StatsRepository>((ref) {
  return StatsRepository(
    ref.watch(dioClientProvider).dio,
    ref.watch(jsonCacheProvider),
  );
});

final statsProvider = FutureProvider.autoDispose<Cached<UserStats>>((ref) {
  return ref.watch(statsRepositoryProvider).fetchStats();
});

final globalStatsProvider = FutureProvider.autoDispose<Cached<GlobalStats>>((ref) {
  return ref.watch(statsRepositoryProvider).fetchGlobalStats();
});

class ReviewGateStatus {
  const ReviewGateStatus({
    required this.reviewedCount,
    required this.reviewGate,
    required this.unlocked,
  });

  final int reviewedCount;
  final int reviewGate;
  final bool unlocked;
}

/// Single shared source of truth for "can this user post right now?",
/// read by both the Create-Post and Stats screens. Seeded from `GET
/// /stats/me` and then patched locally by the Feed after each review action
/// (see FeedNotifier.reviewAndRemove) so posting a review doesn't need an
/// extra network round-trip just to refresh the gate.
class ReviewGateStatusNotifier extends Notifier<ReviewGateStatus?> {
  @override
  ReviewGateStatus? build() => null;

  Future<void> ensureLoaded() async {
    if (state != null) return;
    await refresh();
  }

  /// Swallows connectivity failures: this is seeded opportunistically from screen
  /// `initState`s, where an uncaught rejection would surface as an unhandled
  /// error rather than anything the user can act on. Offline, the gate simply
  /// stays at its last known value (or `—` if never loaded).
  Future<void> refresh() async {
    try {
      final stats = await ref.read(statsRepositoryProvider).fetchStats();
      state = ReviewGateStatus(
        reviewedCount: stats.data.reviewedCount,
        reviewGate: stats.data.reviewGate,
        unlocked: stats.data.unlocked,
      );
    } catch (e) {
      if (!asRelayException(e).isConnectivityFailure) rethrow;
    }
  }

  void updateFromReviewResult({
    required int reviewedCount,
    required int reviewGate,
    required bool unlocked,
  }) {
    state = ReviewGateStatus(
      reviewedCount: reviewedCount,
      reviewGate: reviewGate,
      unlocked: unlocked,
    );
  }
}

final reviewGateStatusProvider =
    NotifierProvider<ReviewGateStatusNotifier, ReviewGateStatus?>(
  ReviewGateStatusNotifier.new,
);
