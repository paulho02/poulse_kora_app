import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../economy/presentation/economy_explainer.dart';
import '../data/channel.dart';

/// What posting to one channel costs: a token glyph and a number, under the
/// channel's badge.
///
/// This deliberately does **not** resolve the price against the balance the way
/// it once did ("3 · Enough to post"). Two clauses per row turned a list of
/// channels into a column of sentences, and the affordability question is
/// already answered — continuously, on every screen — by the token pill in the
/// app bar. Here the price is a property of the channel, sitting with the
/// channel's other identity, and it stays a figure.
///
/// It is tappable for the same reason the pill is: a number with no model
/// behind it is trivia, and [showEconomyExplainer] is where the model lives.
/// Tapping must not select the channel, which is why this sits in its own
/// [InkWell] above the row's — the gesture arena gives it to the innermost hit,
/// so the chip wins its own taps and the row keeps the rest.
///
/// Shows a **range** rather than one number, because a channel is several
/// routes — one per content language, plus the no-language one — each priced by
/// its own congestion. The exact charge only exists once the author has also
/// picked a language, which happens in the composer. Where the range collapses
/// to a single number it is drawn as one, since "4–4" reads as a bug.
///
/// Renders nothing when the price is unknown ([Channel.postPriceMin] null, i.e.
/// a list cached before this existed): null means unknown, never free.
class ChannelPriceChip extends StatelessWidget {
  const ChannelPriceChip({super.key, required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final low = channel.postPriceMin;
    final high = channel.postPriceMax;
    if (low == null || high == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isSingle = channel.hasSinglePrice;
    final text = isSingle ? '$low' : l10n.channelPriceRange(low, high);

    return Semantics(
      button: true,
      label: isSingle
          ? l10n.channelPriceSemantics(low)
          : l10n.channelPriceRangeSemantics(low, high),
      excludeSemantics: true,
      child: Material(
        // Outlined rather than bare text: a number under an avatar reads as a
        // caption, and nothing about a caption invites a tap. The border is
        // what makes it look like the control it is — the same stadium shape
        // the economy pills use, so the two tappable price surfaces in the app
        // are recognisably the same kind of thing. Carried by the `shape` so
        // the ink splash is clipped to it instead of spilling square.
        color: theme.colorScheme.surfaceContainerHighest,
        shape: StadiumBorder(
          side: BorderSide(color: theme.colorScheme.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showEconomyExplainer(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.toll_outlined,
                  size: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 3),
                Text(
                  text,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
