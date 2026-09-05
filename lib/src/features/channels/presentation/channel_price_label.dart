import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../economy/application/economy_providers.dart';
import '../data/channel.dart';

/// What posting to one channel costs, drawn as **affordability** rather than as
/// a figure.
///
/// The person this is for is not comparison-shopping; they want to post, can't
/// yet, and are reviewing to earn the difference. Their question is "can I
/// afford it now?", and a bare number makes them answer it themselves against a
/// balance that lives on another screen. So the number is stated, then
/// immediately resolved: "3 · Enough to post", or "3 · 2 more tokens to post",
/// in the primary or the muted tone respectively. Glanceable, and it stops
/// being interesting exactly when it stops applying — someone with plenty of
/// tokens sees every row in the ready state and learns to ignore it, which is
/// the correct outcome.
///
/// Renders nothing when the price is unknown ([Channel.postPrice] null, i.e. a
/// list cached before per-channel pricing) or before the economy has loaded:
/// a price with no balance to weigh it against would be the bare figure this
/// widget exists not to show.
class ChannelPriceLabel extends ConsumerWidget {
  const ChannelPriceLabel({required this.channel, super.key});

  final Channel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final price = channel.postPrice;
    final economy = ref.watch(economyProvider)?.data;
    if (price == null || economy == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final canAfford = economy.tokenBalance >= price;
    final needed = (price - economy.tokenBalance).clamp(0, price);

    // The same two clauses the feed pill uses for the same question, so the
    // wording a user learns on one screen is the wording they meet on the other.
    final clause = canAfford
        ? l10n.economyReadyToPost
        : l10n.economyTokensToGo(needed);
    final tone = canAfford
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      label: '${l10n.channelPriceSemantics(price)}. $clause',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.toll_outlined, size: 14, color: tone),
            const SizedBox(width: 5),
            Text(
              '$price',
              style: theme.textTheme.labelMedium?.copyWith(
                color: tone,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                clause,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: tone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
