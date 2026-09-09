import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../../core/theme/app_theme.dart';
import '../application/feed_providers.dart';

/// The card in place of a post that no longer exists.
///
/// A queue slot survives its post: the backend's review queue holds ids, and an
/// author erasing their account takes the rows away without going through
/// everybody's queue to tidy up (see the backend's `app/core/account_deletion.py`).
/// So a slot can resolve to nothing, and the honest thing to show is a card
/// saying so rather than silently one fewer post — the reader would otherwise
/// watch their feed stop topping up with no explanation, which is exactly the
/// "is this thing broken?" the self-refreshing feed exists to avoid.
///
/// Three things it deliberately is not:
///
/// - **Not tappable.** There is no detail view to open; the whole content of
///   this card is the sentence on it.
/// - **Not forwardable.** Nothing can be passed on, so the forward button is
///   absent rather than present-and-disabled. A disabled button invites a tap
///   and then explains itself; an absent one says the same thing quietly.
/// - **Not a drop.** The button clears the slot (`DELETE /posts/feed/{id}`) and
///   earns nothing. Nobody read anything, so there is no verdict to record and
///   no token to pay for one — labelling it "Drop" would be claiming a review
///   happened.
///
/// The visual is deliberately flatter than a [PostCard]: no channel colour, no
/// avatar, no deadline fill. It should read as a receipt for something that is
/// gone, not as content competing for a verdict.
class MissingPostCard extends ConsumerStatefulWidget {
  const MissingPostCard({super.key, required this.postId});

  final int postId;

  @override
  ConsumerState<MissingPostCard> createState() => _MissingPostCardState();
}

class _MissingPostCardState extends ConsumerState<MissingPostCard> {
  bool _dismissing = false;

  Future<void> _dismiss() async {
    if (_dismissing) return;
    // Captured before the await: a successful dismiss unmounts this card, and
    // the messenger is still needed on the failure path afterwards.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _dismissing = true);
    try {
      await ref
          .read(feedNotifierProvider.notifier)
          .dismissMissingPost(widget.postId);
    } catch (error) {
      showErrorSnackBarOn(messenger, l10n, error);
      if (!mounted) return;
      setState(() => _dismissing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.help_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.feedMissingPostTitle,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              l10n.feedMissingPostBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _dismissing ? null : _dismiss,
                icon: const Icon(Icons.close, size: 16),
                label: Text(l10n.feedMissingPostDismiss),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
