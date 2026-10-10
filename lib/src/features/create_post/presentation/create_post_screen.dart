import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/languages/language_providers.dart';
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
import 'language_picker_sheet.dart';
import 'token_spend_badge.dart';
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
enum _PublishBlocker { noChannel, emptyPost, noLanguage, languageNeedsNoText }

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int? _selectedChannelId;
  _PublishBlocker? _blocker;
  bool _isAnonymous = false;
  bool _isSubmitting = false;
  late final List<_ComposerBlock> _blocks = [_newTextBlock()];

  /// The language this post will be published in, and so who can receive it.
  ///
  /// Filled in by the on-device detector as the author types, until they open
  /// the picker themselves — from then on [_languageTouched] freezes it, because
  /// a detector that keeps overruling a deliberate choice is worse than no
  /// detector. Null means "not decided yet" and blocks publishing, rather than
  /// defaulting to the app's own language: a phone set to English is no evidence
  /// about the language someone is writing in, and a wrong guess here routes the
  /// post to people who cannot read it.
  String? _selectedLanguage;
  bool _languageTouched = false;

  /// What the detector last made of the text, kept even once the author has
  /// overridden it so the picker can still badge its suggestion.
  String? _detectedLanguage;
  Timer? _detectDebounce;

  /// The exact price for (channel, language), quoted by the backend and held
  /// for the current price window. Null while either half of the route is
  /// unchosen, or while the quote is in flight or failed — the channel's own
  /// range covers that case.
  PostPrice? _routePrice;

  /// Guards against an out-of-order quote: switching channel twice quickly can
  /// land the first response after the second, and the price shown must be the
  /// one for the route currently selected.
  int _priceRequest = 0;

  /// Drives the spend badge. Built in `initState` rather than as a `late final`
  /// initializer: that form is lazy, so a composer that never published would
  /// first construct the controller inside `dispose`, building a `Ticker`
  /// against an already-deactivated element.
  late final AnimationController _spendPop;

  /// What the post just cost, and the balance it came out of. Non-null only
  /// while the badge is on screen.
  int? _spentAmount;
  int _balanceBeforeSpend = 0;

  /// The keyboard's height at the last metrics change, to spot it closing.
  double _keyboardInset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _spendPop = AnimationController(vsync: this, duration: kTokenSpendPlay);
    // Refresh so the price reflects current congestion when opening the composer.
    Future.microtask(() => ref.read(economyProvider.notifier).refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _spendPop.dispose();
    _detectDebounce?.cancel();
    for (final block in _blocks) {
      if (block is _TextBlock) {
        block.controller
          ..removeListener(_onTextChanged)
          ..dispose();
      }
    }
    super.dispose();
  }

  /// Dropping focus when the keyboard goes away. A text block is multiline, so
  /// its keyboard has no "done" action: the author closes it with the system
  /// back gesture or the keyboard's own hide key, and Flutter keeps the field
  /// focused through either, caret still blinking. Only while this route is on
  /// top, so a sheet's own field closing its keyboard is left alone.
  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return;
    final inset = view.viewInsets.bottom;
    final closed = _keyboardInset > 0 && inset == 0;
    _keyboardInset = inset;
    if (closed && mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  /// Every text block is created through here so exactly one place has to
  /// remember to hook up language detection — a block added by any of the three
  /// paths that add one would otherwise be invisible to it.
  _TextBlock _newTextBlock([String initial = '']) {
    final block = _TextBlock(initial);
    block.controller.addListener(_onTextChanged);
    return block;
  }

  int get _mediaCount => _blocks.whereType<_MediaBlock>().length;
  int get _remainingMediaSlots => _kMaxMediaItems - _mediaCount;

  /// Whether the post carries any words at all. Drives whether "no language" is
  /// offerable: it means the post reaches every subscriber of the channel
  /// regardless of what they read, which is only honest when there is nothing
  /// to read.
  bool get _hasText => _blocks.whereType<_TextBlock>().any(
    (block) => block.controller.text.trim().isNotEmpty,
  );

  String get _allText => _blocks
      .whereType<_TextBlock>()
      .map((block) => block.controller.text)
      .join('\n');

  /// Re-run detection on a debounce as the author writes.
  ///
  /// Debounced because this fires per keystroke and a suggestion that changes
  /// mid-word is noise; 400ms is about the gap between words at speed, so the
  /// picker settles instead of flickering.
  void _onTextChanged() {
    _detectDebounce?.cancel();
    _detectDebounce = Timer(const Duration(milliseconds: 400), _redetect);
  }

  /// Re-read *all* the text and re-decide, from scratch.
  ///
  /// Deliberately a pure function of the post's current content rather than of
  /// what was typed most recently: the author can delete a block, and a
  /// suggestion derived from text that no longer exists is simply wrong. That
  /// is why every path which changes the *set* of blocks calls this too, not
  /// only the per-keystroke listener — removing the last German paragraph fires
  /// no controller notification at all, so detection used to sit on "German"
  /// over a post that had become entirely English.
  void _redetect() {
    if (!mounted) return;

    // No text left anywhere. Whatever was detected came from text the post no
    // longer contains, so it stops being evidence — clearing it also lets "no
    // language" become offerable again, which is the honest state for a post
    // that is now just a photo. An explicit choice is left alone: the author
    // answered this question themselves, and a video can be spoken German.
    if (!_hasText) {
      if (_detectedLanguage == null &&
          (_languageTouched || _selectedLanguage == null)) {
        return;
      }
      setState(() {
        _detectedLanguage = null;
        if (!_languageTouched) _selectedLanguage = null;
      });
      return;
    }

    final detected = ref.read(languageDetectorProvider).detect(_allText);
    // A null answer here means "there is text, but I am not confident" — too
    // short, or sitting between two languages. That must leave the choice
    // exactly where it is rather than clearing it, or typing into a half-
    // finished sentence would flicker the picker off and on.
    if (detected == null) return;
    setState(() {
      _detectedLanguage = detected;
      if (!_languageTouched) {
        _selectedLanguage = detected;
        if (_blocker == _PublishBlocker.noLanguage) _blocker = null;
      }
    });
  }

  /// Show what the post just cost, then hold a beat before the screen moves on.
  ///
  /// Awaited by `_submit`, so the navigation genuinely waits for it — the same
  /// shape as `PostCard._review`, which holds its forward score on screen
  /// before letting the card leave. Without the wait the badge would be built
  /// and torn down inside one frame.
  Future<void> _playSpend(int spent, int balanceBefore) async {
    setState(() {
      _spentAmount = spent;
      _balanceBeforeSpend = balanceBefore;
    });
    try {
      await _spendPop.forward(from: 0);
      await Future<void>.delayed(kTokenSpendHold);
    } on TickerCanceled {
      // Disposed mid-play; there is nothing left to show it on.
    }
    if (!mounted) return;
    setState(() => _spentAmount = null);
  }

  Future<void> _pickLanguage() async {
    final unspecified = ref.read(languageUnspecifiedProvider);
    final chosen = await showLanguagePickerSheet(
      context,
      selected: _selectedLanguage,
      allowUnspecified: !_hasText,
      suggested: _detectedLanguage,
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _selectedLanguage = chosen;
      // From here the detector stops proposing. The author has answered the
      // question it was guessing at, and re-guessing over them would make the
      // field feel like it was fighting back.
      _languageTouched = true;
      if (_blocker == _PublishBlocker.noLanguage ||
          _blocker == _PublishBlocker.languageNeedsNoText) {
        _blocker = null;
      }
      if (chosen != unspecified || !_hasText) _routePrice = null;
    });
    unawaited(_refreshRoutePrice());
  }

  /// Ask the backend what this exact (channel, language) route costs.
  ///
  /// A quote rather than an estimate: `POST /posts` charges this number until
  /// its window rolls over. A failure is deliberately silent — the channel's
  /// range is still on screen and still true, and an error toast for a price
  /// refresh would interrupt writing for something nobody asked for.
  Future<void> _refreshRoutePrice() async {
    final channelId = _selectedChannelId;
    final language = _selectedLanguage;
    if (channelId == null || language == null) {
      if (mounted && _routePrice != null) setState(() => _routePrice = null);
      return;
    }
    final request = ++_priceRequest;
    try {
      final quote = await ref
          .read(channelsRepositoryProvider)
          .fetchPostPrice(channelId: channelId, language: language);
      if (!mounted || request != _priceRequest) return;
      setState(() => _routePrice = quote);
    } catch (_) {
      if (!mounted || request != _priceRequest) return;
      setState(() => _routePrice = null);
    }
  }

  Future<void> _submit() async {
    final channelId = _selectedChannelId;
    if (channelId == null) {
      setState(() => _blocker = _PublishBlocker.noChannel);
      return;
    }
    final language = _selectedLanguage;
    if (language == null) {
      setState(() => _blocker = _PublishBlocker.noLanguage);
      return;
    }
    // Checked here rather than by mutating the selection when text appears: the
    // author chose "no language" deliberately, and silently switching it out
    // from under them once they typed a caption would be a worse surprise than
    // being told. The backend refuses this too - the check exists there because
    // it is the only side that can be trusted, and here so the refusal does not
    // cost an upload.
    if (language == ref.read(languageUnspecifiedProvider) && _hasText) {
      setState(() => _blocker = _PublishBlocker.languageNeedsNoText);
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

    // Read before the spend so the flash can be driven by what actually left
    // the balance, rather than by the quoted price. The two differ for a
    // superuser, who posts for free — and `record` refuses a zero, so they get
    // no flash rather than a "−0".
    final balanceBefore = ref.read(economyProvider)?.data.tokenBalance;

    setState(() => _isSubmitting = true);
    try {
      final result = await ref
          .read(feedRepositoryProvider)
          .createPost(
            channelId: channelId,
            blocks: blockInputs,
            language: language,
            isAnonymous: _isAnonymous,
            media: media,
          );
      // Posting spent tokens; sync the balance and refresh the (now higher) price.
      ref.read(economyProvider.notifier).setBalance(result.tokenBalance);
      // What actually left the balance, worked out now while both numbers are
      // in hand — `refresh()` below re-fetches and can move the balance again
      // for reasons that have nothing to do with this post. It is *recorded*
      // later, immediately before the navigation.
      final spent = balanceBefore == null
          ? 0
          : balanceBefore - result.tokenBalance;
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
        // the next one - noticed only after publishing to the wrong place.
        _selectedChannelId = null;
        // Cleared with the channel and for the same reason: the composer is a
        // tab in an IndexedStack, so a language left selected would be
        // inherited by a post written in a different one.
        _selectedLanguage = null;
        _languageTouched = false;
        _detectedLanguage = null;
        _routePrice = null;
        _blocker = null;
        _blocks
          ..clear()
          ..add(_newTextBlock());
      });
      // Played here, on the screen the author is still looking at, before the
      // navigation rather than after it — see `TokenSpendBadge`. A free post (a
      // superuser's) spends nothing and raises no badge.
      if (spent > 0 && balanceBefore != null) {
        await _playSpend(spent, balanceBefore);
        if (!mounted) return;
      }
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
  /// what the reader gets. An empty post raises the same blocker line the Publish
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
    // the next thing the author wants is the Publish button, not the keyboard.
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
        // The previous quote was for a different route, so it stops being a
        // quote the moment the channel changes. Cleared rather than left to be
        // overwritten, so the pill falls back to the new channel's range for
        // the moment the fetch is in flight instead of showing the old channel's
        // exact figure as if it applied here.
        _routePrice = null;
        if (_blocker == _PublishBlocker.noChannel) _blocker = null;
      });
      unawaited(_refreshRoutePrice());
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
  /// so it clears with the edit rather than waiting for the next Publish press.
  /// Call from inside a `setState`.
  void _clearEmptyPostBlocker() {
    if (_blocker == _PublishBlocker.emptyPost) _blocker = null;
  }

  void _addTextBlock() {
    setState(() {
      _blocks.add(_newTextBlock());
      _clearEmptyPostBlocker();
    });
  }

  void _removeBlock(int index) {
    setState(() {
      final block = _blocks.removeAt(index);
      if (block is _TextBlock) {
        block.controller
          ..removeListener(_onTextChanged)
          ..dispose();
      }
    });
    // Deleting a paragraph changes the post's text without any controller
    // firing, so detection has to be re-run by hand here or the suggestion
    // stays pinned to text that is gone. Immediate rather than debounced: this
    // is one deliberate action, not a stream of keystrokes.
    _redetect();
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
            priceOverride: _effectivePrice(selectedChannel),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Stacked so the spend badge lands centred over the editor — the same
      // place `ForwardScoreBadge` lands over the card it belongs to, and where
      // the author's eye already is. `Positioned.fill` + `Center` rather than
      // an alignment on the Stack itself, so the badge centres on the body
      // regardless of how tall the editor's own content happens to be.
      body: Stack(
        children: [
          ViewTip(
            tipKey: 'tip.create',
            message: l10n.createPostTipMessage,
            child: Builder(
              builder: (context) {
                if (economy == null) {
                  // `EconomyNotifier.refresh` swallows connectivity failures,
                  // so an offline first launch would otherwise spin here
                  // forever.
                  if (isOffline) {
                    return ErrorStateView(
                      error: PeerkolaApiException(
                        0,
                        'offline',
                        const {},
                        kind: ApiErrorKind.offline,
                      ),
                      onRetry: () =>
                          ref.read(economyProvider.notifier).refresh(),
                    );
                  }
                  return const Center(child: CircularProgressIndicator());
                }
                return channelsAsync.when(
                  data: (cached) => _buildEditor(context, cached.data),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => ErrorStateView(
                    error: error,
                    onRetry: () =>
                        ref.read(channelsNotifierProvider.notifier).refresh(),
                  ),
                );
              },
            ),
          ),
          if (_spentAmount != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: TokenSpendBadge(
                    spent: _spentAmount!,
                    balanceBefore: _balanceBeforeSpend,
                    animation: _spendPop,
                  ),
                ),
              ),
            ),
        ],
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
              // Publish is enabled — has to weigh the balance against the price
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

  /// What this post will actually be charged, or null while that is not yet
  /// knowable.
  ///
  /// The exact route quote when both a channel and a language are chosen; the
  /// channel's cheapest route while only the channel is. The low end rather
  /// than the high one, because this figure also gates the Publish button — and
  /// telling someone they cannot afford a post that a different language would
  /// in fact make affordable is a refusal they cannot act on. The exact number
  /// always arrives before they can publish, since a language is required.
  int? _effectivePrice(Channel? channel) =>
      _routePrice?.price ?? channel?.lowestPrice;

  /// The economy as it applies to *this* post: the viewer's balance, priced
  /// against the chosen route.
  ///
  /// Collapses the range onto the resolved price *once there is one*, and
  /// otherwise leaves the deployment-wide spread in place.
  ///
  /// Both halves matter. Collapsing when a price is known keeps the pill and
  /// the Publish button reading the same number — the affordability getters use
  /// the range's low end, so a leftover spread would let a cheap route in
  /// another channel vouch for this one, and the pill would read "Cost 4"
  /// beside an enabled button on a balance of 3. *Not* collapsing before then
  /// is what lets the composer open on "Cost 2–6" and narrow to "Cost 4" as the
  /// author picks: there is no single price yet, and showing the base rate
  /// instead would name a figure nobody is ever charged — which is the bug this
  /// replaced, and an invisible one, since a plausible number looks fine.
  Economy _effectiveEconomy(Economy economy, Channel? channel) {
    final price = _effectivePrice(channel);
    return price == null
        ? economy
        : economy.copyWith(
            postPrice: price,
            postPriceMin: price,
            postPriceMax: price,
          );
  }

  /// Everything that is not the article being written: the block-adding
  /// buttons, and the three decisions made at the moment of publishing
  /// (channel, anonymity, publish).
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
            // Once both halves of the route are chosen there *is* an exact
            // number, and saying so is the point: everything up to here has
            // been a range, and a figure that silently stops being a range
            // looks identical to one that never was. `_routePrice` is non-null
            // only for a quote the backend actually returned for this exact
            // (channel, language) pair, so this line never appears over an
            // interpolation or a stale channel figure.
            if (_routePrice != null) _ExactPriceLine(price: _routePrice!.price),
            // Only when it applies, and right above the button it explains —
            // the disabled Publish button is otherwise the only thing saying no,
            // and it can't say why.
            if (!economy.canAffordPost)
              _ShortOnTokensHint(
                needed: needed,
                onEarnTokens: () => context.go('/feed'),
              ),
            if (_blocker != null) _PublishBlockerHint(blocker: _blocker!),
            Row(
              children: [
                // The publishing decisions — where it goes, in what language,
                // under whose name — in a `Wrap` rather than a scroller.
                //
                // A horizontal scroller was the wrong shape for this: three
                // chips and a button do not fit a phone, and a control that has
                // to be scrolled into view is a control nobody knows is there.
                // The language chip in particular is *required*, so hiding it
                // off-edge meant the composer refused to publish over something
                // the author could not see. Wrapping grows the toolbar by one
                // chip-height only on the screens that actually need it, which
                // is the cost worth paying — the fixed second row this replaced
                // would have taken that height from the editor everywhere.
                //
                // Ordered destination-first so it is the anonymity toggle that
                // drops to a second line, never one half of the routing key.
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _ChannelSelectorChip(
                        channel: selectedChannel,
                        hasError: _blocker == _PublishBlocker.noChannel,
                        onTap: () => _pickChannel(channels),
                      ),
                      _LanguageSelectorChip(
                        language: _selectedLanguage,
                        unspecified: ref.watch(languageUnspecifiedProvider),
                        hasError:
                            _blocker == _PublishBlocker.noLanguage ||
                            _blocker == _PublishBlocker.languageNeedsNoText,
                        onTap: _pickLanguage,
                      ),
                      FilterChip(
                        label: Text(l10n.postAnonymous),
                        avatar: Icon(
                          _isAnonymous
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 16,
                        ),
                        selected: _isAnonymous,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        onSelected: _onAnonymousChanged,
                      ),
                    ],
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
                  child: Text(l10n.createPostPublish),
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
                  // Opts out of the app-wide filled field
                  // (`AppTheme.inputDecorationTheme`). A text block is not a
                  // form field — it is the post, rendered where the post goes,
                  // and a grey slab behind it would wrap every paragraph in a
                  // control the reader will never see.
                  filled: false,
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

  /// Publish was pressed with no channel picked - the chip turns error-coloured
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

/// The chosen language as a chip, beside the channel one.
///
/// It sits in the publish row for the same reason the channel does: both are
/// decisions about *where the post goes*, made at the moment of publishing,
/// rather than anything about the writing. Unpicked it reads as a prompt.
///
/// The detector fills this in as the author types, so in the ordinary case it
/// is already answered by the time anyone looks at it — which is the point.
/// What it must never do is look answered when it is not: an unset language
/// blocks publishing rather than defaulting to the app's own language, because
/// a phone set to English is no evidence about what someone is writing.
class _LanguageSelectorChip extends StatelessWidget {
  const _LanguageSelectorChip({
    required this.language,
    required this.unspecified,
    required this.hasError,
    required this.onTap,
  });

  final String? language;
  final String unspecified;
  final bool hasError;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final code = language;
    final color = code == null
        ? (hasError ? theme.colorScheme.error : theme.colorScheme.primary)
        : (hasError ? theme.colorScheme.error : theme.colorScheme.outline);

    final label = switch (code) {
      null => l10n.composerLanguagePick,
      final value when value == unspecified => l10n.contentLanguageNone,
      final value => contentLanguageLabel(l10n, value),
    };

    return ActionChip(
      onPressed: onTap,
      tooltip: l10n.composerLanguageTitle,
      avatar: Icon(
        code == unspecified ? Icons.image_outlined : Icons.translate,
        size: 16,
        color: color,
      ),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      shape: const StadiumBorder(),
      side: BorderSide(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// "Price based on your selection: 4" — shown only once the author has picked
/// both a channel and a language.
///
/// The pill in the app bar already states the number, but not that it has
/// *become exact*. It counts down from a range as the author decides, and the
/// moment it lands on one figure is the moment worth naming — otherwise the
/// difference between "somewhere in 2–6" and "4, guaranteed" is a silent one.
class _ExactPriceLine extends StatelessWidget {
  const _ExactPriceLine({required this.price});

  final int price;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Semantics(
      label: l10n.composerExactPriceSemantics(price),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(
              Icons.toll_outlined,
              size: 15,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.composerExactPriceLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$price',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one case where the composer still owes an explanation: the Publish button
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

/// The "one thing still missing before this can be published" line, in the row
/// above the Publish button it explains.
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
      _PublishBlocker.noLanguage => l10n.createPostNeedsLanguage,
      _PublishBlocker.languageNeedsNoText => l10n.createPostLanguageNeedsNoText,
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
