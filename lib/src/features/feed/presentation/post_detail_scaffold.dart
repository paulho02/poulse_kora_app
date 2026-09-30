import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/slide_up_route.dart';
import '../data/post.dart';
import 'post_author_avatar.dart';
import 'post_blocks_view.dart';
import 'probe_marker.dart';

/// The chrome every full-screen post view shares: grab handle, author row,
/// scrolling article body, and an optional pinned footer.
///
/// Both callers — the feed's reviewable post and history's read-only one —
/// used to be near-identical copies that differed only in their footer and one
/// line of metadata; they are the same page with two arguments now.
///
/// **Full screen, not a bottom sheet.** A post is mostly media, and a sheet
/// capped the picture at a fraction of the screen no matter how far it was
/// dragged. The slide-up motion is kept (see [slideUpRoute]) because that part
/// was right.
///
/// Two things follow from having the whole screen:
/// - Media is **full-bleed**: text keeps its reading margin, images and video
///   run edge to edge (see [PostBlocksView]'s `fullBleed`), which is the entire
///   point of the change.
/// - The footer is **pinned**, not appended after the article. Drop/forward
///   used to sit below the body, so acting on a long post meant scrolling to
///   the end of something you had already decided about.
class PostDetailScaffold extends StatelessWidget {
  const PostDetailScaffold({
    super.key,
    required this.post,
    required this.metaLine,
    this.footer,
    this.progress,
    this.metaTrailing,
  });

  final Post post;

  /// The line under the author's name — channel, age, and whatever else the
  /// caller's context makes relevant (review deadline, or when it was reviewed).
  final String metaLine;

  /// Pinned to the bottom of the screen, above the safe area. Null for a
  /// read-only view.
  final Widget? footer;

  /// Optional 0..1 bar drawn just above [footer].
  final double? progress;

  /// A small marker after [metaLine] that only one caller has reason to show —
  /// the history's gift counter on the author's own post.
  final Widget? metaTrailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SlideDownDismissHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 12),
              child: Row(
                children: [
                  PostAuthorAvatar(post: post, radius: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                post.isAnonymous
                                    ? l10n.postAnonymous
                                    : (post.author.username ??
                                          l10n.postUnknownAuthor),
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: post.isSupporterPost
                                      ? theme.colorScheme.primary
                                      : null,
                                ),
                              ),
                            ),
                            if (post.isSupporterPost) ...[
                              const SizedBox(width: 6),
                              const _SupporterBadge(),
                            ],
                          ],
                        ),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                metaLine,
                                style: theme.textTheme.labelSmall,
                              ),
                            ),
                            // Placed here rather than in each caller so every
                            // way of opening a post - the feed, history, the
                            // composer's preview - marks a check identically.
                            // A check that showed its mark in one view and not
                            // another would teach readers to check the view.
                            if (post.isProbe) ...[
                              const SizedBox(width: 6),
                              const ProbeMarker(),
                            ],
                            if (metaTrailing != null) ...[
                              const SizedBox(width: 8),
                              metaTrailing!,
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: l10n.postDetailCloseTooltip,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  // No horizontal padding on the list: PostBlocksView indents
                  // the text itself so media can reach both edges.
                  PostBlocksView(blocks: post.blocks, fullBleed: true),
                ],
              ),
            ),
            if (progress != null)
              LinearProgressIndicator(value: progress, minHeight: 3),
            if (footer != null)
              Material(
                color: theme.colorScheme.surface,
                elevation: 3,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: footer,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Spelled out here (not just the icon used on the feed card) since this is the
/// one place worth a beat of explanation for what the sparkle means.
class _SupporterBadge extends StatelessWidget {
  const _SupporterBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 12, color: theme.colorScheme.primary),
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
    );
  }
}
