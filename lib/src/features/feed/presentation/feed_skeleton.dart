import 'package:flutter/material.dart';

import '../../../core/presentation/skeleton.dart';

/// What the feed shows while its first fetch is in flight.
///
/// Deliberately built from the same numbers as [PostCard] — the 12/6 card
/// margin, the 16 padding, the 24dp author avatar, the 40dp action row — so
/// the real cards land into the layout the skeleton was already holding
/// instead of shoving it around. If those numbers change in `post_card.dart`,
/// they have to change here too; a skeleton that no longer matches its card is
/// the one failure mode of this idea.
///
/// Three cards, not a screenful: past the fold nobody is looking, and a
/// shorter list finishes its shimmer sweep as one gesture.
class FeedSkeleton extends StatelessWidget {
  const FeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          _PostCardSkeleton(hasMedia: true),
          _PostCardSkeleton(),
          _PostCardSkeleton(hasMedia: true),
        ],
      ),
    );
  }
}

class _PostCardSkeleton extends StatelessWidget {
  const _PostCardSkeleton({this.hasMedia = false});

  final bool hasMedia;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SkeletonBox.circle(size: 24),
                const SizedBox(width: 8),
                const SkeletonBox(width: 74, height: 11),
                const SizedBox(width: 12),
                const SkeletonBox(width: 52, height: 9),
                const Spacer(),
                const SkeletonBox(width: 30, height: 9),
              ],
            ),
            const SizedBox(height: 14),
            const SkeletonLine(height: 11),
            const SizedBox(height: 7),
            // The second line stops short, the way a wrapped sentence does.
            // Two full-width bars read as a table, not as text.
            const SkeletonLine(widthFactor: 0.62, height: 11),
            if (hasMedia) ...[
              const SizedBox(height: 12),
              // 4:3, the landscape ratio every post image is cropped to
              // (`POST_MEDIA_LANDSCAPE_RATIO`), so the commonest case reserves
              // the right height.
              const AspectRatio(
                aspectRatio: 4 / 3,
                child: SkeletonBox(height: double.infinity, radius: 10),
              ),
            ],
            const SizedBox(height: 14),
            const Row(
              children: [
                Expanded(child: SkeletonBox(height: 40, radius: 12)),
                SizedBox(width: 8),
                Expanded(child: SkeletonBox(height: 40, radius: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
