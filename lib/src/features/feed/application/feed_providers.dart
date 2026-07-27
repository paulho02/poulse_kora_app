import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cached.dart';
import '../../../core/providers.dart';
import '../../economy/application/economy_providers.dart';
import '../../stats/application/stats_providers.dart';
import '../data/feed_repository.dart';
import '../data/post.dart';

final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  return FeedRepository(
    ref.watch(dioClientProvider).dio,
    ref.watch(jsonCacheProvider),
  );
});

/// `null` means "all subscribed channels" (no filter).
class SelectedChannelFilterNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? channelId) => state = channelId;
}

final selectedChannelFilterProvider =
    NotifierProvider<SelectedChannelFilterNotifier, int?>(
      SelectedChannelFilterNotifier.new,
    );

class FeedNotifier extends AsyncNotifier<Cached<List<Post>>> {
  @override
  Future<Cached<List<Post>>> build() {
    final channelId = ref.watch(selectedChannelFilterProvider);
    return ref.read(feedRepositoryProvider).fetchFeed(channelId: channelId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    final channelId = ref.read(selectedChannelFilterProvider);
    state = await AsyncValue.guard(
      () => ref.read(feedRepositoryProvider).fetchFeed(channelId: channelId),
    );
  }

  /// Optimistically removes the post from the local list immediately (safe
  /// here because the simplified feed model guarantees reviewing a post
  /// never changes what other users see), then pushes the result into the
  /// shared review-gate status without an extra network round-trip.
  ///
  /// The rollback in the catch is also what makes an offline review behave
  /// sanely: the card reappears and the caller shows the reason, rather than the
  /// post silently vanishing into a change that never reached the server.
  Future<void> reviewAndRemove(int postId, String kind) async {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.map((posts) => posts.where((p) => p.id != postId).toList()),
    );

    try {
      final result = await ref
          .read(feedRepositoryProvider)
          .reviewPost(postId, kind);
      ref
          .read(reviewGateStatusProvider.notifier)
          .updateFromReviewResult(
            reviewedCount: result.reviewedCount,
            reviewGate: result.reviewGate,
            unlocked: result.unlocked,
          );
      // Reviewing earns a token — keep the economy header current without a refetch.
      ref.read(economyProvider.notifier).setBalance(result.tokenBalance);
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }
}

final feedNotifierProvider =
    AsyncNotifierProvider<FeedNotifier, Cached<List<Post>>>(FeedNotifier.new);

/// Which post (if any) is expanded in the detail bottom sheet.
class ExpandedPostIdNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? postId) => state = postId;
}

final expandedPostIdProvider = NotifierProvider<ExpandedPostIdNotifier, int?>(
  ExpandedPostIdNotifier.new,
);
