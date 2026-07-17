import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../channels/application/channels_providers.dart';
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

    ref.listen(expandedPostIdProvider, (previous, next) {
      if (next == null) return;
      final matches = feedAsync.value?.where((p) => p.id == next) ?? const [];
      if (matches.isNotEmpty) showPostDetailSheet(context, ref, matches.first);
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(feedAsync.when(
          data: (posts) => 'Feed · ${posts.length} open posts',
          loading: () => 'Feed',
          error: (_, _) => 'Feed',
        )),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(feedNotifierProvider.notifier).refresh(),
        child: Column(
          children: [
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
                      onTap: () => ref.read(selectedChannelFilterProvider.notifier).set(null),
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
                data: (posts) {
                  if (subscribedChannels.isEmpty) {
                    return _EmptyState(
                      icon: Icons.forum_outlined,
                      title: 'Join a channel to get started',
                      subtitle: 'Subscribe to channels to start seeing posts in your feed.',
                      actionLabel: 'Browse channels',
                      onAction: () => context.go('/channels'),
                    );
                  }
                  if (posts.isEmpty) {
                    return const _EmptyState(
                      icon: Icons.check_circle_outline,
                      title: 'All caught up',
                      subtitle: 'No posts to review right now.',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: posts.length,
                    itemBuilder: (context, index) => PostCard(post: posts[index]),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('Could not load feed:\n$error')),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        avatar: color != null
            ? CircleAvatar(backgroundColor: color, radius: 6)
            : null,
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
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
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
