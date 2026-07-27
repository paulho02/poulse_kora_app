import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/error_state_view.dart';
import '../../../core/theme/app_colors.dart';
import '../../channels/application/channels_providers.dart';
import '../../economy/application/economy_providers.dart';
import '../../economy/presentation/economy_status_bar.dart';
import '../application/feed_providers.dart';
import 'post_card.dart';
import 'post_detail_sheet.dart';

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(feedNotifierProvider);
    final subscribedChannels = ref.watch(subscribedChannelsProvider);
    final selectedChannel = ref.watch(selectedChannelFilterProvider);

    // Seed the token/price header once; refreshed on pull-to-refresh below.
    ref.listen(expandedPostIdProvider, (previous, next) {
      if (next == null) return;
      final matches =
          feedAsync.value?.data.where((p) => p.id == next) ?? const [];
      if (matches.isNotEmpty) showPostDetailSheet(context, ref, matches.first);
    });
    Future.microtask(() => ref.read(economyProvider.notifier).ensureLoaded());

    return Scaffold(
      appBar: AppBar(
        title: Text(
          feedAsync.when(
            data: (feed) => 'Feed · ${feed.data.length} open posts',
            loading: () => 'Feed',
            error: (_, _) => 'Feed',
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload feed',
            onPressed: feedAsync.isLoading
                ? null
                : () => Future.wait([
                    ref.read(feedNotifierProvider.notifier).refresh(),
                    ref.read(economyProvider.notifier).refresh(),
                  ]),
          ),
        ],
      ),
      body: RefreshIndicator(
        // Pull-to-refresh (scroll up) also fetches the latest token balance/price.
        onRefresh: () => Future.wait([
          ref.read(feedNotifierProvider.notifier).refresh(),
          ref.read(economyProvider.notifier).refresh(),
        ]),
        child: Column(
          children: [
            const EconomyStatusBar(),
            if (subscribedChannels.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _ChannelChip(
                      label: 'All',
                      selected: selectedChannel == null,
                      onTap: () => ref
                          .read(selectedChannelFilterProvider.notifier)
                          .set(null),
                    ),
                    for (final channel in subscribedChannels)
                      _ChannelChip(
                        label: channel.name,
                        color: AppColors.channelColor(channel.name),
                        selected: selectedChannel == channel.id,
                        onTap: () => ref
                            .read(selectedChannelFilterProvider.notifier)
                            .set(channel.id),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: feedAsync.when(
                data: (feed) {
                  final posts = feed.data;
                  if (subscribedChannels.isEmpty) {
                    return _ScrollableEmptyState(
                      icon: Icons.forum_outlined,
                      title: 'Join a channel to get started',
                      subtitle:
                          'Subscribe to channels to start seeing posts in your feed.',
                      actionLabel: 'Browse channels',
                      onAction: () => context.go('/channels'),
                    );
                  }
                  if (posts.isEmpty) {
                    return const _ScrollableEmptyState(
                      icon: Icons.check_circle_outline,
                      title: 'All caught up',
                      subtitle: 'No posts to review right now.',
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
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: posts.length,
                          itemBuilder: (context, index) => PostCard(
                            key: ValueKey(posts[index].id),
                            post: posts[index],
                          ),
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                // Only reached with no cached feed at all — otherwise the
                // repository served the saved copy above.
                error: (error, _) => ErrorStateView(
                  error: error,
                  onRetry: () =>
                      ref.read(feedNotifierProvider.notifier).refresh(),
                ),
              ),
            ),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
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
