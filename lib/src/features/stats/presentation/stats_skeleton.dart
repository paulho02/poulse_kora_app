import 'package:flutter/material.dart';

import '../../../core/presentation/skeleton.dart';

/// What the stats screen shows on a cold load: the trust card, the 2x2 metric
/// grid and the two chart cards, in their real proportions.
///
/// Stats is the screen where a spinner cost the most. Every one of these cards
/// is a fixed, known shape — the layout is the *same* every time, only the
/// numbers change — so there was never any reason to withhold it.
class StatsSkeleton extends StatelessWidget {
  const StatsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // Trust: label, the big number, the progress bar.
          const _CardSkeleton(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 80, height: 10),
                SizedBox(height: 14),
                SkeletonBox(width: 118, height: 34, radius: 8),
                SizedBox(height: 16),
                SkeletonBox(height: 6, radius: 3),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2,
            children: List.filled(4, const _MetricTileSkeleton()),
          ),
          const SizedBox(height: 12),
          const _CardSkeleton(child: _ChartSkeleton()),
          const SizedBox(height: 12),
          const _CardSkeleton(child: _ChartSkeleton()),
        ],
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
  }
}

class _MetricTileSkeleton extends StatelessWidget {
  const _MetricTileSkeleton();

  @override
  Widget build(BuildContext context) {
    // Icon disc on the left, number over label on the right — see
    // `_MetricTile` in `stats_screen.dart`.
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            SkeletonBox.circle(size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SkeletonBox(width: 40, height: 20, radius: 6),
                  SizedBox(height: 6),
                  SkeletonBox(width: 58, height: 9),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A label line over a row of bars — close enough to both charts on this
/// screen (`WeeklyActivityChart`, `ForwardingDistributionChart`) that either
/// can land into it without the card resizing.
class _ChartSkeleton extends StatelessWidget {
  const _ChartSkeleton();

  @override
  Widget build(BuildContext context) {
    // Uneven heights, so it reads as a chart rather than as a loading bar.
    const heights = [34.0, 58.0, 26.0, 70.0, 44.0, 62.0, 30.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkeletonBox(width: 92, height: 10),
        const SizedBox(height: 20),
        SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final height in heights) ...[
                Expanded(child: SkeletonBox(height: height, radius: 4)),
                if (height != heights.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
