import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/tips/presentation/view_tip.dart';
import '../../channels/application/channels_providers.dart';
import '../../channels/data/channel.dart';
import '../../economy/application/economy_providers.dart';
import '../../economy/presentation/economy_header_status.dart';
import '../application/feed_providers.dart';
import 'post_card.dart';
import 'post_detail_view.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

/// How close to the bottom counts as "about to run out", and so worth asking
/// the server whether anything has arrived. Roughly a card's height, so the
/// question is asked while there is still something left to read.
const double _endOfFeedSlack = 400;

class _FeedScreenState extends ConsumerState<FeedScreen> {
  /// Whether the channel filter shows its full row of chips, or the one-line
  /// summary it collapses into while reading. See [_onUserScroll].
  bool _filterExpanded = true;

  /// Whether this is the tab being looked at, and whether the app is in front.
  /// The feed only watches for arrivals when both hold — see [_syncWatching].
  bool _onScreen = false;
  bool _resumed = true;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _resumed = state == AppLifecycleState.resumed;
        _syncWatching();
      },
    );
    // Seed the token pill once; refreshed on pull-to-refresh and whenever a
    // poll actually brings something in.
    Future.microtask(() => ref.read(economyProvider.notifier).ensureLoaded());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `StatefulShellRoute.indexedStack` keeps every tab mounted and turns the
    // ticker off on the ones you cannot see, so this — not `initState` — is
    // where the feed learns whether it is the tab being read.
    _onScreen = TickerMode.valuesOf(context).enabled;
    _syncWatching();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    ref.read(feedNotifierProvider.notifier).stopWatching();
    super.dispose();
  }

  void _syncWatching() {
    final feed = ref.read(feedNotifierProvider.notifier);
    if (_onScreen && _resumed) {
      feed.startWatching();
    } else {
      feed.stopWatching();
    }
  }

  /// Reaching the end of the list is a reader saying "more, please" — the same
  /// gesture as an infinite scroll, answered by asking the queue rather than by
  /// paging (there is no next page; there is only what has arrived since).
  ///
  /// Keyed on the scroll *settling* rather than on every update, so a fling
  /// down the feed asks once instead of once a frame.
  bool _onScrollEnd(ScrollEndNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification.metrics.extentAfter > _endOfFeedSlack) return false;
    unawaited(ref.read(feedNotifierProvider.notifier).checkForArrivals());
    return false;
  }

  /// Pull-to-refresh. Says so when it fails instead of letting the list vanish:
  /// `refresh` leaves the posts already on screen alone and throws, so the
  /// reader keeps reading and merely learns the reload did not land.
  Future<void> _refresh(AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Future.wait([
        ref.read(feedNotifierProvider.notifier).refresh(),
        ref.read(economyProvider.notifier).refresh(),
      ]);
    } catch (error) {
      showErrorSnackBarOn(messenger, l10n, error);
    }
  }

  /// Collapse the filter while scrolling into the feed, restore it on the way
  /// back up.
  ///
  /// The filter is a navigation control, not part of the article — it earns its
  /// 44dp when you are choosing what to read and costs a post card's worth of
  /// screen when you are reading. Reacting to the *gesture* rather than to the
  /// offset is what makes it feel like a scrollbar rather than a header that
  /// snaps at some magic pixel: reaching back up for the filter is the same
  /// motion as reaching back up the feed.
  bool _onUserScroll(UserScrollNotification notification) {
    // The chip row is itself a scroll view; only the feed under it drives this.
    if (notification.metrics.axis != Axis.vertical) return false;
    final expanded = switch (notification.direction) {
      ScrollDirection.reverse => false,
      ScrollDirection.forward => true,
      ScrollDirection.idle => _filterExpanded,
    };
    if (expanded != _filterExpanded) {
      setState(() => _filterExpanded = expanded);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(feedNotifierProvider);
    final subscribedChannels = ref.watch(subscribedChannelsProvider);
    final selectedChannelId = ref.watch(selectedChannelFilterProvider);
    final l10n = AppLocalizations.of(context);

    ref.listen(expandedPostIdProvider, (previous, next) {
      if (next == null) return;
      final matches =
          feedAsync.value?.data.where((p) => p.id == next) ?? const [];
      if (matches.isNotEmpty) showPostDetail(context, ref, matches.first);
    });

    Channel? selectedChannel;
    for (final channel in subscribedChannels) {
      if (channel.id == selectedChannelId) {
        selectedChannel = channel;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        // No open-post count: it was a number nobody acts on, and the title bar
        // is worth more as the one place the token balance lives.
        //
        // No reload button either. The feed watches the queue while it is on
        // screen and appends what arrives, so a button whose whole job is
        // "check again" would be advertising a chore that no longer exists —
        // and its presence is most of what made this read as a static list.
        // Pull-to-refresh stays, for impatience rather than necessity.
        title: Text(l10n.feedTitle),
        actions: const [EconomyHeaderStatus()],
      ),
      body: ViewTip(
        tipKey: 'tip.feed',
        message: l10n.feedTipMessage,
        child: RefreshIndicator(
          // Pull-to-refresh (scroll up) also fetches the latest token balance/price.
          onRefresh: () => _refresh(l10n),
          child: Column(
            // Explicit instead of relying on the default (`center`): with
            // `center`, this Column's own width comes from the widest of its
            // children, and once `ViewTip`'s tip card is dismissed its
            // sibling placeholder is a zero-height `SizedBox(width:
            // double.infinity)` - which, through `ViewTip`'s own Column,
            // ends up making our width ambiguous and the chip row area
            // collapse to its content width and get centered by *its*
            // ancestor instead of spanning full width. `stretch` makes this
            // Column's own width unambiguous regardless of what an ancestor
            // we don't control does.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (subscribedChannels.isNotEmpty)
                _ChannelFilter(
                  channels: subscribedChannels,
                  selected: selectedChannel,
                  expanded: _filterExpanded,
                  onSelect: (channel) => ref
                      .read(selectedChannelFilterProvider.notifier)
                      .set(channel?.id),
                  onExpand: () => setState(() => _filterExpanded = true),
                ),
              Expanded(
                child: NotificationListener<ScrollEndNotification>(
                  onNotification: _onScrollEnd,
                  child: NotificationListener<UserScrollNotification>(
                    onNotification: _onUserScroll,
                    child: feedAsync.when(
                      data: (feed) {
                        final posts = feed.data;
                        if (subscribedChannels.isEmpty) {
                          return _ScrollableEmptyState(
                            icon: Icons.forum_outlined,
                            title: l10n.feedEmptyNoChannelsTitle,
                            subtitle: l10n.feedEmptyNoChannelsSubtitle,
                            actionLabel: l10n.feedEmptyNoChannelsAction,
                            onAction: () => context.go('/channels'),
                          );
                        }
                        if (posts.isEmpty) {
                          // A channel filter isn't the reason there's nothing in
                          // the *whole* queue — only mention it (and offer to
                          // clear it) when it's plausibly why this one channel
                          // looks empty, so the user doesn't wonder where their
                          // posts went.
                          final filtered = selectedChannel;
                          if (filtered != null) {
                            return _ScrollableEmptyState(
                              icon: Icons.filter_alt_off_outlined,
                              title: l10n.feedEmptyFilteredTitle(filtered.name),
                              subtitle: l10n.feedEmptyFilteredSubtitle,
                              actionLabel: l10n.feedEmptyFilteredAction,
                              onAction: () => ref
                                  .read(selectedChannelFilterProvider.notifier)
                                  .set(null),
                            );
                          }
                          return _ScrollableEmptyState(
                            icon: Icons.check_circle_outline,
                            title: l10n.feedEmptyCaughtUpTitle,
                            subtitle: l10n.feedEmptyCaughtUpSubtitle,
                          );
                        }
                        return Column(
                          children: [
                            // Says so when these posts came off disk, so nobody acts on
                            // a queue that may have moved on without them.
                            if (feed.staleLabel != null)
                              StaleDataNotice(label: feed.staleLabel!),
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                // One past the end for the footer: scrolling off
                                // the last post should land on a statement about
                                // what happens next, not on a hard stop that
                                // looks like the app forgot to load more.
                                itemCount: posts.length + 1,
                                itemBuilder: (context, index) =>
                                    index == posts.length
                                    ? const _EndOfFeedNotice()
                                    : PostCard(
                                        key: ValueKey(posts[index].id),
                                        post: posts[index],
                                      ),
                              ),
                            ),
                          ],
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      // Only reached with no cached feed at all — otherwise the
                      // repository served the saved copy above.
                      error: (error, _) => ErrorStateView(
                        error: error,
                        onRetry: () => _refresh(l10n),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The channel filter in its two sizes: a row of chips to choose with, and a
/// single line stating what is being read once the choosing is done.
///
/// Both are the same control — tapping the collapsed line brings the chips
/// back, so the filter is never more than one tap away from wherever the feed
/// has been scrolled to.
class _ChannelFilter extends StatelessWidget {
  const _ChannelFilter({
    required this.channels,
    required this.selected,
    required this.expanded,
    required this.onSelect,
    required this.onExpand,
  });

  final List<Channel> channels;
  final Channel? selected;
  final bool expanded;
  final ValueChanged<Channel?> onSelect;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 180),
      sizeCurve: Curves.easeOutCubic,
      crossFadeState: expanded
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
      // Both halves are laid out at full width even while collapsed, so the
      // chips don't reflow as the row closes.
      alignment: Alignment.topCenter,
      // A `Row` inside a scroll view, not a horizontal `ListView` in a fixed
      // 44dp box: a horizontal ListView forces every child to *exactly* the
      // viewport height, and a Material chip squeezed below the height it
      // wants centres its label against the padding it asked for and eats the
      // whole deficit off the bottom — which is what left the tag text sitting
      // low. A Row passes the height constraint down loose, so each chip lays
      // out at its natural height and the label is centred in it.
      //
      // `mainAxisSize.min` keeps the row hugging its own content (and so the
      // left edge) instead of trying to fill — and then re-centring within —
      // the scroll view's width when there are too few chips to scroll.
      firstChild: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ChannelChip(
              label: l10n.feedAllChannelsChip,
              selected: selected == null,
              onTap: () => onSelect(null),
            ),
            for (final channel in channels)
              _ChannelChip(
                label: channel.name,
                color: AppColors.channelColor(channel.name),
                selected: selected?.id == channel.id,
                onTap: () => onSelect(channel),
              ),
          ],
        ),
      ),
      secondChild: _CollapsedChannelFilter(selected: selected, onTap: onExpand),
    );
  }
}

/// The filter while reading: which channel the feed is showing, and a way back
/// to the chips.
class _CollapsedChannelFilter extends StatelessWidget {
  const _CollapsedChannelFilter({required this.selected, required this.onTap});

  final Channel? selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final channel = selected;
    final color = channel == null
        ? theme.colorScheme.onSurfaceVariant
        : AppColors.channelColor(channel.name);

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  channel?.name ?? l10n.feedAllChannelsLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.expand_more,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
                semanticLabel: l10n.feedShowChannelFilter,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelChip extends StatelessWidget {
  const _ChannelChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final outline = color ?? Theme.of(context).colorScheme.outlineVariant;
    return Padding(
      // Horizontal only. The chip's own tap-target padding already sets its
      // height (48dp), and adding to it just makes the filter row taller than
      // the control inside it needs to be.
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        // Hide the check mark: it reserves leading space only when selected,
        // which shifts the label off-centre. The colored border + selected
        // fill signal selection instead.
        showCheckmark: false,
        labelPadding: const EdgeInsets.symmetric(horizontal: 10),
        // Fully rounded (pill) tags with the channel color as the border.
        shape: const StadiumBorder(),
        side: BorderSide(color: outline),
      ),
    );
  }
}

/// The line under the last post, saying what happens when you run out.
///
/// A feed that simply stops at the last card reads as unfinished — the reader
/// cannot tell "that's all there is for now" from "it failed to load the rest",
/// and the only way to find out used to be reloading. This says which it is, and
/// distinguishes the two states worth distinguishing: a full queue is work
/// waiting to be done, an empty one is a queue waiting on other people.
class _EndOfFeedNotice extends ConsumerWidget {
  const _EndOfFeedNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(feedQueueStatusProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 36),
      child: Text(
        status != null && status.isFull
            ? l10n.feedQueueFullNotice
            : l10n.feedUpToDateNotice,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Wraps [_EmptyState] in a scrollable so `RefreshIndicator` still picks up
/// the pull-down gesture when there's no list to scroll (empty feed).
class _ScrollableEmptyState extends StatelessWidget {
  const _ScrollableEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: _EmptyState(
            icon: icon,
            title: title,
            subtitle: subtitle,
            actionLabel: actionLabel,
            onAction: onAction,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
