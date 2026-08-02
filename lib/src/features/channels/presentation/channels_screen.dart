import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/tips/presentation/view_tip.dart';
import '../application/channels_providers.dart';
import '../data/channel.dart';

class ChannelsScreen extends ConsumerStatefulWidget {
  const ChannelsScreen({super.key});

  @override
  ConsumerState<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends ConsumerState<ChannelsScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(channelsNotifierProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.channelsTitle)),
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
                                  itemBuilder: (context, index) =>
                                      _ChannelTile(channel: filtered[index]),
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
  const _ChannelTile({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = AppColors.channelColor(channel.name);
    final l10n = AppLocalizations.of(context);
    return ListTile(
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
      subtitle: Text(channel.description),
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
          channel.isSubscribed ? l10n.channelsJoinedButton : l10n.channelsJoinButton,
        ),
      ),
    );
  }
}
