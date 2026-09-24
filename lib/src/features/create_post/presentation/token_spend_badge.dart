import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';

/// How long the spend plays for, and how long it then holds before the
/// composer navigates away. The same shape of pair as
/// `kForwardScorePopIn`/`kForwardScoreHold` in
/// `features/feed/presentation/forward_score_badge.dart` — the two are the same
/// moment on opposite sides of the economy — but the hold here is the longer of
/// the two on purpose: the forward score's number is final the instant it
/// appears, whereas this one is still *falling* when the play ends, so the hold
/// is the only part of the beat where the balance you are left with is readable.
const Duration kTokenSpendPlay = Duration(milliseconds: 1000);
const Duration kTokenSpendHold = Duration(milliseconds: 820);

/// Where in [kTokenSpendPlay] the balance starts falling.
///
/// Everything before this is the pause that makes the effect readable: you see
/// what you had and what it cost, *then* it is taken. A number that starts
/// dropping the instant the "−N" appears reads as one blur with no before.
const double kTokenSpendDropStart = 0.42;

/// The tokens a post just cost, shown over the composer the moment it is
/// published — the balance you had, a red "−N", and then the count falling to
/// what is left.
///
/// The sibling of `ForwardScoreBadge`, and deliberately so: same centred
/// position over the content, same pop-in, same beat before the screen moves
/// on. The two are the only moments in the app where a number the reader cares
/// about changes as a *result* of something they just did, and they should
/// read as the same kind of event — one earns, one spends.
///
/// It is drawn over the composer rather than on the feed's token pill it
/// ultimately changes, because the pill is chrome in the corner: an animation
/// there is over before the eye that was on the Publish button finds it. This
/// plays where the author is already looking.
class TokenSpendBadge extends StatelessWidget {
  const TokenSpendBadge({
    super.key,
    required this.spent,
    required this.balanceBefore,
    required this.animation,
  });

  /// What the post cost. Never zero — the composer does not raise the badge at
  /// all for a free post (a superuser's), since "−0" would be a claim about a
  /// balance that never moved.
  final int spent;

  /// The balance the count starts from; it ends at `balanceBefore - spent`.
  final int balanceBefore;

  /// 0 = absent, 1 = fully played.
  final Animation<double> animation;

  int get _balanceAfter => balanceBefore - spent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Semantics(
      liveRegion: true,
      label: l10n.economySpentAnnouncement(spent),
      // The digits underneath tick through every intermediate value; announced
      // one at a time they would be noise rather than a fact.
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final t = animation.value.clamp(0.0, 1.0);
            // Pop-in is spent entirely in the first quarter, so the count-down
            // happens on a badge that is already settled and still.
            final entry = (t / 0.25).clamp(0.0, 1.0);
            final dropped = t <= kTokenSpendDropStart
                ? 0.0
                : Curves.easeOutCubic.transform(
                    (t - kTokenSpendDropStart) / (1 - kTokenSpendDropStart),
                  );
            final shown =
                (balanceBefore + (_balanceAfter - balanceBefore) * dropped)
                    .round();

            return Opacity(
              opacity: Curves.easeOut.transform(entry),
              child: Transform.scale(
                scale: Curves.elasticOut.transform(entry),
                child: _Badge(
                  balance: shown,
                  spent: spent,
                  // In fast, out slow, and gone before the digits settle — it
                  // is the cause, and should not still be hanging there once
                  // the effect has landed.
                  minusOpacity: t < 0.18
                      ? (t / 0.18).clamp(0.0, 1.0)
                      : (1 - ((t - 0.18) / 0.62)).clamp(0.0, 1.0),
                  minusRise: Curves.easeOut.transform(t),
                  theme: theme,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.balance,
    required this.spent,
    required this.minusOpacity,
    required this.minusRise,
    required this.theme,
  });

  final int balance;
  final int spent;
  final double minusOpacity;
  final double minusRise;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Stack(
      // The "−N" sits above the badge's top edge; clipped it would slide up
      // underneath itself.
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Names what the big number is. Without it the pill is a bare
              // count that could as easily be the post's price — which is the
              // other number on this screen, and the one the "−N" above is.
              Text(
                AppLocalizations.of(context).economySpendBadgeLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.toll_outlined,
                size: 22,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '$balance',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: -18 - 12 * minusRise,
          child: Opacity(
            opacity: minusOpacity,
            child: Text(
              '−$spent',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
