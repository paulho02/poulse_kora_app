import 'package:flutter/material.dart';

import '../data/global_stats.dart';

/// Vertical bar chart of how many posts have been forwarded N times.
/// Mirrors WeeklyActivityChart's plain Row/Container approach — a handful of
/// static bars don't warrant a charting dependency.
class ForwardingDistributionChart extends StatelessWidget {
  const ForwardingDistributionChart({super.key, required this.buckets});

  final List<ForwardingBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxCount = buckets.fold<int>(
      1,
      (max, b) => b.postCount > max ? b.postCount : max,
    );

    return Column(
      children: [
        SizedBox(
          height: 100,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final bucket in buckets)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${bucket.postCount}',
                          style: theme.textTheme.labelSmall,
                        ),
                        const SizedBox(height: 4),
                        FractionallySizedBox(
                          widthFactor: 1,
                          child: SizedBox(
                            height:
                                70 *
                                (bucket.postCount / maxCount).clamp(0.03, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: bucket.postCount == 0 ? 0.2 : 0.8,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final bucket in buckets)
              Expanded(
                child: Text(
                  bucket.label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'forwards per post',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
