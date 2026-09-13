import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/slide_up_route.dart';
import '../../../core/settings/price_display_settings.dart';
import '../application/economy_providers.dart';

/// The one place the token economy is explained in full sentences.
///
/// It exists so the header pills don't have to. Each pill states only the
/// number its own screen acts on, and defers "but what *are* tokens?" to here,
/// one tap away from either. Which is also why this opens with the live
/// figures: with no bar spelling them out, this is the only screen where the
/// balance and the current price are readable as numbers.
///
/// **A full-screen [slideUpRoute], not a bottom sheet** — the same route a post
/// opens through. As a sheet it was capped at a fraction of the screen while
/// being four paragraphs, a live-figures panel and a switch, so it arrived
/// already scrolled: the reader met a clipped explanation and had to drag a
/// half-height card to finish a page of text that would have fit outright.
/// Explanations are the one thing that must not be read through a letterbox.
Future<void> showEconomyExplainer(BuildContext context) {
  return Navigator.of(context).push<void>(
    slideUpRoute(builder: (context) => const _EconomyExplainerPage()),
  );
}

class _EconomyExplainerPage extends StatelessWidget {
  const _EconomyExplainerPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Same affordance a post detail page gets: the route slid up, so
            // the way back out is to send it down again.
            const SlideDownDismissHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.economyExplainerTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.commonClose,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _LiveFigures(),
                    const SizedBox(height: 20),
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
                    const Divider(height: 24),
                    const _ShowPricesSwitch(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Balance and current price, as sentences rather than a strip of digits.
///
/// Renders nothing if the economy hasn't loaded — the explainer is worth
/// reading on its own and shouldn't turn into an error state.
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  // A range, because there is no single price any more: every
                  // (channel, language) pair is priced by its own congestion.
                  // Where the two ends meet, the single-number sentence still
                  // reads better than "4 to 4 tokens".
                  economy.hasSinglePrice
                      ? l10n.economyExplainerPrice(economy.priceRange.$1)
                      : l10n.economyExplainerPriceRange(
                          economy.priceRange.$1,
                          economy.priceRange.$2,
                        ),
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
/// This page is one tap from the composer's pill, which is what someone is
/// looking at when they find they can't afford the post they just wrote — the
/// exact moment "let me watch the prices while I earn" becomes a thing worth
/// doing. The channels list carries the same switch for turning it back off.
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
      padding: const EdgeInsets.only(bottom: 18),
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
