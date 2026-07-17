import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/stats_repository.dart';
import '../data/user_stats.dart';

final statsRepositoryProvider = Provider<StatsRepository>((ref) {
  return StatsRepository(ref.watch(dioClientProvider).dio);
});

final statsProvider = FutureProvider.autoDispose<UserStats>((ref) {
  return ref.watch(statsRepositoryProvider).fetchStats();
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

  Future<void> refresh() async {
    final stats = await ref.read(statsRepositoryProvider).fetchStats();
    state = ReviewGateStatus(
      reviewedCount: stats.reviewedCount,
      reviewGate: stats.reviewGate,
      unlocked: stats.unlocked,
    );
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
