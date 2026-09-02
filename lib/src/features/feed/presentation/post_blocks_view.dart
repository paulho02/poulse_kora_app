import 'package:flutter/material.dart';

import '../data/post.dart';
import 'inline_media_block.dart';

/// Horizontal margin kept around a post's text so it reads as prose rather than
/// spanning the full width of a phone. Media deliberately ignores it.
const double _kTextInset = 20;

/// Renders a post's blocks in order, article-style - a paragraph of text or
/// one image/video at a time, exactly as the author arranged them. Shared
/// between the feed's and history's detail views (`post_detail_view.dart`,
/// `history_post_detail_view.dart`), which otherwise differ only in their
/// footer.
///
/// With [fullBleed], text is inset and media runs edge to edge with square
/// corners — what a full-screen post view wants, and the reason it stopped being
/// a bottom sheet. Without it, everything sits inline in whatever padding the
/// parent supplies and media keeps its rounded card corners.
class PostBlocksView extends StatelessWidget {
  const PostBlocksView({
    super.key,
    required this.blocks,
    this.fullBleed = false,
  });

  final List<PostBlock> blocks;
  final bool fullBleed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          switch (blocks[i]) {
            PostTextBlock(:final text) => Padding(
              padding: EdgeInsets.symmetric(
                horizontal: fullBleed ? _kTextInset : 0,
              ),
              child: Text(text, style: theme.textTheme.bodyLarge),
            ),
            PostMediaBlock(:final media) => InlineMediaBlock(
              media: media,
              borderRadius: fullBleed ? 0 : 12,
            ),
          },
        ],
      ],
    );
  }
}
