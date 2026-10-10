import 'package:flutter/material.dart';

import '../../feed/data/post.dart';
import '../../feed/presentation/post_media_thumbnail.dart';
import '../../history/presentation/history_post_detail_view.dart';

/// One post as a compact row on the stats screens: a thumbnail of its first
/// attachment (if any), its channel, two lines of its text, and an optional
/// [trailing] (the view count on an own post).
///
/// Tapping opens the history's read-only detail view rather than the feed's:
/// a post shown here is never one the viewer can still review — their own, or
/// a trending one the server already left out of their queue — so the
/// forward/drop footer has no business appearing.
class StatsPostTile extends StatelessWidget {
  const StatsPostTile({
    super.key,
    required this.post,
    this.showChannel = true,
    this.trailing,
  });

  final Post post;

  /// Off in the per-channel trending list, where the section header already
  /// names the channel.
  final bool showChannel;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = post.mediaItems;
    final text = post.previewText;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showHistoryPostDetail(context, post: post),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            if (media.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.square(
                  dimension: 44,
                  child: PostMediaPreview(media: media.first),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showChannel)
                    Text(
                      post.channelName,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (text.isNotEmpty)
                    Text(
                      text,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}
