import 'package:flutter/material.dart';

import '../data/post.dart';
import 'inline_media_block.dart';

/// Renders a post's blocks in order, article-style - a paragraph of text or
/// one image/video at a time, exactly as the author arranged them. Shared
/// between the feed's and history's detail sheets (`post_detail_sheet.dart`,
/// `history_post_detail_sheet.dart`), which otherwise differ only in their
/// header row and action buttons.
class PostBlocksView extends StatelessWidget {
  const PostBlocksView({super.key, required this.blocks});

  final List<PostBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          switch (blocks[i]) {
            PostTextBlock(:final text) => Text(
              text,
              style: theme.textTheme.bodyLarge,
            ),
            PostMediaBlock(:final media) => InlineMediaBlock(media: media),
          },
        ],
      ],
    );
  }
}
