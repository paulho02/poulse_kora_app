import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/tips/presentation/view_tip.dart';
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
    final l10n = AppLocalizations.of(context);

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
            data: (feed) => l10n.feedTitleWithCount(feed.data.length),
            loading: () => l10n.feedTitle,
            error: (_, _) => l10n.feedTitle,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.feedReloadTooltip,
            onPressed: feedAsync.isLoading
                ? null
                : () => Future.wait([
                    ref.read(feedNotifierProvider.notifier).refresh(),
                    ref.read(economyProvider.notifier).refresh(),
                  ]),
          ),
        ],
      ),
      body: ViewTip(
        tipKey: 'tip.feed',
        message: l10n.feedTipMessage,
        child: RefreshIndicator(
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
                        label: l10n.feedAllChannelsChip,
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
                        title: l10n.feedEmptyNoChannelsTitle,
                        subtitle: l10n.feedEmptyNoChannelsSubtitle,
                        actionLabel: l10n.feedEmptyNoChannelsAction,
                        onAction: () => context.go('/channels'),
                      );
                    }
                    if (posts.isEmpty) {
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
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
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
