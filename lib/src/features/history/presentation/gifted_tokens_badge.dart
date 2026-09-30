import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';

/// The small green counter on an own post in the history: how many readers
/// forwarded it with "Forward & gift", handing the author their token.
///
/// A number with a gift glyph and nothing else — the sentence lives in the
/// tooltip, which a tap opens as well as a hover, so it works on a phone. The
/// tap is the tooltip's, not the row's: tapping the badge explains it rather
/// than opening the post.
///
/// Renders nothing for a post without gifts, and for anyone else's post (the
/// server sends [Post.giftedCount] to the author only), so a caller can place
/// it unconditionally.
class GiftedTokensBadge extends StatelessWidget {
  const GiftedTokensBadge({super.key, required this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    if (count == null || count < 1) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final green = theme.colorScheme.primary;

    return Tooltip(
      message: AppLocalizations.of(context).historyGiftedTokens(count),
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: green.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.card_giftcard, size: 12, color: green),
            const SizedBox(width: 3),
            Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: green,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
