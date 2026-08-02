import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../data/user_stats.dart';

/// Plain Row/Container bar chart — 7 static bars don't warrant pulling in a
/// charting dependency.
class WeeklyActivityChart extends StatelessWidget {
  const WeeklyActivityChart({super.key, required this.buckets});

  final List<WeeklyActivityBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final dayLabels = [
      l10n.statsWeekdayMon,
      l10n.statsWeekdayTue,
      l10n.statsWeekdayWed,
      l10n.statsWeekdayThu,
      l10n.statsWeekdayFri,
      l10n.statsWeekdaySat,
      l10n.statsWeekdaySun,
    ];
    final maxCount = buckets.fold<int>(
      1,
      (max, b) => b.count > max ? b.count : max,
    );

    return Column(
      children: [
        SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final bucket in buckets)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: FractionallySizedBox(
                      heightFactor: (bucket.count / maxCount).clamp(0.03, 1.0),
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: bucket.count == 0 ? 0.2 : 0.8,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < buckets.length; i++)
              Expanded(
                child: Text(
                  dayLabels[buckets[i].date.weekday - 1],
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
