import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../feed/data/post.dart';
import '../../feed/presentation/post_author_avatar.dart';
import '../../feed/presentation/post_blocks_view.dart';

/// Read-only counterpart of the feed's `_PostDetailSheet` (see
/// `feed/presentation/post_detail_sheet.dart`) for posts shown in a history
/// list: no drop/forward actions and no review-deadline bar, since a history
/// entry is already published/already reviewed rather than sitting in the
/// active queue.
void showHistoryPostDetailSheet(
  BuildContext context, {
  required Post post,
  String? reviewKindLabel,
  DateTime? reviewedAt,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    // See the feed's showPostDetailSheet for why DraggableScrollableSheet:
    // scrollable content plus room to drag the sheet taller than its default
    // wrap-content height.
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => _HistoryPostDetailSheet(
        post: post,
        reviewKindLabel: reviewKindLabel,
        reviewedAt: reviewedAt,
        scrollController: scrollController,
      ),
    ),
  );
}

String _relativeAgo(DateTime dt) {
  final diff = DateTime.now().toUtc().difference(dt.toUtc());
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  return '${diff.inDays}d';
}

class _HistoryPostDetailSheet extends StatelessWidget {
  const _HistoryPostDetailSheet({
    required this.post,
    required this.scrollController,
    this.reviewKindLabel,
    this.reviewedAt,
  });

  final Post post;
  final ScrollController scrollController;
  final String? reviewKindLabel;
  final DateTime? reviewedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final postedAgoRaw = _relativeAgo(post.created);
    final postedAgo = postedAgoRaw == 'now'
        ? l10n.postJustNow
        : l10n.postTimeAgoSuffix(postedAgoRaw);

    return SafeArea(
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.postDetailHeader,
                  style: theme.textTheme.labelSmall,
                ),
              ),
              Tooltip(
                message: l10n.postDetailCloseTooltip,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  customBorder: const CircleBorder(),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              PostAuthorAvatar(post: post, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          post.isAnonymous
                              ? l10n.postAnonymous
                              : (post.author.username ??
                                    l10n.postUnknownAuthor),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: post.isSupporterPost
                                ? theme.colorScheme.primary
                                : null,
                          ),
                        ),
                        if (post.isSupporterPost) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 12,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  l10n.postSupporterBadge,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${post.channelName} · ${l10n.postDetailPostedAgo(postedAgo)}',
                      style: theme.textTheme.labelSmall,
                    ),
                    if (reviewKindLabel != null && reviewedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '$reviewKindLabel · '
                        '${l10n.historyDetailReviewedAgo(_reviewedAgoText(l10n, reviewedAt!))}',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          PostBlocksView(blocks: post.blocks),
        ],
      ),
    );
  }

  String _reviewedAgoText(AppLocalizations l10n, DateTime dt) {
    final raw = _relativeAgo(dt);
    return raw == 'now' ? l10n.postJustNow : l10n.postTimeAgoSuffix(raw);
  }
}
