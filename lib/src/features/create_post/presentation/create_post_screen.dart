import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/media/post_media_format.dart';
import '../../../core/media/presentation/crop_media_screen.dart';
import '../../../core/network/connectivity.dart';
import '../../../core/presentation/error_state_view.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/tips/presentation/tip_dialog.dart';
import '../../../core/tips/presentation/view_tip.dart';
import '../../channels/application/channels_providers.dart';
import '../../channels/data/channel.dart';
import '../../economy/application/economy_providers.dart';
import '../../economy/data/economy.dart';
import '../../economy/presentation/economy_header_status.dart';
import '../../feed/application/feed_providers.dart';
import '../../feed/data/feed_repository.dart'
    show ComposerBlockInput, PickedMedia;
import '../../feed/data/post.dart';
import '../../history/application/history_providers.dart';
import '../../profile/application/profile_providers.dart';
import '../../stats/application/stats_providers.dart';
import 'channel_picker_sheet.dart';
import 'post_preview.dart';
import 'video_orientation_sheet.dart';

/// One photo/video picked in the composer, before upload — mirrors `PostMedia`'s
/// shape closely enough to preview it, but stays local until `_submit` turns it
/// into a `PickedMedia` for `FeedRepository.createPost`.
///
/// Every item carries an [orientation], because every published attachment is
/// one of two fixed shapes (see `core/media/post_media_format.dart`). How it got
/// one differs by kind, and that difference is the whole design: a **photo** is
/// already cropped to it — `bytes` are the cropper's output, not the picker's —
/// while a **video** only records the choice, since a Flutter client has no
/// encoder and the crop happens server-side during the transcode.
class _PickedItem {
  _PickedItem({
    required this.bytes,
    required this.filename,
    required this.contentType,
    required this.isVideo,
    required this.orientation,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
  final bool isVideo;
  final PostMediaOrientation orientation;

  double get aspectRatio => orientation.ratio;
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

/// Only videos need guessing now: a photo is re-encoded by the cropper, so its
/// content type is `image/png` by construction rather than by inference.
String _guessVideoContentType(XFile file) {
  final mime = file.mimeType;
  if (mime != null) return mime;
  return file.name.split('.').last.toLowerCase() == 'mov'
      ? 'video/quicktime'
      : 'video/mp4';
}

/// `holiday.heic` -> `holiday.png`. The cropper's output is always PNG, so
/// carrying the source extension over would name the file a lie.
String _asPngFilename(String original) {
  final dot = original.lastIndexOf('.');
  final base = dot > 0 ? original.substring(0, dot) : original;
  return '$base.png';
}

/// A publishing precondition the author hasn't met yet.
///
/// Shown as a line inside the toolbar rather than as a snackbar, because the
/// composer's controls now sit at the *bottom* of the screen and a snackbar is
/// drawn over exactly them - "pick a channel" covered the channel chip it was
/// asking the author to tap, so the message had to time out before it could be
/// acted on. Stored as a case rather than as resolved text so it survives a
/// locale change.
enum _PublishBlocker { noChannel, emptyPost }

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  int? _selectedChannelId;
  _PublishBlocker? _blocker;
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
    if (channelId == null) {
      setState(() => _blocker = _PublishBlocker.noChannel);
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
          blockInputs.add(
            ComposerBlockInput.media(
              media.length,
              // Photos arrive already cropped, so their shape is settled and
              // the backend only validates it; a video's crop is still ahead.
              orientation: block.item.isVideo
                  ? block.item.orientation.wireValue
                  : null,
            ),
          );
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
      setState(() => _blocker = _PublishBlocker.emptyPost);
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
      // The channel's own price moved too — this post is one more op on its
      // backlog, which is exactly what its price is measured from.
      unawaited(ref.read(channelsNotifierProvider.notifier).refreshPrices());
      ref.invalidate(feedNotifierProvider);
      ref.invalidate(postedHistoryProvider);
      ref.invalidate(statsProvider);
      if (!mounted) return;
      for (final block in _blocks) {
        if (block is _TextBlock) block.controller.dispose();
      }
      setState(() {
        _isAnonymous = false;
        // The channel is cleared along with everything else: the composer is a
        // tab in the shell's IndexedStack, so its state outlives the post it
        // was written for, and a channel left selected is inherited silently by
        // the next one - noticed only after relaying to the wrong place.
        _selectedChannelId = null;
        _blocker = null;
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

  /// Show the post as a reader will get it (see `post_preview.dart`).
  ///
  /// Runs the same "drop empty paragraphs, keep the order" walk `_submit` does,
  /// so what is previewed is what would be published — an author who left a
  /// blank block behind while rearranging sees the post without it, which is
  /// what the reader gets. An empty post raises the same blocker line the Relay
  /// button would rather than opening a blank screen; a channel is *not*
  /// required, since previewing the writing is worth doing before that choice
  /// is made.
  void _openPreview(Channel? channel) {
    final blocks = _previewBlocks();
    if (blocks.isEmpty) {
      setState(() => _blocker = _PublishBlocker.emptyPost);
      return;
    }
    // Same reason as `_pickChannel`: a route pushed with the keyboard up hands
    // focus back on the way out, reopening it over a post already written.
    FocusManager.instance.primaryFocus?.unfocus();
    showPostPreview(
      context,
      buildPreviewPost(
        blocks: blocks,
        channel: channel,
        isAnonymous: _isAnonymous,
        author: ref.read(profileProvider).value?.data,
      ),
    );
  }

  List<PostBlock> _previewBlocks() {
    final blocks = <PostBlock>[];
    for (final block in _blocks) {
      switch (block) {
        case _TextBlock():
          final text = block.controller.text.trim();
          if (text.isNotEmpty) blocks.add(PostTextBlock(text));
        case _MediaBlock():
          blocks.add(
            PostMediaBlock(
              PostMedia.local(
                bytes: block.item.bytes,
                isVideo: block.item.isVideo,
                aspectRatio: block.item.aspectRatio,
              ),
            ),
          );
      }
    }
    return blocks;
  }

  Future<void> _pickChannel(List<Channel> channels) async {
    // Drop focus before the sheet opens, and again once it closes: a modal
    // route hands focus back to whatever held it, so picking a channel popped
    // the keyboard up over a post that was already written. Reopening it made
    // sense while the picker came *before* the editor; from the publish row,
    // the next thing the author wants is the Relay button, not the keyboard.
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = await showChannelPickerSheet(
      context,
      channels: channels,
      selectedId: _selectedChannelId,
    );
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (selected != null) {
      setState(() {
        _selectedChannelId = selected.id;
        if (_blocker == _PublishBlocker.noChannel) _blocker = null;
      });
    }
  }

  /// Pick photos, then crop each one to a published shape before it is kept.
  ///
  /// The crop is mandatory rather than offered: the backend rejects any other
  /// aspect ratio outright (`post_media_invalid_aspect_ratio`), so a "skip"
  /// would only produce an upload that fails later. Backing out of the cropper
  /// therefore drops *that* photo and moves on to the next, rather than
  /// cancelling the whole selection — picking five and rethinking one is a
  /// normal thing to do.
  Future<void> _addPhotos() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    final remaining = _remainingMediaSlots;
    if (remaining <= 0) return;

    final List<XFile> files;
    try {
      files = await ImagePicker().pickMultiImage(
        // Bounds what the cropper has to decode. Above kPostCropLongestSide, so
        // zooming in still has real pixels to sample.
        maxWidth: 2048,
        maxHeight: 2048,
        limit: remaining,
      );
    } catch (error) {
      showErrorSnackBarOn(messenger, l10n, error);
      return;
    }
    if (files.isEmpty) return;

    final added = <_PickedItem>[];
    for (final file in files.take(remaining)) {
      final ui.Image decoded;
      try {
        decoded = await decodeImageBytes(await file.readAsBytes());
      } catch (_) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(l10n.errorPostMediaInvalidType)),
          );
        continue;
      }

      final CropResult? cropped;
      try {
        cropped = await navigator.push<CropResult>(
          MaterialPageRoute(
            builder: (_) => CropMediaScreen(
              image: decoded,
              aspects: [
                CropAspect(
                  ratio: kPostMediaPortraitRatio,
                  label: l10n.composerFormatPortrait,
                  icon: Icons.crop_portrait,
                ),
                CropAspect(
                  ratio: kPostMediaLandscapeRatio,
                  label: l10n.composerFormatLandscape,
                  icon: Icons.crop_landscape,
                ),
              ],
              // Start on whichever shape the photo is already closest to, so
              // the common case is one confirmation rather than a decision.
              initialAspectIndex:
                  nearestPostOrientation(decoded.width / decoded.height) ==
                      PostMediaOrientation.portrait
                  ? 0
                  : 1,
              outputLongestSide: kPostCropLongestSide,
              title: l10n.composerCropPhotoTitle,
              hint: l10n.composerCropPhotoHint,
            ),
            fullscreenDialog: true,
          ),
        );
      } finally {
        decoded.dispose();
      }
      if (cropped == null) continue;

      added.add(
        _PickedItem(
          bytes: cropped.bytes,
          filename: _asPngFilename(file.name),
          contentType: 'image/png',
          isVideo: false,
          orientation: nearestPostOrientation(cropped.aspectRatio),
        ),
      );
    }

    if (!mounted || added.isEmpty) return;
    // Appended at the end, not inserted at a cursor - the user drags a block
    // to where it belongs (see the class docstring on _ComposerBlock).
    setState(() {
      _blocks.addAll(added.map(_MediaBlock.new));
      _clearEmptyPostBlocker();
    });
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
    // Bound to a plain local: `file` is a deferred-initialised final, which Dart
    // will not carry a promotion for into the closure below.
    final picked = file;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    // Asked after picking, not before: by now the author has committed to a
    // clip, and the question ("which shape?") is only answerable with one in
    // mind. Dismissing cancels adding it rather than defaulting silently — the
    // backend would happily guess, but then the crop is a surprise.
    final orientation = await showVideoOrientationSheet(context);
    if (orientation == null || !mounted) return;

    setState(() {
      _blocks.add(
        _MediaBlock(
          _PickedItem(
            bytes: bytes,
            filename: picked.name,
            contentType: _guessVideoContentType(picked),
            isVideo: true,
            orientation: orientation,
          ),
        ),
      );
      _clearEmptyPostBlocker();
    });
  }

  /// Turning anonymity *on* is the one direction that needs explaining — what
  /// the reader loses sight of, and what we still store. Shown as a tip
  /// (`showTipDialog`) rather than a plain dialog so it silences itself once
  /// the user has read it, and comes back with "Reset tutorial hints".
  void _onAnonymousChanged(bool value) {
    setState(() => _isAnonymous = value);
    if (!value) return;
    final l10n = AppLocalizations.of(context);
    showTipDialog(
      context: context,
      ref: ref,
      tipKey: 'tip.anonymousPost',
      title: l10n.postAnonymousDisclaimerTitle,
      message: l10n.postAnonymousDisclaimerBody,
      icon: Icons.visibility_off_outlined,
    );
  }

  /// Adding to the article can only make the "add something first" line stale,
  /// so it clears with the edit rather than waiting for the next Relay press.
  /// Call from inside a `setState`.
  void _clearEmptyPostBlocker() {
    if (_blocker == _PublishBlocker.emptyPost) _blocker = null;
  }

  void _addTextBlock() {
    setState(() {
      _blocks.add(_TextBlock());
      _clearEmptyPostBlocker();
    });
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
    final channels = channelsAsync.value?.data;
    // Only real once the editor itself is showing (matches `_buildEditor`'s
    // own empty-channels/loading/error branches, which render no toolbar).
    final showToolbar =
        economy != null && channels != null && channels.isNotEmpty;
    // Resolved once here rather than in `_buildToolbar` alone: the pill needs
    // it too, because the price this post will be charged is the *channel's*,
    // not the global rate the economy endpoint quotes.
    final selectedChannel = _channelById(channels, _selectedChannelId);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.createPostTitle),
        // The price rides in the title bar rather than in a bar of its own: the
        // composer's scarce resource is vertical space for what is being
        // written. See `EconomyHeaderStatus`.
        actions: [
          EconomyHeaderStatus(
            variant: EconomyBarVariant.composer,
            priceOverride: selectedChannel?.postPrice,
          ),
          const SizedBox(width: 8),
        ],
      ),
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
              data: (cached) => _buildEditor(context, cached.data),
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
      // Pinned outside the scrolling editor (rather than inline below the
      // ReorderableListView) so these fixed-height controls don't eat into
      // the editor's viewport once the keyboard is up — on a small screen
      // that squeeze could push the actively-typed block below the fold,
      // behind the keyboard. The Scaffold still slides this bar up above the
      // keyboard on its own via `resizeToAvoidBottomInset`.
      bottomNavigationBar: showToolbar
          ? _buildToolbar(
              context,
              channels,
              // Everything the toolbar decides — the affordability hint, whether
              // Relay is enabled — has to weigh the balance against the price
              // that will actually be charged.
              _effectiveEconomy(economy.data, selectedChannel),
              selectedChannel,
            )
          : null,
    );
  }

  static Channel? _channelById(List<Channel>? channels, int? id) {
    if (channels == null || id == null) return null;
    for (final channel in channels) {
      if (channel.id == id) return channel;
    }
    return null;
  }

  /// The economy as it applies to *this* post: the viewer's balance, priced
  /// against the chosen channel.
  ///
  /// Falls back to the global quote while no channel is chosen — and while the
  /// channel's own price is unknown, which is a list cached before per-channel
  /// pricing existed rather than a channel that is somehow free.
  static Economy _effectiveEconomy(Economy economy, Channel? channel) {
    final price = channel?.postPrice;
    return price == null ? economy : economy.copyWith(postPrice: price);
  }

  /// Everything that is not the article being written: the block-adding
  /// buttons, and the three decisions made at the moment of publishing
  /// (channel, anonymity, relay).
  Widget _buildToolbar(
    BuildContext context,
    List<Channel> channels,
    Economy economy,
    Channel? selectedChannel,
  ) {
    final l10n = AppLocalizations.of(context);

    final needed = (economy.postPrice - economy.tokenBalance).clamp(
      0,
      economy.postPrice,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                const Spacer(),
                // Set apart from the three "add a block" buttons: this one
                // doesn't change the post, it looks at it. Never disabled — an
                // empty post answers with the blocker line, which says more
                // than a greyed-out button can.
                TextButton.icon(
                  onPressed: () => _openPreview(selectedChannel),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: Text(l10n.createPostPreview),
                ),
              ],
            ),
            const Divider(height: 8),
            // Only when it applies, and right above the button it explains —
            // the disabled Relay button is otherwise the only thing saying no,
            // and it can't say why.
            if (!economy.canAffordPost)
              _ShortOnTokensHint(
                needed: needed,
                onEarnTokens: () => context.go('/feed'),
              ),
            if (_blocker != null) _PublishBlockerHint(blocker: _blocker!),
            Row(
              children: [
                FilterChip(
                  label: Text(l10n.postAnonymous),
                  avatar: Icon(
                    _isAnonymous ? Icons.visibility_off : Icons.visibility,
                    size: 16,
                  ),
                  selected: _isAnonymous,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: _onAnonymousChanged,
                ),
                const SizedBox(width: 8),
                // The channel picker used to be a full-width labelled field at
                // the top of the editor — a whole row spent on one word that is
                // usually chosen once. As a chip it sits in the row it belongs
                // to: the three decisions made at the moment of publishing.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _ChannelSelectorChip(
                      channel: selectedChannel,
                      hasError: _blocker == _PublishBlocker.noChannel,
                      onTap: () => _pickChannel(channels),
                    ),
                  ),
                ),
                if (_isSubmitting)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
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
    );
  }

  Widget _buildEditor(BuildContext context, List<Channel> channels) {
    final l10n = AppLocalizations.of(context);
    if (channels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(l10n.createPostNoChannels, textAlign: TextAlign.center),
        ),
      );
    }

    // Nothing but the blocks: the controls live in the Scaffold's pinned
    // toolbar (see `_buildToolbar`), so this whole viewport is the article.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        itemCount: _blocks.length,
        onReorderItem: _onReorder,
        itemBuilder: (context, index) => _buildBlockRow(context, index),
      ),
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
                onChanged: (_) {
                  if (_blocker == _PublishBlocker.emptyPost) {
                    setState(_clearEmptyPostBlocker);
                  }
                },
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

/// The chosen channel as a chip, sitting in the publish row.
///
/// Unpicked it is outlined in the primary colour and reads as a prompt, which
/// is the whole of what the old labelled field's extra row was buying: a
/// required choice that is visibly still open.
class _ChannelSelectorChip extends StatelessWidget {
  const _ChannelSelectorChip({
    required this.channel,
    required this.hasError,
    required this.onTap,
  });

  final Channel? channel;

  /// Relay was pressed with no channel picked - the chip turns error-coloured
  /// so the hint line above it has something to point at.
  final bool hasError;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final selected = channel;
    final color = selected == null
        ? (hasError ? theme.colorScheme.error : theme.colorScheme.primary)
        : AppColors.channelColor(selected.name);

    return ActionChip(
      onPressed: onTap,
      tooltip: l10n.createPostChannelLabel,
      avatar: selected == null
          ? Icon(Icons.tag, size: 16, color: color)
          : CircleAvatar(backgroundColor: color, radius: 6),
      label: Text(
        selected?.name ?? l10n.createPostSelectChannel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      shape: const StadiumBorder(),
      side: BorderSide(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// The one case where the composer still owes an explanation: the Relay button
/// is disabled and nothing else on screen says why.
///
/// A line, not a panel — and only while it applies. The permanent "you need
/// more tokens" banner it replaces was on screen for everyone, including the
/// people it did not concern.
class _ShortOnTokensHint extends StatelessWidget {
  const _ShortOnTokensHint({required this.needed, required this.onEarnTokens});

  final int needed;
  final VoidCallback onEarnTokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Row(
      children: [
        Icon(Icons.info_outline, size: 16, color: theme.colorScheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.economyComposerShort(needed),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        TextButton(
          onPressed: onEarnTokens,
          child: Text(l10n.economyComposerEarnAction),
        ),
      ],
    );
  }
}

/// The "one thing still missing before this can be relayed" line, in the row
/// above the Relay button it explains.
///
/// A line rather than a snackbar, for the reason given on [_PublishBlocker]:
/// a snackbar covers the toolbar, and the toolbar holds the very control the
/// message is asking the author to use.
class _PublishBlockerHint extends StatelessWidget {
  const _PublishBlockerHint({required this.blocker});

  final _PublishBlocker blocker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final message = switch (blocker) {
      _PublishBlocker.noChannel => l10n.createPostPickChannelError,
      _PublishBlocker.emptyPost => l10n.createPostEmptyPostError,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One picked photo/video, as a full-width row in the block editor.
///
/// Drawn at the shape it will actually publish in — for a photo that is exactly
/// the cropper's output, and for a video it is the frame the server will crop
/// to. So the composer is a preview of the post, not an approximation of it.
///
/// Video still shows a neutral tile rather than a decoded frame: extracting one
/// would mean spinning up a player per picked clip inside a list the author is
/// dragging rows around in.
class _ComposerMediaTile extends StatelessWidget {
  const _ComposerMediaTile({required this.item});

  final _PickedItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: item.aspectRatio,
        child: item.isVideo
            ? ColoredBox(
                color: Colors.black87,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.play_circle_outline,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.composerVideoWillBeCropped,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              )
            : Image.memory(item.bytes, fit: BoxFit.cover),
      ),
    );
  }
}
