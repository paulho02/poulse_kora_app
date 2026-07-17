import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/stats_providers.dart';
import '../data/user_stats.dart';
import 'weekly_activity_chart.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(statsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: statsAsync.when(
        data: (stats) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(statsProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _TrustScoreCard(stats: stats),
              const SizedBox(height: 12),
              _MetricsGrid(stats: stats),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('THIS WEEK', style: Theme.of(context).textTheme.labelSmall),
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
                      Text('BADGES', style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final badge in stats.badges)
                            Chip(
                              label: Text(badge.label),
                              backgroundColor: badge.earned
                                  ? Theme.of(context).colorScheme.primaryContainer
                                  : null,
                              side: badge.earned
                                  ? null
                                  : BorderSide(
                                      color: Theme.of(context).colorScheme.outlineVariant,
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
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load stats:\n$error')),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TRUST SCORE', style: theme.textTheme.labelSmall),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('${stats.trustScore}', style: theme.textTheme.displaySmall),
                const SizedBox(width: 6),
                Text('/ 100', style: theme.textTheme.labelMedium),
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

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.stats});

  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2,
      children: [
        _MetricTile(label: 'Reviewed', value: stats.reviewedCount),
        _MetricTile(label: 'Forwarded', value: stats.forwardedCount),
        _MetricTile(label: 'Dropped', value: stats.droppedCount),
        _MetricTile(label: 'Avg Hops', value: stats.avgHops),
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
