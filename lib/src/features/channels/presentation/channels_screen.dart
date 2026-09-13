import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../../core/settings/price_display_settings.dart';
import '../../economy/application/economy_providers.dart';
import '../application/channels_providers.dart';
import '../data/channel.dart';
import 'channel_avatar.dart';
import 'channel_price_chip.dart';

/// The channel list, as one tab of `FeedPreferencesScreen`.
///
/// Deliberately no `Scaffold` or `AppBar` of its own: it is a tab body now, and
/// the shell owns the bar (including the price switch, which it shows only
/// while this tab is the one on screen — see `ChannelPriceSwitchAction`).
class ChannelsTab extends ConsumerStatefulWidget {
  const ChannelsTab({super.key});

  @override
  ConsumerState<ChannelsTab> createState() => _ChannelsTabState();
}

class _ChannelsTabState extends ConsumerState<ChannelsTab> {
  final _searchController = TextEditingController();
  String _query = '';

  /// Runs only while prices are on screen — see [_refreshIfLapsed].
  Timer? _priceTimer;
  DateTime? _lastPriceRefresh;

  @override
  void initState() {
    super.initState();
    // Deferred like the composer's own economy load: `ensureLoaded` sets
    // provider state, which must not happen while the tree is still building.
    Future.microtask(() {
      if (mounted) _watchPrices(ref.read(showChannelPricesProvider));
    });
  }

  @override
  void dispose() {
    _priceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Start or stop following the price, as the switch is flipped.
  ///
  /// Nothing here runs for the default (off) case: someone browsing channels
  /// pays neither the economy fetch nor the timer.
  void _watchPrices(bool showPrices) {
    if (!showPrices) {
      _priceTimer?.cancel();
      _priceTimer = null;
      return;
    }
    ref.read(economyProvider.notifier).ensureLoaded();
    _priceTimer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshIfLapsed(),
    );
  }

  /// Re-fetch once the quoted price window has actually passed.
  ///
  /// This is the whole point of leaving prices on: the user is reviewing to
  /// earn their way to a post, and a board frozen at the figures from whenever
  /// they opened the screen would answer the wrong question. The backend states
  /// exactly when its quote stops holding (`post_price_expires_at`), so this
  /// follows that rather than polling on a guess — the 5s tick only decides how
  /// promptly a lapse is noticed.
  void _refreshIfLapsed() {
    if (!mounted) return;
    final expiresAt = ref.read(economyProvider)?.data.postPriceExpiresAt;
    if (expiresAt == null || DateTime.now().isBefore(expiresAt)) return;

    // Throttled for the offline case, where nothing will move the expiry along
    // and every tick would otherwise be a fresh attempt.
    final now = DateTime.now();
    final last = _lastPriceRefresh;
    if (last != null && now.difference(last) < const Duration(seconds: 15)) {
      return;
    }
    _lastPriceRefresh = now;
    ref.read(economyProvider.notifier).refresh();
    ref.read(channelsNotifierProvider.notifier).refreshPrices();
  }

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(channelsNotifierProvider);
    final showPrices = ref.watch(showChannelPricesProvider);
    final l10n = AppLocalizations.of(context);

    ref.listen<bool>(
      showChannelPricesProvider,
      (_, next) => _watchPrices(next),
    );

    return RefreshIndicator(
      onRefresh: () => ref.read(channelsNotifierProvider.notifier).refresh(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.channelsSearchHint,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.toLowerCase()),
            ),
          ),
          Expanded(
            child: channelsAsync.when(
              data: (cached) {
                final channels = cached.data;
                final filtered = _query.isEmpty
                    ? channels
                    : channels
                          .where(
                            (c) =>
                                c.name.toLowerCase().contains(_query) ||
                                c.description.toLowerCase().contains(_query),
                          )
                          .toList();
                return Column(
                  children: [
                    if (cached.staleLabel != null)
                      StaleDataNotice(label: cached.staleLabel!),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(child: Text(l10n.channelsNoneFound))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) => _ChannelTile(
                                channel: filtered[index],
                                showPrice: showPrices,
                              ),
                            ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ErrorStateView(
                error: error,
                onRetry: () =>
                    ref.read(channelsNotifierProvider.notifier).refresh(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The price mode switch, in the app bar.
///
/// Public because the bar belongs to `FeedPreferencesScreen` now, which shows
/// this only while the channels tab is selected — the switch is about the
/// channel list and would be a control with no subject on the languages tab.
///
/// It replaced an `isSelected` IconButton there — a coin glyph toggling between
/// filled and outlined said nothing about what it did, and the only thing
/// naming it was a tooltip, which on touch needs a long press nobody performs.
/// A real switch with a word beside it says both what it is and which way it is
/// set, at a glance.
///
/// It stays in the header rather than becoming a row over the list: it is
/// chrome *about* the list, and a full-width `SwitchListTile` under the search
/// field spent a whole line of the screen with the least to spare on a control
/// that is off by default and touched rarely — the same trade the economy bars
/// lost when they became pills.
///
/// The tooltip is back, but as a second name rather than the only one: the
/// visible word does the everyday job, and the full sentence is what a screen
/// reader announces and what a long press reveals.
class ChannelPriceSwitchAction extends StatelessWidget {
  const ChannelPriceSwitchAction({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Tooltip(
      message: l10n.channelsShowPricesHint,
      child: Semantics(
        toggled: value,
        label: l10n.channelsShowPricesHint,
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.channelsShowPricesLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            // A Switch is sized for a settings row and would set the toolbar's
            // height on its own; scaled down it keeps the affordance without
            // making the app bar taller than every other screen's.
            Transform.scale(
              scale: 0.75,
              child: Switch(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}

/// One channel, as a card rather than a `ListTile`.
///
/// The list used to be undivided tiles, which at three lines each ran together
/// into one column of text — a channel is a *thing* you join, not a row in a
/// settings table, and the rest of the app already says so with cards (see
/// `PostCard`). Same margin and radius as a feed card, so the two screens read
/// as one product.
///
/// The price sits under the badge rather than beside the description: it
/// belongs to the channel's identity, not to its sentence, and stacking it
/// there keeps the description on one line at any text scale.
class _ChannelTile extends ConsumerWidget {
  const _ChannelTile({required this.channel, required this.showPrice});

  final Channel channel;
  final bool showPrice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ChannelAvatar(name: channel.name),
                if (showPrice) ...[
                  const SizedBox(height: 4),
                  ChannelPriceChip(channel: channel),
                ],
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    channel.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    channel.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.tonal(
              onPressed: () async {
                try {
                  await ref
                      .read(channelsNotifierProvider.notifier)
                      .toggleSubscription(channel);
                } catch (error) {
                  if (context.mounted) {
                    showErrorSnackBar(context, error);
                  }
                }
              },
              child: Text(
                channel.isSubscribed
                    ? l10n.channelsJoinedButton
                    : l10n.channelsJoinButton,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
