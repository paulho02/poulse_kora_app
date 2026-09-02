import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../application/feed_providers.dart';
import '../data/feed_repository.dart' show PostReviewResult;
import '../data/post.dart';
import 'post_author_avatar.dart';
import 'post_media_thumbnail.dart';

/// Shared height for the Drop / Forward action buttons so they always match.
const double _actionButtonHeight = 40;

class PostCard extends ConsumerStatefulWidget {
  const PostCard({super.key, required this.post});

  final Post post;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  bool _leaving = false;
  // -1 slides the card left (drop), +1 slides it right (forward).
  double _direction = 0;

  @override
  void dispose() {
    _exit.dispose();
    super.dispose();
  }

  Future<void> _review(String kind) async {
    if (_leaving) return;
    // Captured up front: once the review succeeds, the provider drops this
    // post and this card can end up unmounted before the snackbar would be
    // shown for a *later* failure path — reading the messenger now keeps
    // that path working too.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);

    // Disable the buttons immediately, but don't animate yet: the server
    // gets the final say on whether this review is even valid (the post may
    // already have left this user's queue), so the "it flew off the list"
    // animation must not play until that's confirmed.
    setState(() => _leaving = true);

    final PostReviewResult result;
    try {
      result = await ref
          .read(feedNotifierProvider.notifier)
          .reviewPost(widget.post.id, kind);
    } catch (error) {
      showErrorSnackBarOn(messenger, l10n, error);
      if (!mounted) return;
      setState(() => _leaving = false);
      return;
    }

    if (!mounted) return;
    // Confirmed — now it's safe to play the exit animation, then commit the
    // removal to the provider (which drops it from the underlying list).
    setState(() => _direction = kind == 'forward' ? 1 : -1);
    await _exit.forward();
    if (!mounted) return;
    ref
        .read(feedNotifierProvider.notifier)
        .applyReviewResult(widget.post.id, result);
  }

  @override
  Widget build(BuildContext context) {
    final card = _buildCard(context);

    return AnimatedBuilder(
      animation: _exit,
      child: card,
      builder: (context, child) {
        // First ~60% of the timeline slides + fades the card away; the last
        // ~40% collapses its height so the list smoothly closes the gap.
        final slide = Curves.easeIn.transform(
          (_exit.value / 0.6).clamp(0.0, 1.0),
        );
        final collapse = Curves.easeInOut.transform(
          ((_exit.value - 0.6) / 0.4).clamp(0.0, 1.0),
        );

        return Align(
          alignment: Alignment.topCenter,
          heightFactor: 1 - collapse,
          child: Opacity(
            opacity: 1 - slide,
            child: Transform.translate(
              offset: Offset(_direction * slide * 380, 0),
              child: child,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final post = widget.post;
    final color = AppColors.channelColor(post.channelName);
    // Match CardTheme's own base color (see AppTheme._build) rather than
    // leaving `color` null, so the wash below blends onto the *actual* card
    // background instead of compositing over whatever sits behind the card
    // (e.g. scaffoldBackgroundColor), which read as noticeably darker than a
    // normal card.
    final cardBaseColor = theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerHigh
        : theme.colorScheme.surfaceContainerLowest;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      // Supporter posts get a thin accent border plus a faint accent wash —
      // cards are otherwise borderless/neutral (see AppTheme.cardTheme), so
      // this reads as clearly special without introducing a new color or
      // going as loud as a full accent fill.
      color: post.isSupporterPost
          ? Color.alphaBlend(
              theme.colorScheme.primary.withValues(alpha: 0.08),
              cardBaseColor,
            )
          : null,
      shape: post.isSupporterPost
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
            )
          : null,
      child: InkWell(
        onTap: () => ref.read(expandedPostIdProvider.notifier).set(post.id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PostAuthorAvatar(post: post, radius: 12),
                  const SizedBox(width: 8),
                  Text(
                    post.isAnonymous
                        ? l10n.postAnonymous
                        : (post.author.username ?? l10n.postUnknownAuthor),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontStyle: post.isAnonymous
                          ? FontStyle.italic
                          : FontStyle.normal,
                      color: post.isSupporterPost
                          ? theme.colorScheme.primary
                          : null,
                    ),
                  ),
                  if (post.isSupporterPost) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: l10n.postSupporterTooltip,
                      child: Icon(
                        Icons.auto_awesome,
                        size: 12,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Text('·', style: theme.textTheme.labelSmall),
                  const SizedBox(width: 6),
                  Text(
                    post.channelName,
                    style: theme.textTheme.labelSmall?.copyWith(color: color),
                  ),
                  const Spacer(),
                  Text(post.timeAgo, style: theme.textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                post.previewText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              if (post.hasMedia) ...[
                const SizedBox(height: 10),
                Stack(
                  children: [
                    PostMediaThumbnail(media: post.mediaItems.first),
                    if (post.mediaItems.length > 1)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: PostMediaCountBadge(
                          count: post.mediaItems.length - 1,
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  // Drop on the left, Forward on the right — keep the action
                  // sides consistent with the post detail sheet.
                  Expanded(
                    child: _DropButton(
                      post: post,
                      onPressed: _leaving ? null : () => _review('drop'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    // Pin to the same fixed height as the Drop button. The
                    // tight SizedBox + shrinkWrap tap target neutralises the
                    // platform visualDensity, which otherwise shrinks the
                    // FilledButton below the Drop button's 40px.
                    child: SizedBox(
                      height: _actionButtonHeight,
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _leaving ? null : () => _review('forward'),
                        icon: const Icon(Icons.arrow_forward, size: 16),
                        label: Text(l10n.postForward),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Drop button with a built-in "auto-drop" progress fill: the background fills
/// from the left in proportion to how much of the post's 24h review window has
/// elapsed, hinting at when the post will be dropped automatically.
class _DropButton extends StatelessWidget {
  const _DropButton({required this.post, required this.onPressed});

  final Post post;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final progress = post.deadlineProgress;
    final hoursLeft = post.timeRemaining.inHours;
    final radius = BorderRadius.circular(AppTheme.radius);

    return Tooltip(
      message: l10n.postAutoDropsIn(hoursLeft),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: colorScheme.outline),
            ),
            child: SizedBox(
              height: _actionButtonHeight,
              child: Stack(
                children: [
                  // Elapsed-time fill, tinted with the "discard" color.
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: radius,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: progress.clamp(0.0, 1.0),
                          child: ColoredBox(
                            color: colorScheme.error.withValues(alpha: 0.14),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.close,
                          size: 16,
                          color: colorScheme.onSurface,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.postDrop,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
