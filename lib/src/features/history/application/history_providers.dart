import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../feed/data/post.dart';
import '../data/history_repository.dart';
import '../data/reviewed_post.dart';

const _pageSize = 20;

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return HistoryRepository(ref.watch(dioClientProvider).dio);
});

/// Common shape the history screen drives regardless of which concrete
/// notifier (posted vs. reviewed) backs it — lets the screen call
/// `loadMore`/check `hasMore` without knowing the item type.
abstract class HistoryPager {
  bool get hasMore;
  bool get isLoadingMore;
  Future<void> loadMore();
}

/// The current user's own posts, newest first, loaded page by page. `loadMore`
/// appends the next page; `hasMore` is false once a page comes back shorter
/// than the page size.
class PostedHistoryNotifier extends AsyncNotifier<List<Post>>
    implements HistoryPager {
  @override
  bool hasMore = true;
  @override
  bool isLoadingMore = false;

  @override
  Future<List<Post>> build() async {
    hasMore = true;
    final page = await ref
        .read(historyRepositoryProvider)
        .fetchMyPosts(limit: _pageSize);
    hasMore = page.length == _pageSize;
    return page;
  }

  @override
  Future<void> loadMore() async {
    if (isLoadingMore || !hasMore) return;
    final current = state.value;
    if (current == null) return;
    isLoadingMore = true;
    try {
      final page = await ref
          .read(historyRepositoryProvider)
          .fetchMyPosts(skip: current.length, limit: _pageSize);
      hasMore = page.length == _pageSize;
      state = AsyncData([...current, ...page]);
    } finally {
      isLoadingMore = false;
    }
  }
}

final postedHistoryProvider =
    AsyncNotifierProvider<PostedHistoryNotifier, List<Post>>(
      PostedHistoryNotifier.new,
    );

/// The current user's reviewed posts, newest-review-first, loaded page by page.
/// Same shape as `PostedHistoryNotifier`; kept separate rather than shared via
/// generics since the two item types and endpoints differ.
class ReviewedHistoryNotifier extends AsyncNotifier<List<ReviewedPost>>
    implements HistoryPager {
  @override
  bool hasMore = true;
  @override
  bool isLoadingMore = false;

  @override
  Future<List<ReviewedPost>> build() async {
    hasMore = true;
    final page = await ref
        .read(historyRepositoryProvider)
        .fetchMyReviews(limit: _pageSize);
    hasMore = page.length == _pageSize;
    return page;
  }

  @override
  Future<void> loadMore() async {
    if (isLoadingMore || !hasMore) return;
    final current = state.value;
    if (current == null) return;
    isLoadingMore = true;
    try {
      final page = await ref
          .read(historyRepositoryProvider)
          .fetchMyReviews(skip: current.length, limit: _pageSize);
      hasMore = page.length == _pageSize;
      state = AsyncData([...current, ...page]);
    } finally {
      isLoadingMore = false;
    }
  }
}

final reviewedHistoryProvider =
    AsyncNotifierProvider<ReviewedHistoryNotifier, List<ReviewedPost>>(
      ReviewedHistoryNotifier.new,
    );
