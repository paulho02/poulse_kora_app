import 'package:flutter/material.dart';

import '../../../core/presentation/skeleton.dart';

/// What the posted/reviewed history shows on a cold load.
///
/// History is a dense list of undivided rows under date headers, so the
/// skeleton has to show *that* — a date header, then a run of rows, then
/// another header. A generic stack of cards would promise the wrong screen.
class HistorySkeleton extends StatelessWidget {
  const HistorySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          _DateHeaderSkeleton(width: 54),
          _RowSkeleton(textFactor: 0.88),
          _RowSkeleton(textFactor: 0.54),
          _RowSkeleton(textFactor: 0.76),
          _DateHeaderSkeleton(width: 82),
          _RowSkeleton(textFactor: 0.66),
          _RowSkeleton(textFactor: 0.91),
          _RowSkeleton(textFactor: 0.48),
        ],
      ),
    );
  }
}

class _DateHeaderSkeleton extends StatelessWidget {
  const _DateHeaderSkeleton({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: SkeletonBox(width: width, height: 12),
    );
  }
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton({required this.textFactor});

  final double textFactor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Channel name on the left, timestamp on the right — the meta row
          // every history tile leads with.
          const Row(
            children: [
              SkeletonBox(width: 62, height: 9),
              Spacer(),
              SkeletonBox(width: 40, height: 9),
            ],
          ),
          const SizedBox(height: 8),
          SkeletonLine(widthFactor: textFactor, height: 11),
        ],
      ),
    );
  }
}
