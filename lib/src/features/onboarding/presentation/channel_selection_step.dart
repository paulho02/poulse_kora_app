import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../../core/theme/app_colors.dart';
import '../../channels/application/channels_providers.dart';
import '../../channels/data/channel.dart';

/// The onboarding flow's mandatory channel step: pick 1-3 channels so the Feed
/// tab has something in it the moment onboarding finishes.
///
/// The 1-3 cap is enforced here only. Nothing backend-side stops an existing
/// user from subscribing to more later from the Channels tab; this is purely
/// about giving a new account a manageable, non-empty starting feed.
///
/// The list itself is fetched earlier, when `OnboardingScreen` mounts, so by
/// the time this step appears it is usually already in hand. This widget adds
/// the other half of that arrangement: a warm-up that failed left an error
/// nobody saw, minutes ago, so the step asks once more when it arrives instead
/// of showing a Retry button for a stale answer. Only a second failure is
/// current enough to be worth showing.
class ChannelSelectionStep extends ConsumerStatefulWidget {
  const ChannelSelectionStep({super.key, required this.onContinue});
  final VoidCallback onContinue;

  static const _maxSelectable = 3;

  @override
  ConsumerState<ChannelSelectionStep> createState() =>
      _ChannelSelectionStepState();
}

class _ChannelSelectionStepState extends ConsumerState<ChannelSelectionStep> {
  @override
  void initState() {
    super.initState();
    // Deliberately narrow: only a *stale error* is re-asked, never a list that
    // loaded fine and never one still in flight. Refreshing unconditionally
    // would throw away a good warm-up and put a spinner in front of everyone.
    if (!ref.read(channelsNotifierProvider).hasError) return;
    Future.microtask(() {
      if (mounted) ref.read(channelsNotifierProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final channelsAsync = ref.watch(channelsNotifierProvider);
    final selectedCount = ref.watch(subscribedChannelsProvider).length;
    final canContinue =
        selectedCount >= 1 &&
        selectedCount <= ChannelSelectionStep._maxSelectable;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.onboardingChannelsTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.onboardingChannelsSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.onboardingChannelsSelectedCount(
                    selectedCount,
                    ChannelSelectionStep._maxSelectable,
                  ),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selectedCount == 0
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: channelsAsync.when(
              data: (cached) => ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: cached.data.length,
                itemBuilder: (context, i) => _SelectableChannelTile(
                  channel: cached.data[i],
                  atMax:
                      selectedCount >= ChannelSelectionStep._maxSelectable,
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ErrorStateView(
                error: error,
                onRetry: () =>
                    ref.read(channelsNotifierProvider.notifier).refresh(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canContinue ? widget.onContinue : null,
                child: Text(l10n.commonContinue),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectableChannelTile extends ConsumerWidget {
  const _SelectableChannelTile({required this.channel, required this.atMax});

  final Channel channel;

  /// Whether the 3-channel cap is already reached — relevant only when
  /// [channel] itself isn't the one already selected, to block picking a 4th.
  final bool atMax;

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    if (!channel.isSubscribed && atMax) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l10n.onboardingChannelsMaxReached(
                ChannelSelectionStep._maxSelectable,
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    try {
      await ref
          .read(channelsNotifierProvider.notifier)
          .toggleSubscription(channel);
    } catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = AppColors.channelColor(channel.name);
    return ListTile(
      onTap: () => _toggle(context, ref),
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
      subtitle: Text(
        channel.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Checkbox(
        value: channel.isSubscribed,
        onChanged: (_) => _toggle(context, ref),
      ),
    );
  }
}
