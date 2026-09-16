import 'package:flutter/material.dart';

import '../../../core/presentation/skeleton.dart';

/// What the channel list shows on a cold load, shaped like [_ChannelTile]:
/// the 12/5 card margin, the 44dp avatar, two stacked lines of text and a
/// join button on the right.
///
/// The price chip under the avatar is deliberately *not* drawn. It only
/// appears when the price switch is on, and a skeleton that promises a control
/// which may never arrive reflows the row the moment the real data lands —
/// which is the one thing a skeleton exists to avoid.
class ChannelsSkeleton extends StatelessWidget {
  const ChannelsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          _ChannelTileSkeleton(nameWidth: 78, descriptionFactor: 0.72),
          _ChannelTileSkeleton(nameWidth: 104, descriptionFactor: 0.55),
          _ChannelTileSkeleton(nameWidth: 66, descriptionFactor: 0.8),
          _ChannelTileSkeleton(nameWidth: 92, descriptionFactor: 0.63),
          _ChannelTileSkeleton(nameWidth: 72, descriptionFactor: 0.7),
        ],
      ),
    );
  }
}

class _ChannelTileSkeleton extends StatelessWidget {
  const _ChannelTileSkeleton({
    required this.nameWidth,
    required this.descriptionFactor,
  });

  /// Varied per row on purpose: five identical placeholders read as a loading
  /// *pattern*, five uneven ones read as a list of differently-named things.
  final double nameWidth;
  final double descriptionFactor;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            const SkeletonBox.circle(size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SkeletonBox(width: nameWidth, height: 12),
                  const SizedBox(height: 8),
                  SkeletonLine(widthFactor: descriptionFactor, height: 10),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const SkeletonBox(width: 72, height: 36, radius: 12),
          ],
        ),
      ),
    );
  }
}
