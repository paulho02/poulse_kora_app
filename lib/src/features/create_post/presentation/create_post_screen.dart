import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../channels/application/channels_providers.dart';
import '../../channels/data/channel.dart';
import '../../feed/application/feed_providers.dart';
import '../../feed/data/feed_repository.dart';
import '../../stats/application/stats_providers.dart';
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
    Future.microtask(() => ref.read(reviewGateStatusProvider.notifier).ensureLoaded());
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
      await ref.read(feedRepositoryProvider).createPost(
            channelId: channelId,
            text: text,
            isAnonymous: _isAnonymous,
          );
      if (!mounted) return;
      _textController.clear();
      setState(() => _isAnonymous = false);
      ref.invalidate(feedNotifierProvider);
      context.go('/feed');
    } on RelayApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageFor(e))),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _messageFor(RelayApiException e) {
    switch (e.error) {
      case 'review_gate_locked':
        return 'Review more posts before you can create one.';
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
    final gateStatus = ref.watch(reviewGateStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Post'),
        actions: [
          if (gateStatus?.unlocked ?? false)
            TextButton(
              onPressed: _isSubmitting ? null : _submit,
              child: const Text('Relay'),
            ),
        ],
      ),
      body: gateStatus == null
          ? const Center(child: CircularProgressIndicator())
          : gateStatus.unlocked
              ? channelsAsync.when(
                  data: (channels) => _buildEditor(context, channels),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) =>
                      Center(child: Text('Could not load channels:\n$error')),
                )
              : _buildLockedState(context, gateStatus),
    );
  }

  Widget _buildLockedState(BuildContext context, ReviewGateStatus gate) {
    final theme = Theme.of(context);
    final remaining = (gate.reviewGate - gate.reviewedCount).clamp(0, gate.reviewGate);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 20),
            Text('Review to unlock posting', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Forward or drop $remaining more post${remaining == 1 ? '' : 's'} in your '
              'feed before you can publish.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/feed'),
              child: const Text('Go to Feed'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context, List<Channel> channels) {
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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                avatar: Icon(_isAnonymous ? Icons.visibility_off : Icons.visibility, size: 16),
                selected: _isAnonymous,
                onSelected: (value) => setState(() => _isAnonymous = value),
              ),
              const Spacer(),
              if (_isSubmitting) const CircularProgressIndicator(strokeWidth: 2),
            ],
          ),
        ],
      ),
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
