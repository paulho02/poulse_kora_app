import 'package:flutter/material.dart';

import '../../../core/presentation/skeleton.dart';

/// What the profile shows on a cold load: the centred avatar block, the row of
/// three stat tiles, and the two setting cards under it.
///
/// The avatar circle matters more here than anywhere else in the app. It is
/// the largest single element on the screen, and a spinner in its place meant
/// the whole page shifted down the moment the profile arrived.
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          Center(
            child: Column(
              children: [
                SkeletonBox.circle(size: 96),
                SizedBox(height: 16),
                SkeletonBox(width: 136, height: 18, radius: 9),
                SizedBox(height: 10),
                SkeletonBox(width: 196, height: 11),
              ],
            ),
          ),
          SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _StatTileSkeleton()),
              Expanded(child: _StatTileSkeleton()),
              Expanded(child: _StatTileSkeleton()),
            ],
          ),
          SizedBox(height: 24),
          _RowCardSkeleton(),
          SizedBox(height: 8),
          _RowCardSkeleton(),
        ],
      ),
    );
  }
}

class _StatTileSkeleton extends StatelessWidget {
  const _StatTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            SkeletonBox(width: 34, height: 22, radius: 6),
            SizedBox(height: 8),
            SkeletonBox(width: 50, height: 9),
          ],
        ),
      ),
    );
  }
}

/// A `ListTile`-shaped card: leading icon, one line of label.
class _RowCardSkeleton extends StatelessWidget {
  const _RowCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            SkeletonBox(width: 22, height: 22, radius: 6),
            SizedBox(width: 18),
            Expanded(child: SkeletonLine(widthFactor: 0.45, height: 12)),
          ],
        ),
      ),
    );
  }
}
