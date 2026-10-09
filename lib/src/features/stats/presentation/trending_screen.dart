import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/empty_state.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../channels/presentation/channel_avatar.dart';
import '../application/stats_providers.dart';
import '../data/post_stats.dart';
import 'stats_post_tile.dart';

/// The detailed trending view: each channel's top posts, liveliest channel
/// first (the server's order). Reached from the trending card on the stats
/// screen.
class TrendingScreen extends ConsumerWidget {
  const TrendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final trendingAsync = ref.watch(trendingChannelsProvider);

    Future<void> refresh() async {
      ref.invalidate(trendingChannelsProvider);
      try {
        await ref.read(trendingChannelsProvider.future);
      } catch (_) {
        // Rendered by the `error:` branch below.
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.trendingTitle)),
      body: trendingAsync.when(
        data: (cached) => RefreshIndicator(
          onRefresh: refresh,
          child: cached.data.isEmpty
              ? ScrollableEmptyState(
                  icon: Icons.local_fire_department_outlined,
                  title: l10n.trendingEmpty,
                  subtitle: l10n.trendingEmptySubtitle,
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (cached.staleLabel != null) ...[
                      StaleDataNotice(label: cached.staleLabel!),
                      const SizedBox(height: 12),
                    ],
                    for (final channel in cached.data) ...[
                      _ChannelSection(channel: channel),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(trendingChannelsProvider),
        ),
      ),
    );
  }
}

class _ChannelSection extends StatelessWidget {
  const _ChannelSection({required this.channel});

  final TrendingChannel channel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ChannelAvatar(name: channel.channelName, radius: 14),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    channel.channelName,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final post in channel.posts)
              StatsPostTile(post: post, showChannel: false),
          ],
        ),
      ),
    );
  }
}
