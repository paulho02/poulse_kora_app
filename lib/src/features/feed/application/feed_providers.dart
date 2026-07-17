import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../stats/application/stats_providers.dart';
import '../data/feed_repository.dart';
import '../data/post.dart';

final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  return FeedRepository(ref.watch(dioClientProvider).dio);
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

class FeedNotifier extends AsyncNotifier<List<Post>> {
  @override
  Future<List<Post>> build() {
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
  Future<void> reviewAndRemove(int postId, String kind) async {
    final current = state.value ?? [];
    state = AsyncData(current.where((p) => p.id != postId).toList());

    try {
      final result = await ref.read(feedRepositoryProvider).reviewPost(postId, kind);
      ref.read(reviewGateStatusProvider.notifier).updateFromReviewResult(
            reviewedCount: result.reviewedCount,
            reviewGate: result.reviewGate,
            unlocked: result.unlocked,
          );
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }
}

final feedNotifierProvider = AsyncNotifierProvider<FeedNotifier, List<Post>>(
  FeedNotifier.new,
);

/// Which post (if any) is expanded in the detail bottom sheet.
class ExpandedPostIdNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? postId) => state = postId;
}

final expandedPostIdProvider = NotifierProvider<ExpandedPostIdNotifier, int?>(
  ExpandedPostIdNotifier.new,
);
