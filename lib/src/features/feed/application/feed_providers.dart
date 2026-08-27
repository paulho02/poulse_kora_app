import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cached.dart';
import '../../../core/providers.dart';
import '../../economy/application/economy_providers.dart';
import '../../history/application/history_providers.dart';
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

  /// Hits the server for a drop/forward review. Deliberately doesn't touch
  /// the local list — a caller that plays an exit animation (see
  /// `PostCard`) needs to know the review actually succeeded *before*
  /// starting it, and only remove the post (via [applyReviewResult]) once
  /// that animation finishes.
  Future<PostReviewResult> reviewPost(int postId, String kind) {
    return ref.read(feedRepositoryProvider).reviewPost(postId, kind);
  }

  /// Removes [postId] from the local list and applies the rest of a
  /// successful review's side effects. Only call this once the server has
  /// confirmed the review (i.e. after [reviewPost] resolved).
  void applyReviewResult(int postId, PostReviewResult result) {
    final current = state.value;
    if (current != null) {
      state = AsyncData(
        current.map((posts) => posts.where((p) => p.id != postId).toList()),
      );
    }
    ref
        .read(reviewGateStatusProvider.notifier)
        .updateFromReviewResult(
          reviewedCount: result.reviewedCount,
          reviewGate: result.reviewGate,
          unlocked: result.unlocked,
        );
    // Reviewing earns a token — keep the economy header current without a refetch.
    ref.read(economyProvider.notifier).setBalance(result.tokenBalance);
    ref.invalidate(reviewedHistoryProvider);
    ref.invalidate(statsProvider);
  }

  /// Convenience for callers with no exit animation to sequence around
  /// (e.g. the detail sheet, which closes immediately either way): review,
  /// then apply straight away.
  Future<void> reviewAndRemove(int postId, String kind) async {
    final result = await reviewPost(postId, kind);
    applyReviewResult(postId, result);
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
