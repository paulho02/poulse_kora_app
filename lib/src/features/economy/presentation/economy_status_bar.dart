import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/economy_providers.dart';

/// Slim header bar showing the viewer's spendable token balance and the current
/// price to publish a post. Not real-time — the hosting screen seeds it via
/// `economyProvider.notifier.ensureLoaded()` and it refreshes on review/post
/// actions and pull-to-refresh. Renders nothing until the economy has loaded.
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
          _Stat(
            icon: Icons.sell_outlined,
            // The price tracks live operation-queue congestion, so a cached one
            // is an indication rather than a quote — mark it instead of
            // presenting a stale number as the current cost.
            label: cached.isStale
                ? '~${economy.postPrice} to post'
                : '${economy.postPrice} to post',
            color: economy.canAffordPost
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.error,
          ),
          if (expiresAt != null) ...[
            const SizedBox(width: 20),
            _PriceCountdown(expiresAt: expiresAt),
          ],
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

/// Ticking countdown to `expiresAt`, tap-to-reveal a tooltip explaining what it
/// means. Renders nothing once expired rather than showing a stuck "0:00" —
/// that also covers a stale cached economy, whose `expiresAt` is already in
/// the past the moment it loads.
class _PriceCountdown extends StatefulWidget {
  const _PriceCountdown({required this.expiresAt});

  final DateTime expiresAt;

  @override
  State<_PriceCountdown> createState() => _PriceCountdownState();
}

class _PriceCountdownState extends State<_PriceCountdown> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = _timeLeft();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _PriceCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expiresAt != widget.expiresAt) {
      _remaining = _timeLeft();
      _startTimer();
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

  void _startTimer() {
    _timer?.cancel();
    if (_remaining <= Duration.zero) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _timeLeft();
      if (!mounted) return;
      setState(() => _remaining = left);
      if (left <= Duration.zero) _timer?.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining <= Duration.zero) return const SizedBox.shrink();
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;
    final label = '$minutes:${seconds.toString().padLeft(2, '0')}';

    return Tooltip(
      // Default Tooltip only shows on long-press on mobile; this is meant to be
      // discoverable with a plain tap, since nothing else hints it's tappable.
      triggerMode: TooltipTriggerMode.tap,
      message:
          'The price to post rises when the app is busy. '
          "It's locked in for $label — after that it may change.",
      child: _Stat(
        icon: Icons.timer_outlined,
        label: label,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
