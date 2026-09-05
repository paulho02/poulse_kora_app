import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../../core/settings/price_display_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/tips/presentation/view_tip.dart';
import '../../economy/application/economy_providers.dart';
import '../application/channels_providers.dart';
import '../data/channel.dart';
import 'channel_price_label.dart';

class ChannelsScreen extends ConsumerStatefulWidget {
  const ChannelsScreen({super.key});

  @override
  ConsumerState<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends ConsumerState<ChannelsScreen> {
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

    ref.listen<bool>(showChannelPricesProvider, (_, next) => _watchPrices(next));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.channelsTitle),
        actions: [
          // A toggle rather than a permanent column of figures: prices are for
          // the one mode that wants them (see `PriceDisplayStore`), and this is
          // how someone enters and leaves that mode.
          IconButton(
            isSelected: showPrices,
            icon: const Icon(Icons.toll_outlined),
            selectedIcon: const Icon(Icons.toll),
            tooltip: showPrices
                ? l10n.channelsHidePricesTooltip
                : l10n.channelsShowPricesTooltip,
            onPressed: () =>
                ref.read(showChannelPricesProvider.notifier).toggle(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ViewTip(
        tipKey: 'tip.channels',
        message: l10n.channelsTipMessage,
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(channelsNotifierProvider.notifier).refresh(),
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
                                    c.description.toLowerCase().contains(
                                      _query,
                                    ),
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
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => ErrorStateView(
                    error: error,
                    onRetry: () =>
                        ref.read(channelsNotifierProvider.notifier).refresh(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelTile extends ConsumerWidget {
  const _ChannelTile({required this.channel, required this.showPrice});

  final Channel channel;
  final bool showPrice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = AppColors.channelColor(channel.name);
    final l10n = AppLocalizations.of(context);
    return ListTile(
      isThreeLine: showPrice,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Text(
          channel.name.isNotEmpty ? channel.name[0] : '?',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(
        channel.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(channel.description),
          if (showPrice) ChannelPriceLabel(channel: channel),
        ],
      ),
      trailing: FilledButton.tonal(
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
    );
  }
}
