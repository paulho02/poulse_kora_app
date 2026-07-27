import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/error_state_view.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../application/feed_providers.dart';
import '../data/post.dart';

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
    // Captured up front: the optimistic removal inside `reviewAndRemove` unmounts
    // this card, so by the time a failure comes back `context` is dead. Reading
    // the messenger now is what lets the error still reach the user.
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _leaving = true;
      _direction = kind == 'forward' ? 1 : -1;
    });

    // Play the exit animation first so the action feels physical, then commit
    // the removal to the provider (which drops it from the underlying list).
    await _exit.forward();

    try {
      await ref
          .read(feedNotifierProvider.notifier)
          .reviewAndRemove(widget.post.id, kind);
    } catch (error) {
      // Say why. Offline is just another error code here — the card returns
      // rather than the review being queued, since the server decides whether a
      // review is still valid (the post may have left this user's queue).
      showErrorSnackBarOn(messenger, error);
      // Roll the card back into view — but only if this state object survived;
      // the rollback in the notifier may have rebuilt a fresh one.
      if (!mounted) return;
      setState(() => _leaving = false);
      _exit.reset();
    }
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
    final post = widget.post;
    final color = AppColors.channelColor(post.channelName);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: () => ref.read(expandedPostIdProvider.notifier).set(post.id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _AuthorAvatar(post: post),
                  const SizedBox(width: 8),
                  Text(
                    post.isAnonymous
                        ? 'Anonymous'
                        : (post.author.username ?? 'Unknown'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontStyle: post.isAnonymous
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('·', style: theme.textTheme.labelSmall),
                  const SizedBox(width: 6),
                  Text(
                    post.channelName,
                    style: theme.textTheme.labelSmall?.copyWith(color: color),
                  ),
                  const Spacer(),
                  Text(
                    _timeAgo(post.created),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                post.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              if (post.hasImage) ...[
                const SizedBox(height: 10),
                Container(
                  height: 80,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text('IMAGE', style: theme.textTheme.labelSmall),
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
                        label: const Text('Forward'),
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
    final progress = post.deadlineProgress;
    final hoursLeft = post.timeRemaining.inHours;
    final radius = BorderRadius.circular(AppTheme.radius);

    return Tooltip(
      message: 'Auto-drops in ${hoursLeft}h',
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
                          'Drop',
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

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    if (post.isAnonymous) {
      return const CircleAvatar(
        radius: 12,
        child: Icon(Icons.person_outline, size: 14),
      );
    }
    final username = post.author.username ?? '?';
    final color = AppColors.avatarColor(username);
    return CircleAvatar(
      radius: 12,
      backgroundColor: color,
      child: Text(
        username.isNotEmpty ? username[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

String _timeAgo(DateTime created) {
  final diff = DateTime.now().toUtc().difference(created.toUtc());
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  return '${diff.inDays}d';
}
