import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/speech_bubble_tooltip.dart';
import '../application/economy_providers.dart';

/// Slim header bar showing the viewer's spendable token balance and the current
/// price to publish a post. Not real-time — the hosting screen seeds it via
/// `economyProvider.notifier.ensureLoaded()` and it refreshes on review/post
/// actions, pull-to-refresh, and whenever the quoted price's guarantee window
/// (see `_PriceWithCountdown`) runs out. Renders nothing until the economy has
/// loaded.
class EconomyStatusBar extends ConsumerWidget {
  const EconomyStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cached = ref.watch(economyProvider);
    if (cached == null) return const SizedBox.shrink();
    final economy = cached.data;

    final theme = Theme.of(context);
    final expiresAt = economy.postPriceExpiresAt;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          _Stat(
            icon: Icons.toll_outlined,
            label:
                '${economy.tokenBalance} '
                'token${economy.tokenBalance == 1 ? '' : 's'}',
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 20),
          if (expiresAt != null)
            _PriceWithCountdown(
              price: economy.postPrice,
              isStale: cached.isStale,
              canAfford: economy.canAffordPost,
              expiresAt: expiresAt,
            )
          else
            _Stat(
              icon: Icons.sell_outlined,
              label: cached.isStale
                  ? '~${economy.postPrice} to post'
                  : '${economy.postPrice} to post',
              color: economy.canAffordPost
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.error,
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Price and its countdown as a single pill, so the two read as one fact
/// ("this price, guaranteed for this long") rather than two unrelated stats
/// that happen to sit next to each other. Tapping anywhere in the pill shows
/// the explainer tooltip.
///
/// Once the countdown hits zero, keeps polling `economyProvider.refresh()`
/// (throttled) instead of just freezing on "0:00" — a stale price is worse
/// than a short loading blip, and this way the bar heals itself without the
/// user having to pull-to-refresh.
class _PriceWithCountdown extends ConsumerStatefulWidget {
  const _PriceWithCountdown({
    required this.price,
    required this.isStale,
    required this.canAfford,
    required this.expiresAt,
  });

  final int price;
  final bool isStale;
  final bool canAfford;
  final DateTime expiresAt;

  @override
  ConsumerState<_PriceWithCountdown> createState() =>
      _PriceWithCountdownState();
}

class _PriceWithCountdownState extends ConsumerState<_PriceWithCountdown> {
  Timer? _timer;
  late Duration _remaining;
  DateTime? _lastRefreshAttempt;

  @override
  void initState() {
    super.initState();
    _remaining = _timeLeft();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    if (_remaining <= Duration.zero) _maybeRefresh();
  }

  @override
  void didUpdateWidget(covariant _PriceWithCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A single perpetual timer (below) already re-derives `_remaining` from
    // `widget.expiresAt` every tick, so nothing needs restarting here — this
    // just avoids up to a 1s stale flash right after a fetch lands.
    if (oldWidget.expiresAt != widget.expiresAt) {
      setState(() => _remaining = _timeLeft());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Duration _timeLeft() {
    final left = widget.expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _remaining = _timeLeft());
    if (_remaining <= Duration.zero) _maybeRefresh();
  }

  /// Throttled rather than fire-once: `EconomyNotifier.refresh()` swallows
  /// connectivity failures, so a one-shot attempt could leave an offline user
  /// stuck on the loading state forever with nothing to retry it.
  void _maybeRefresh() {
    final now = DateTime.now();
    if (_lastRefreshAttempt != null &&
        now.difference(_lastRefreshAttempt!) < const Duration(seconds: 5)) {
      return;
    }
    _lastRefreshAttempt = now;
    ref.read(economyProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priceColor = widget.canAfford
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.error;
    final priceLabel = widget.isStale
        ? '~${widget.price} to post'
        : '${widget.price} to post';

    final expired = _remaining <= Duration.zero;
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;
    final countdownLabel = '$minutes:${seconds.toString().padLeft(2, '0')}';

    return SpeechBubbleTooltip(
      message: expired
          ? "The price just expired — refreshing it now."
          : 'The price to post rises when the app is busy. '
                "It's locked in for $countdownLabel — after that it may change.",
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sell_outlined, size: 16, color: priceColor),
            const SizedBox(width: 6),
            Text(
              priceLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: priceColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                width: 1,
                height: 12,
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            if (expired)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(
                    theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else ...[
              Icon(
                Icons.timer_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                countdownLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
