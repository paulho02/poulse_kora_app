import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../../core/tips/presentation/view_tip.dart';
import '../application/stats_providers.dart';
import '../data/global_stats.dart';
import '../data/user_stats.dart';
import 'forwarding_distribution_chart.dart';
import 'trust_explainer.dart';
import 'weekly_activity_chart.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(statsProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.statsTitle)),
      body: ViewTip(
        tipKey: 'tip.stats',
        message: l10n.statsTipMessage,
        child: statsAsync.when(
          data: (cached) {
            final stats = cached.data;
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(statsProvider);
                ref.invalidate(globalStatsProvider);
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (cached.staleLabel != null) ...[
                    StaleDataNotice(label: cached.staleLabel!),
                    const SizedBox(height: 12),
                  ],
                  _TrustScoreCard(stats: stats),
                  const SizedBox(height: 12),
                  _MetricsGrid(stats: stats),
                  const SizedBox(height: 12),
                  const _GlobalStatsCard(),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.statsThisWeek,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          const SizedBox(height: 16),
                          WeeklyActivityChart(buckets: stats.weeklyActivity),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.statsBadges,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final badge in stats.badges)
                                Chip(
                                  label: Text(badge.label),
                                  backgroundColor: badge.earned
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer
                                      : null,
                                  side: badge.earned
                                      ? null
                                      : BorderSide(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.outlineVariant,
                                          style: BorderStyle.solid,
                                        ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorStateView(
            error: error,
            onRetry: () => ref.invalidate(statsProvider),
          ),
        ),
      ),
    );
  }
}

class _TrustScoreCard extends StatelessWidget {
  const _TrustScoreCard({required this.stats});

  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.statsTrustScore,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                // The same explanation the profile tile opens. Offered in both
                // places because this is a number with a consequence, and the
                // consequence is invisible: a reader whose forwards started
                // reaching fewer people has nothing else to connect that to.
                const TrustInfoButton(),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${stats.trustScore}',
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(width: 6),
                Text(l10n.statsOutOf100, style: theme.textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: stats.trustScore / 100,
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// App-wide stats (not tied to the current user). Loads independently so a
/// failure here doesn't blank out the personal stats above it.
class _GlobalStatsCard extends ConsumerWidget {
  const _GlobalStatsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final globalAsync = ref.watch(globalStatsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.statsAcrossApp, style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(
              l10n.statsForwardingDistribution,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 16),
            globalAsync.when(
              data: (cached) => _GlobalStatsBody(global: cached.data),
              loading: () => const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              ),
              // One card inside a working screen — a full error state would be
              // out of proportion, so it degrades to a quiet line.
              error: (error, _) => SizedBox(
                height: 60,
                child: Center(
                  child: Text(
                    messageFor(l10n, error),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlobalStatsBody extends StatelessWidget {
  const _GlobalStatsBody({required this.global});

  final GlobalStats global;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (global.totalPosts == 0) {
      return SizedBox(
        height: 60,
        child: Center(child: Text(l10n.statsNoPostsYet)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ForwardingDistributionChart(buckets: global.forwardingDistribution),
        const SizedBox(height: 12),
        Text(
          l10n.statsTotalPosts(global.totalPosts),
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.stats});

  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2,
      children: [
        _MetricTile(label: l10n.statsReviewed, value: stats.reviewedCount),
        _MetricTile(label: l10n.statsForwarded, value: stats.forwardedCount),
        _MetricTile(label: l10n.statsDropped, value: stats.droppedCount),
        _MetricTile(label: l10n.statsAvgHops, value: stats.avgHops),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final num value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value', style: theme.textTheme.headlineSmall),
            Text(label, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
