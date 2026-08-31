import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/network/connectivity.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/tips/presentation/view_tip.dart';
import '../../channels/application/channels_providers.dart';
import '../../channels/data/channel.dart';
import '../../economy/application/economy_providers.dart';
import '../../economy/data/economy.dart';
import '../../economy/presentation/economy_status_bar.dart';
import '../../feed/application/feed_providers.dart';
import '../../feed/data/feed_repository.dart'
    show ComposerBlockInput, PickedMedia;
import '../../history/application/history_providers.dart';
import '../../stats/application/stats_providers.dart';
import 'channel_picker_sheet.dart';

/// One photo/video picked in the composer, before upload — mirrors `PostMedia`'s
/// shape closely enough to preview it, but stays local until `_submit` turns it
/// into a `PickedMedia` for `FeedRepository.createPost`.
class _PickedItem {
  _PickedItem({
    required this.bytes,
    required this.filename,
    required this.contentType,
    required this.isVideo,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
  final bool isVideo;
}

/// One row in the composer, article-style: a paragraph of text or one picked
/// photo/video. `_blocks` holds these in display order; dragging a row (via its
/// handle) reorders them, which is how a photo ends up "between" two
/// paragraphs - see `_onReorder`.
sealed class _ComposerBlock {}

class _TextBlock extends _ComposerBlock {
  _TextBlock([String initial = ''])
    : controller = TextEditingController(text: initial);

  final TextEditingController controller;
}

class _MediaBlock extends _ComposerBlock {
  _MediaBlock(this.item);

  final _PickedItem item;
}

/// Up to POST_MEDIA_MAX_FILES total per post (see the backend's
/// POST_MEDIA_MAX_FILES) — kept in sync manually since the composer has no
/// config endpoint to read it from; matches the current backend default.
const _kMaxMediaItems = 5;

String _guessContentType(XFile file, {required bool isVideo}) {
  final mime = file.mimeType;
  if (mime != null) return mime;
  final ext = file.name.split('.').last.toLowerCase();
  if (isVideo) return ext == 'mov' ? 'video/quicktime' : 'video/mp4';
  switch (ext) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    default:
      return 'image/jpeg';
  }
}

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  int? _selectedChannelId;
  bool _isAnonymous = false;
  bool _isSubmitting = false;
  final List<_ComposerBlock> _blocks = [_TextBlock()];

  @override
  void initState() {
    super.initState();
    // Refresh so the price reflects current congestion when opening the composer.
    Future.microtask(() => ref.read(economyProvider.notifier).refresh());
  }

  @override
  void dispose() {
    for (final block in _blocks) {
      if (block is _TextBlock) block.controller.dispose();
    }
    super.dispose();
  }

  int get _mediaCount => _blocks.whereType<_MediaBlock>().length;
  int get _remainingMediaSlots => _kMaxMediaItems - _mediaCount;

  Future<void> _submit() async {
    final channelId = _selectedChannelId;
    final l10n = AppLocalizations.of(context);
    if (channelId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.createPostPickChannelError)),
      );
      return;
    }

    // Walk the blocks in order, building the parallel (block, file) lists the
    // repository sends - a media block's `file_index` is its position in
    // `media`, not in `_blocks`. Empty/whitespace-only paragraphs are dropped
    // silently rather than rejected - an easy thing to leave behind while
    // rearranging blocks.
    final blockInputs = <ComposerBlockInput>[];
    final media = <PickedMedia>[];
    for (final block in _blocks) {
      switch (block) {
        case _TextBlock():
          final text = block.controller.text.trim();
          if (text.isNotEmpty) blockInputs.add(ComposerBlockInput.text(text));
        case _MediaBlock():
          blockInputs.add(ComposerBlockInput.media(media.length));
          media.add(
            PickedMedia(
              bytes: block.item.bytes,
              filename: block.item.filename,
              contentType: block.item.contentType,
            ),
          );
      }
    }
    if (blockInputs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.createPostEmptyPostError)),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = await ref
          .read(feedRepositoryProvider)
          .createPost(
            channelId: channelId,
            blocks: blockInputs,
            isAnonymous: _isAnonymous,
            media: media,
          );
      // Posting spent tokens; sync the balance and refresh the (now higher) price.
      ref.read(economyProvider.notifier).setBalance(result.tokenBalance);
      await ref.read(economyProvider.notifier).refresh();
      ref.invalidate(feedNotifierProvider);
      ref.invalidate(postedHistoryProvider);
      ref.invalidate(statsProvider);
      if (!mounted) return;
      for (final block in _blocks) {
        if (block is _TextBlock) block.controller.dispose();
      }
      setState(() {
        _isAnonymous = false;
        _blocks
          ..clear()
          ..add(_TextBlock());
      });
      context.go('/feed');
    } catch (error) {
      if (!mounted) return;
      // Includes the offline case: publishing is priced at request time from live
      // queue congestion, so it can't be deferred to a replay at an unknown price.
      showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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

  Future<void> _addPhotos() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final remaining = _remainingMediaSlots;
    if (remaining <= 0) return;

    final List<XFile> files;
    try {
      files = await ImagePicker().pickMultiImage(
        // Client-side courtesy only — the backend re-encodes/downscales and
        // enforces the real caps (POST_IMAGE_MAX_DIMENSION_PX etc.) regardless.
        maxWidth: 2048,
        maxHeight: 2048,
        limit: remaining,
      );
    } catch (error) {
      showErrorSnackBarOn(messenger, l10n, error);
      return;
    }
    if (files.isEmpty) return;

    final items = await Future.wait(
      files.take(remaining).map((file) async {
        return _PickedItem(
          bytes: await file.readAsBytes(),
          filename: file.name,
          contentType: _guessContentType(file, isVideo: false),
          isVideo: false,
        );
      }),
    );
    if (!mounted) return;
    // Appended at the end, not inserted at a cursor - the user drags a block
    // to where it belongs (see the class docstring on _ComposerBlock).
    setState(() => _blocks.addAll(items.map(_MediaBlock.new)));
  }

  Future<void> _addVideo() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    if (_remainingMediaSlots <= 0) return;

    final XFile? file;
    try {
      file = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        // Client-side courtesy only, matching the backend's
        // POST_VIDEO_MAX_DURATION_SECONDS default — the server still measures
        // and enforces the real cap itself via ffprobe.
        maxDuration: const Duration(seconds: 60),
      );
    } catch (error) {
      showErrorSnackBarOn(messenger, l10n, error);
      return;
    }
    if (file == null) return;

    final item = _PickedItem(
      bytes: await file.readAsBytes(),
      filename: file.name,
      contentType: _guessContentType(file, isVideo: true),
      isVideo: true,
    );
    if (!mounted) return;
    setState(() => _blocks.add(_MediaBlock(item)));
  }

  void _addTextBlock() {
    setState(() => _blocks.add(_TextBlock()));
  }

  void _removeBlock(int index) {
    setState(() {
      final block = _blocks.removeAt(index);
      if (block is _TextBlock) block.controller.dispose();
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    // `onReorderItem`, not the deprecated `onReorder`: newIndex already
    // accounts for the item being removed from oldIndex first.
    setState(() {
      final block = _blocks.removeAt(oldIndex);
      _blocks.insert(newIndex, block);
    });
  }

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(channelsNotifierProvider);
    final economy = ref.watch(economyProvider);
    final isOffline = ref.watch(connectivityProvider).isOffline;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.createPostTitle)),
      body: ViewTip(
        tipKey: 'tip.create',
        message: l10n.createPostTipMessage,
        child: Builder(
          builder: (context) {
            if (economy == null) {
              // `EconomyNotifier.refresh` swallows connectivity failures, so an
              // offline first launch would otherwise spin here forever.
              if (isOffline) {
                return ErrorStateView(
                  error: RelayApiException(
                    0,
                    'offline',
                    const {},
                    kind: ApiErrorKind.offline,
                  ),
                  onRetry: () => ref.read(economyProvider.notifier).refresh(),
                );
              }
              return const Center(child: CircularProgressIndicator());
            }
            return channelsAsync.when(
              data: (cached) =>
                  _buildEditor(context, cached.data, economy.data),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ErrorStateView(
                error: error,
                onRetry: () =>
                    ref.read(channelsNotifierProvider.notifier).refresh(),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Shown above the composer when the user can't yet afford the current price:
  /// posting is admission-priced in tokens, earned by reviewing.
  Widget _buildAffordabilityBanner(BuildContext context, Economy economy) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
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
              l10n.createPostNeedMoreTokens(needed, economy.postPrice),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: () => context.go('/feed'),
            child: Text(l10n.feedTitle),
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
    final l10n = AppLocalizations.of(context);
    if (channels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l10n.createPostNoChannels,
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
                const SizedBox(height: 8),
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: _blocks.length,
                    onReorderItem: _onReorder,
                    itemBuilder: (context, index) =>
                        _buildBlockRow(context, index),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: l10n.createPostAddPhoto,
                      onPressed: _remainingMediaSlots <= 0 ? null : _addPhotos,
                      icon: const Icon(Icons.photo_outlined),
                    ),
                    IconButton(
                      tooltip: l10n.createPostAddVideo,
                      onPressed: _remainingMediaSlots <= 0 ? null : _addVideo,
                      icon: const Icon(Icons.videocam_outlined),
                    ),
                    IconButton(
                      tooltip: l10n.createPostAddText,
                      onPressed: _addTextBlock,
                      icon: const Icon(Icons.notes_outlined),
                    ),
                    if (_mediaCount > 0)
                      Text(
                        '$_mediaCount/$_kMaxMediaItems',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
                const Divider(),
                Row(
                  children: [
                    FilterChip(
                      label: Text(l10n.postAnonymous),
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
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    TextButton(
                      onPressed: (_isSubmitting || !economy.canAffordPost)
                          ? null
                          : _submit,
                      child: const Text('Relay'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBlockRow(BuildContext context, int index) {
    final block = _blocks[index];
    final l10n = AppLocalizations.of(context);
    return Padding(
      key: ValueKey(block),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(top: 10, right: 4),
              child: Icon(
                Icons.drag_indicator,
                size: 20,
                color: Theme.of(context).colorScheme.outline,
                semanticLabel: l10n.createPostReorderBlock,
              ),
            ),
          ),
          Expanded(
            child: switch (block) {
              _TextBlock() => TextField(
                controller: block.controller,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: l10n.createPostHint,
                  border: InputBorder.none,
                ),
              ),
              _MediaBlock() => _ComposerMediaTile(item: block.item),
            },
          ),
          IconButton(
            tooltip: l10n.createPostRemoveMedia,
            iconSize: 18,
            onPressed: () => _removeBlock(index),
            icon: const Icon(Icons.close),
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
    final l10n = AppLocalizations.of(context);
    final hasSelection = channel != null;
    final color = hasSelection ? AppColors.channelColor(channel!.name) : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.createPostChannelLabel,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
        ),
        child: Row(
          children: [
            if (color != null) ...[
              CircleAvatar(backgroundColor: color, radius: 7),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                hasSelection ? channel!.name : l10n.createPostSelectChannel,
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

/// One picked photo/video, as a full-width row in the block editor. Video gets
/// the same neutral play-icon tile as the feed card (`PostMediaThumbnail`'s
/// `_VideoPlaceholderTile`) for visual consistency, rather than decoding a
/// frame just for this preview.
class _ComposerMediaTile extends StatelessWidget {
  const _ComposerMediaTile({required this.item});

  final _PickedItem item;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: item.isVideo
            ? const ColoredBox(
                color: Colors.black87,
                child: Icon(Icons.play_circle_outline, color: Colors.white),
              )
            : Image.memory(item.bytes, fit: BoxFit.cover),
      ),
    );
  }
}
