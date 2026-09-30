import 'dart:async';

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

/// How often the feed asks whether anything has arrived, while it is on screen.
///
/// The question is one LRANGE server-side (`GET /posts/feed/status`) and the
/// answer is almost always "no", so this can be short enough that a post shows
/// up while you are still looking at the screen — which is the entire point —
/// without being a poll worth worrying about. It stops when the tab is left or
/// the app is backgrounded — nothing needs watching for a reader who is not
/// reading, and doubling as the activity signal the price formula reads means a
/// poll that kept running in the background would be a lie about who is here.
const _pollInterval = Duration(seconds: 20);

/// Ask early rather than at the bottom of the list: with this many posts left to
/// review, a reader is close enough to the end that anything arriving now lands
/// before they get there, and the feed never visibly runs dry.
const _topUpThreshold = 3;

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

/// The last thing `GET /posts/feed/status` said about the queue.
///
/// Kept beside the feed rather than inside it because it describes the *whole*
/// queue while the feed may be showing one channel of it — and because the two
/// answer different questions: the feed is what to read, this is whether there
/// is any point waiting for more.
class FeedQueueStatusNotifier extends Notifier<FeedQueueStatus?> {
  @override
  FeedQueueStatus? build() => null;

  void set(FeedQueueStatus status) => state = status;

  /// Drop one post from the count, once the server has confirmed it is gone
  /// from the queue. See [FeedQueueStatus.withoutPost].
  void remove(int postId) => state = state?.withoutPost(postId);
}

final feedQueueStatusProvider =
    NotifierProvider<FeedQueueStatusNotifier, FeedQueueStatus?>(
      FeedQueueStatusNotifier.new,
    );

/// The review queue, kept current by itself.
///
/// The feed is a queue the server pushes into, not a page a client asks for, so
/// the design goal is that a reader never has to ask: while the feed is on
/// screen it polls `GET /posts/feed/status` and *appends* whatever has arrived.
/// Pull-to-refresh is still there for impatience, but nothing depends on it.
class FeedNotifier extends AsyncNotifier<Cached<List<FeedEntry>>> {
  /// Every post id this session has already accounted for — pulled into the
  /// list, or reported by a status poll we then fetched against.
  ///
  /// This is what keeps the poll from costing anything. Without it, a channel
  /// filter alone would guarantee a wasted feed fetch on every single tick: the
  /// status lists the whole queue, the filtered list holds part of it, and the
  /// difference would read as news forever.
  final Set<int> _accountedFor = {};

  Timer? _poll;

  /// Whether the feed is on screen and wants a timer — kept apart from [_poll]
  /// itself because [build] re-runs whenever the channel filter changes, and the
  /// `onDispose` that tears the timer down fires with it. Without this, choosing
  /// a channel would quietly leave the feed static for the rest of the session.
  bool _watching = false;

  /// Guards against two feed fetches in flight at once — a poll landing on top
  /// of a scroll-triggered top-up would append the same arrival twice.
  bool _fetching = false;

  /// Reviews the server has accepted but whose card has not finished leaving
  /// yet — see [reviewPost] and [pendingRemoval].
  ///
  /// Several may be open at once: reviewing a second post while the first is
  /// still playing its score-and-slide is ordinary use, not a race to guard
  /// against, so this is a map rather than a single slot.
  final Map<int, PostReviewResult> _confirmed = {};

  @override
  Future<Cached<List<FeedEntry>>> build() async {
    // Changing the filter is a different queue view: refetch from scratch.
    final channelId = ref.watch(selectedChannelFilterProvider);
    ref.onDispose(_cancelTimer);
    _accountedFor.clear();
    _confirmed.clear();
    final feed = await ref
        .read(feedRepositoryProvider)
        .fetchFeed(channelId: channelId);
    _accountedFor.addAll(feed.data.map((e) => e.postId));
    _ensureTimer();
    return feed.map(_oldestFirst);
  }

  /// The server hands the queue back newest-placement-first (see the
  /// `/posts/feed` route's own docstring); the feed reads top-to-bottom, so
  /// this flips it to oldest-at-top. Every place that takes the server's order
  /// wholesale — here, and the stale-copy fallbacks in [_fetchAndAppend] and
  /// [_ontoHeldOrder] — goes through this, so "newer is always lower" holds
  /// everywhere, not just for the arrivals [_fetchAndAppend] appends.
  List<FeedEntry> _oldestFirst(List<FeedEntry> fetched) =>
      fetched.reversed.toList();

  // --- staying current ------------------------------------------------------

  /// Begin polling for arrivals. Idempotent — safe to call whenever the feed
  /// becomes visible again.
  void startWatching() {
    _watching = true;
    _ensureTimer();
    // Don't make a returning reader wait out a whole interval for news that may
    // have landed while they were elsewhere.
    unawaited(checkForArrivals());
  }

  /// Stop polling — the feed is off screen or the app is backgrounded. Nothing
  /// arrives into a queue nobody is reading, and it will be asked again on the
  /// way back in.
  void stopWatching() {
    _watching = false;
    _cancelTimer();
  }

  void _ensureTimer() {
    if (!_watching || _poll != null) return;
    _poll = Timer.periodic(_pollInterval, (_) => checkForArrivals());
  }

  void _cancelTimer() {
    _poll?.cancel();
    _poll = null;
  }

  /// Ask whether anything new is queued, and pull it in if so.
  ///
  /// Cheap to call for any reason at all — a tick, a resume, reaching the end of
  /// the list — because the status request is the only guaranteed cost and it
  /// answers "no" without touching Postgres.
  Future<void> checkForArrivals() async {
    if (_fetching) return;
    if (!state.hasValue) {
      // The first load is still running, or it failed outright (offline, most
      // likely). Retrying it is the useful thing to do either way, and beats
      // making the reader find the retry button once the network is back.
      // Appending to a list we do not have yet would only lose the arrival.
      if (state.isLoading) return;
      _fetching = true;
      try {
        await refresh();
      } catch (_) {
        // Still down. The next tick tries again.
      } finally {
        _fetching = false;
      }
      return;
    }
    final FeedQueueStatus status;
    try {
      status = await ref.read(feedRepositoryProvider).fetchFeedStatus();
    } catch (_) {
      // Offline, or a blip. Staying quiet is right: the list on screen is still
      // perfectly readable, and the next tick asks again.
      return;
    }
    ref.read(feedQueueStatusProvider.notifier).set(status);

    final isNews = status.postIds.any((id) => !_accountedFor.contains(id));
    if (!isNews) return;
    if (await _fetchAndAppend()) {
      // Reviewing earns tokens for everyone, so the price moves under a feed
      // left open. Worth one request when we were fetching anyway — awaited
      // rather than fired off, so nothing is still writing to providers after
      // the caller thinks this is done.
      try {
        await ref.read(economyProvider.notifier).refresh();
      } catch (_) {
        // A minute-stale price pill is not worth interrupting a reader for.
      }
    }
    // Even a fetch that appended nothing settles the question for these ids —
    // they belong to a channel the filter is hiding. Recording them is what
    // stops the filter from provoking the same fetch on every tick.
    _accountedFor.addAll(status.postIds);
  }

  /// Refetch the queue and add whatever is new to the *end* of the list.
  /// Returns whether anything was actually appended.
  ///
  /// Append, never reorder or remove. The server hands the queue back
  /// newest-first, so splicing arrivals in at the top would shove the post being
  /// read down the screen mid-sentence — the opposite of continuous. Reversed
  /// to oldest-first before appending (see [_oldestFirst]), so a batch of two+
  /// simultaneous arrivals still lands with the newer one lower, not just the
  /// batch as a whole below what was already on screen. And removal stays
  /// [applyReviewResult]'s job alone, so a card already playing its exit
  /// animation is never yanked out from under it by a poll that landed a
  /// moment after the review was accepted.
  Future<bool> _fetchAndAppend() async {
    if (_fetching) return false;
    final channelId = ref.read(selectedChannelFilterProvider);
    _fetching = true;
    try {
      final fetched = await ref
          .read(feedRepositoryProvider)
          .fetchFeed(channelId: channelId);
      // A stale result is the disk copy talking, not the server. It can only
      // repeat what we already hold, so it is never news.
      if (fetched.isStale) return false;
      final held = state.value;
      if (held == null) return false;
      // Coming back from a stale copy, take the live list wholesale: what we
      // were showing is of unknown age and may not be queued any more.
      if (held.isStale) {
        state = AsyncData(fetched.map(_oldestFirst));
        return fetched.data.isNotEmpty;
      }
      final heldIds = held.data.map((e) => e.postId).toSet();
      final arrivals = fetched.data.reversed
          .where((e) => !heldIds.contains(e.postId))
          .toList();
      if (arrivals.isEmpty) return false;
      state = AsyncData(Cached.live([...held.data, ...arrivals]));
      return true;
    } catch (_) {
      // Topping up is opportunistic — a failure leaves the readable list alone
      // and costs nothing but a wait for the next tick.
      return false;
    } finally {
      _fetching = false;
    }
  }

  /// Refetch from scratch, keeping the current posts on screen while it runs.
  ///
  /// Deliberately no `AsyncLoading` first: blanking the list to a spinner loses
  /// the reader's place, which is exactly the reload-and-start-over feel this
  /// feed is meant to be rid of. `RefreshIndicator` draws its own spinner over
  /// the posts already there, and a failure throws so the caller can say so
  /// without the list disappearing underneath the message.
  Future<void> refresh() async {
    final channelId = ref.read(selectedChannelFilterProvider);
    final feed = await ref
        .read(feedRepositoryProvider)
        .fetchFeed(channelId: channelId);
    _accountedFor
      ..clear()
      ..addAll(feed.data.map((e) => e.postId));
    state = AsyncData(feed.map(_ontoHeldOrder));
  }

  /// A freshly fetched queue, laid out in the order the reader already has.
  ///
  /// The server hands the queue back newest-placement-first, but [_fetchAndAppend]
  /// deliberately puts arrivals at the *end* so nothing shoves the post being
  /// read down the screen. Taking the server's order wholesale here undid that:
  /// a reader who had picked up one arrival — which a review reliably produces,
  /// since it frees the queue slot the worker then fills — saw the whole list
  /// resort itself the next time they pulled to refresh, with the bottom post
  /// jumping to the top. Two orderings for the same set of posts, and the
  /// refresh was the one that moved things under a reader who was mid-sentence.
  ///
  /// So the fetch decides *membership* and the list on screen decides
  /// *position*: what the reader is already looking at stays where it is, what
  /// the queue no longer holds goes, and anything genuinely new lands at the
  /// end. Same rule as an arrival, so there is only one order to learn.
  List<FeedEntry> _ontoHeldOrder(List<FeedEntry> fetched) {
    final held = state.value;
    // Nothing to preserve, or what we hold came off disk and is of unknown age
    // — the live list is the better answer in both cases.
    if (held == null || held.isStale) return _oldestFirst(fetched);
    final position = {
      for (var i = 0; i < held.data.length; i++) held.data[i].postId: i,
    };
    final known = <FeedEntry>[];
    final arrivals = <FeedEntry>[];
    // Oldest-of-`fetched`-first, so a batch of several new arrivals keeps the
    // newer one lower within that batch too — see [_oldestFirst].
    for (final entry in fetched.reversed) {
      (position.containsKey(entry.postId) ? known : arrivals).add(entry);
    }
    // A post the server has already taken a verdict on has left the queue but
    // is still on screen, mid-exit. Dropping it here would yank the card out
    // from under its own animation — [applyReviewResult] retires it a beat
    // later, which is the one place removal belongs.
    final fetchedIds = fetched.map((e) => e.postId).toSet();
    for (final entry in held.data) {
      if (_confirmed.containsKey(entry.postId) &&
          !fetchedIds.contains(entry.postId)) {
        known.add(entry);
      }
    }
    known.sort((a, b) => position[a.postId]!.compareTo(position[b.postId]!));
    return [...known, ...arrivals];
  }

  // --- reviewing ------------------------------------------------------------

  /// Hits the server for a drop/forward review. Deliberately doesn't touch
  /// the local list: every caller has something to play between the server's
  /// answer and the post's removal — the forwarding score the answer carries,
  /// then an exit (the card's slide, the detail page's pop) — and none of that
  /// may start before the review is known to have succeeded. So callers review
  /// first and commit the removal with [applyReviewResult] once they are done.
  ///
  /// The confirmation is remembered until they do, so that a caller which never
  /// gets to finish cannot strand the post here. See [pendingRemoval].
  Future<PostReviewResult> reviewPost(
    int postId,
    String kind, {
    bool giftToken = false,
  }) async {
    final result = await ref
        .read(feedRepositoryProvider)
        .reviewPost(postId, kind, giftToken: giftToken);
    _confirmed[postId] = result;
    return result;
  }

  /// The confirmation for a post the server has already taken a verdict on but
  /// which is still on the list, or null if there is none.
  ///
  /// The safety net under the animation: the verdict lives on the server the
  /// moment [reviewPost] resolves, but the removal is owed by a widget that may
  /// be gone by then — and a post left here would be shown again, with live
  /// buttons, good for nothing but a 409. A card rebuilt for one of these
  /// commits it instead of rendering (see `PostCard.initState`). Nothing else
  /// re-adds a post, so this stays empty in the normal case.
  PostReviewResult? pendingRemoval(int postId) => _confirmed[postId];

  /// Drops one slot from the list on screen, whatever kind it was.
  ///
  /// Kept apart from [applyReviewResult] because dismissing a [MissingPost] is
  /// the only other thing that removes an entry, and it has none of a review's
  /// side effects — no score, no token, no history to invalidate.
  /// Whether [postId] is still on the list on screen.
  bool _holds(int postId) =>
      state.value?.data.any((e) => e.postId == postId) ?? false;

  void _removeFromList(int postId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.map(
        (entries) => entries.where((e) => e.postId != postId).toList(),
      ),
    );
    // The list and the status describe the same queue, so they have to move
    // together. The list is what this screen renders; the status is what the
    // *other* tabs read for the nav-bar count, and it is only otherwise
    // refreshed by a poll. Both callers of this reach it after the server has
    // confirmed the slot is gone, which is the only point at which this is
    // true rather than optimistic.
    ref.read(feedQueueStatusProvider.notifier).remove(postId);
  }

  /// Clear a slot whose post no longer exists — the ghost card's one button.
  ///
  /// Removed locally only once the server has confirmed, exactly like a review:
  /// it answers 409 while the post is still there, which means this list is
  /// stale and dropping the card would hide a post the reader still owes a
  /// verdict on. Throws on failure so the card can say so.
  Future<void> dismissMissingPost(int postId) async {
    await ref.read(feedRepositoryProvider).dismissMissingPost(postId);
    _removeFromList(postId);
    // A slot just freed up server-side, same as a review — so the worker may be
    // placing something right now.
    if ((state.value?.data.length ?? 0) <= _topUpThreshold) {
      unawaited(checkForArrivals());
    }
  }

  /// Removes [postId] from the local list and applies the rest of a
  /// successful review's side effects. Only call this once the server has
  /// confirmed the review (i.e. after [reviewPost] resolved).
  void applyReviewResult(int postId, PostReviewResult result) {
    if (_confirmed.remove(postId) == null && !_holds(postId)) {
      // Already committed — a card that was rebuilt mid-exit can hand us the
      // same result its predecessor was carrying. The list work below is
      // idempotent but the token balance and the review-gate counters are not.
      return;
    }
    _removeFromList(postId);
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

    // A review is also the one moment a slot is guaranteed to have just freed
    // up server-side, so the worker may be placing something *right now*. Ask
    // immediately rather than waiting out the tick, once the list is short
    // enough that the answer would arrive in time to matter.
    if ((state.value?.data.length ?? 0) <= _topUpThreshold) {
      unawaited(checkForArrivals());
    }
  }
}

final feedNotifierProvider =
    AsyncNotifierProvider<FeedNotifier, Cached<List<FeedEntry>>>(
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
