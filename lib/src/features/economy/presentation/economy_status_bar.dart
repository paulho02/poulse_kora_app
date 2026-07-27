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
