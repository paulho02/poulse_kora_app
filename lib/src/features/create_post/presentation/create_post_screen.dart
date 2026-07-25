import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../channels/application/channels_providers.dart';
import '../../channels/data/channel.dart';
import '../../economy/application/economy_providers.dart';
import '../../economy/data/economy.dart';
import '../../economy/presentation/economy_status_bar.dart';
import '../../feed/application/feed_providers.dart';
import '../../feed/data/feed_repository.dart';
import 'channel_picker_sheet.dart';

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _textController = TextEditingController();
  int? _selectedChannelId;
  bool _isAnonymous = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Refresh so the price reflects current congestion when opening the composer.
    Future.microtask(() => ref.read(economyProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final channelId = _selectedChannelId;
    final text = _textController.text.trim();
    if (channelId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a channel to post to.')),
      );
      return;
    }
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write something before relaying.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = await ref
          .read(feedRepositoryProvider)
          .createPost(
            channelId: channelId,
            text: text,
            isAnonymous: _isAnonymous,
          );
      // Posting spent tokens; sync the balance and refresh the (now higher) price.
      ref.read(economyProvider.notifier).setBalance(result.tokenBalance);
      await ref.read(economyProvider.notifier).refresh();
      ref.invalidate(feedNotifierProvider);
      if (!mounted) return;
      _textController.clear();
      setState(() => _isAnonymous = false);
      context.go('/feed');
    } on RelayApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_messageFor(e))));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _messageFor(RelayApiException e) {
    switch (e.error) {
      case 'insufficient_tokens':
        final price = e.detail['price'];
        final balance = e.detail['balance'];
        return 'Not enough tokens to post (need $price, you have $balance). '
            'Review posts in your feed to earn more.';
      default:
        return 'Could not create the post.';
    }
  }

  Future<void> _pickChannel(List<Channel> channels) async {
    final selected = await showChannelPickerSheet(
      context,
      channels: channels,
      selectedId: _selectedChannelId,
    );
    if (selected != null) {
      setState(() => _selectedChannelId = selected.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(channelsNotifierProvider);
    final economy = ref.watch(economyProvider);
    final canAfford = economy?.canAffordPost ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Post'),
        actions: [
          TextButton(
            onPressed: (_isSubmitting || !canAfford) ? null : _submit,
            child: const Text('Relay'),
          ),
        ],
      ),
      body: economy == null
          ? const Center(child: CircularProgressIndicator())
          : channelsAsync.when(
              data: (channels) => _buildEditor(context, channels, economy),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text('Could not load channels:\n$error')),
            ),
    );
  }

  /// Shown above the composer when the user can't yet afford the current price:
  /// posting is admission-priced in tokens, earned by reviewing.
  Widget _buildAffordabilityBanner(BuildContext context, Economy economy) {
    final theme = Theme.of(context);
    final needed = (economy.postPrice - economy.tokenBalance).clamp(
      0,
      economy.postPrice,
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.toll_outlined,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Need $needed more token${needed == 1 ? '' : 's'} to post at the current '
              'price of ${economy.postPrice}. Review posts in your feed to earn more.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: () => context.go('/feed'),
            child: const Text('Feed'),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(
    BuildContext context,
    List<Channel> channels,
    Economy economy,
  ) {
    if (channels.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No channels are available to post to yet.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    Channel? selectedChannel;
    for (final c in channels) {
      if (c.id == _selectedChannelId) {
        selectedChannel = c;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EconomyStatusBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!economy.canAffordPost)
                  _buildAffordabilityBanner(context, economy),
                _ChannelSelectorButton(
                  channel: selectedChannel,
                  onTap: () => _pickChannel(channels),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      hintText: "What's worth sharing?",
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const Divider(),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('Anonymous'),
                      avatar: Icon(
                        _isAnonymous ? Icons.visibility_off : Icons.visibility,
                        size: 16,
                      ),
                      selected: _isAnonymous,
                      onSelected: (value) =>
                          setState(() => _isAnonymous = value),
                    ),
                    const Spacer(),
                    if (_isSubmitting)
                      const CircularProgressIndicator(strokeWidth: 2),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Tappable field that shows the currently selected channel (or a prompt) and
/// opens the searchable channel picker.
class _ChannelSelectorButton extends StatelessWidget {
  const _ChannelSelectorButton({required this.channel, required this.onTap});

  final Channel? channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelection = channel != null;
    final color = hasSelection ? AppColors.channelColor(channel!.name) : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Channel',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        child: Row(
          children: [
            if (color != null) ...[
              CircleAvatar(backgroundColor: color, radius: 7),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                hasSelection ? channel!.name : 'Select a channel',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: hasSelection
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Icon(Icons.expand_more, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
