import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/error_state_view.dart';
import '../application/feed_providers.dart';
import '../data/post.dart';
import 'post_author_avatar.dart';

void showPostDetailSheet(BuildContext context, WidgetRef ref, Post post) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _PostDetailSheet(post: post),
  ).whenComplete(() => ref.read(expandedPostIdProvider.notifier).set(null));
}

class _PostDetailSheet extends ConsumerWidget {
  const _PostDetailSheet({required this.post});

  final Post post;

  Future<void> _review(BuildContext context, WidgetRef ref, String kind) async {
    // Grab the messenger before popping: afterwards this sheet's context is
    // defunct, and a `context.mounted` check would just swallow the error.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    Navigator.of(context).pop();
    try {
      await ref
          .read(feedNotifierProvider.notifier)
          .reviewAndRemove(post.id, kind);
    } catch (error) {
      showErrorSnackBarOn(messenger, l10n, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final hoursLeft = post.timeRemaining.inHours;
    final postedAgo = post.timeAgo == 'now'
        ? l10n.postJustNow
        : l10n.postTimeAgoSuffix(post.timeAgo);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.postDetailHeader, style: theme.textTheme.labelSmall),
            const SizedBox(height: 16),
            Row(
              children: [
                PostAuthorAvatar(post: post, radius: 20),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          post.isAnonymous
                              ? l10n.postAnonymous
                              : (post.author.username ?? l10n.postUnknownAuthor),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: post.isSupporterPost
                                ? theme.colorScheme.primary
                                : null,
                          ),
                        ),
                        // Spelled out here (not just the icon used on the feed
                        // card) since this is the one place worth a beat of
                        // explanation for what the sparkle means.
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
                      '${post.channelName} · ${l10n.postDetailPostedAgo(postedAgo)} · '
                      '${l10n.postDetailHoursLeft(hoursLeft)}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(post.text, style: theme.textTheme.bodyLarge),
            if (post.hasImage) ...[
              const SizedBox(height: 20),
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  l10n.postPhotoPlaceholder,
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: post.deadlineProgress,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _review(context, ref, 'drop'),
                    icon: const Icon(Icons.close),
                    label: Text(l10n.postDrop),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _review(context, ref, 'forward'),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(l10n.postForward),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
