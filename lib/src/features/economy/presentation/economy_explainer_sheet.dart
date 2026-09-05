import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/settings/price_display_settings.dart';
import '../application/economy_providers.dart';

/// The one place the token economy is explained in full sentences.
///
/// It exists so the header pills don't have to. The economy used to be a
/// full-width bar on both screens carrying the whole model — balance, price and
/// a countdown — which is a lot of permanent chrome for something you consult a
/// few times a day. Each pill now states only the number its own screen acts
/// on, and defers "but what *are* tokens?" to here, one tap away from either.
///
/// Which is why this sheet opens with the live figures: with no bar spelling
/// them out, this is the only screen where the balance and the current price
/// are readable as numbers rather than inferred from a progress bar.
Future<void> showEconomyExplainerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      final l10n = AppLocalizations.of(context);
      return SafeArea(
        // Scrollable rather than a plain column: a default sheet is capped at a
        // fraction of the screen, and this one is four paragraphs that grow
        // with the reader's text scale — short screens and large type were
        // clipping the last point off the bottom.
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(
                l10n.economyExplainerTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const _LiveFigures(),
              const SizedBox(height: 16),
              _Point(
                icon: Icons.add_circle_outline,
                text: l10n.economyExplainerEarn,
              ),
              _Point(
                icon: Icons.sell_outlined,
                text: l10n.economyExplainerCost,
              ),
              _Point(
                icon: Icons.tag,
                text: l10n.economyExplainerPerChannel,
              ),
              _Point(
                icon: Icons.timer_outlined,
                text: l10n.economyExplainerLock,
              ),
              const _ShowPricesSwitch(),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonGotIt),
                ),
              ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Balance and current price, as sentences rather than a strip of digits.
///
/// Renders nothing if the economy hasn't loaded — the sheet is reachable from a
/// pill that only exists once it has, but the explainer is worth reading on its
/// own and shouldn't turn into an error state.
class _LiveFigures extends ConsumerWidget {
  const _LiveFigures();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cached = ref.watch(economyProvider);
    if (cached == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final economy = cached.data;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.toll_outlined, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.economyExplainerBalance(economy.tokenBalance),
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  l10n.economyExplainerPrice(economy.postPrice),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The switch for channel prices, offered here rather than buried in Settings.
///
/// This sheet is one tap from the composer's pill, which is what someone is
/// looking at when they find they can't afford the post they just wrote — the
/// exact moment "let me watch the prices while I earn" becomes a thing worth
/// doing. Settings would be the discoverable-by-nobody place to put it; the
/// channels list has the same switch in its app bar for turning it back off.
class _ShowPricesSwitch extends ConsumerWidget {
  const _ShowPricesSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return SwitchListTile(
      value: ref.watch(showChannelPricesProvider),
      onChanged: (value) =>
          ref.read(showChannelPricesProvider.notifier).set(value),
      title: Text(l10n.economyShowPricesTitle),
      subtitle: Text(l10n.economyShowPricesSubtitle),
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
