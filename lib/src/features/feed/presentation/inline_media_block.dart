import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/media/application/active_video.dart';
import '../../../core/media/data/media_video_source.dart';
import '../../../core/media/presentation/video_player_surface.dart';
import '../data/post.dart';
import 'post_media_thumbnail.dart'
    show DurationBadge, PostMediaImage, PostMediaPreview;

/// How long a video is given to start playing before giving up and showing an
/// error instead of spinning forever.
const _kVideoInitTimeout = Duration(seconds: 20);

/// Fallback shape for media the backend never measured — everything uploaded
/// before `PostMedia.width/height` existed. Those rows are not backfilled and
/// may be any shape, so the block is letterboxed (`BoxFit.contain`) inside this
/// box rather than cropped to it: padding an old photo is recoverable, cutting
/// it in half is not.
const _kUnknownRatio = 4 / 3;

/// A clip pauses once this little of it is left on screen. Not zero: a block
/// hanging one pixel into the viewport is gone for viewing purposes, and waiting
/// for the last pixel would leave audio playing from something nobody can see.
/// Not a half either, which would stop a clip while it is still being watched at
/// the top of the screen.
const _kPauseBelowVisibleFraction = 0.25;

/// One media block rendered inline among a post's text paragraphs (see
/// `post_detail_view.dart` / `history_post_detail_sheet.dart`) — full width, at
/// its actual position in the article, not grouped into a separate swipeable
/// gallery the way earlier versions of the detail sheet did.
///
/// Everything published now is 4:3 or 4:5 (see `core/media/post_media_format.dart`),
/// and the block is laid out from those dimensions *before* any bytes arrive —
/// so opening a post no longer reflows as each image decodes.
///
/// A video starts as its **poster frame** under a play button and only creates a
/// real [VideoPlayerController] once tapped — lazy per block, so opening a
/// text-heavy post with several videos doesn't fire several concurrent
/// authenticated video fetches just because the view was opened. The poster is
/// what stops an unplayed clip from being a black rectangle; it costs one small
/// JPEG from its own route, never a byte of the clip. Once playing, the chrome
/// is [VideoPlayerSurface] — see there for why it isn't chewie's.
///
/// A clip then loops until **something takes it off screen or out of focus**:
/// the viewer pauses it, another clip is started ([activeVideoProvider]), it is
/// scrolled out of the viewport, or the app is backgrounded. Those last three
/// are not polish — a post can hold five media items, and leaving a scrolled-past
/// clip running is what produced the two bugs this block used to have: a clip
/// heard but not seen (its audio under the one you were actually watching) and a
/// clip stuck on a spinner (two authenticated streams competing for Android's
/// decoders). Pausing is deliberate where tearing the controller down would also
/// work: scrolling back finds the clip where you left it, one tap from resuming,
/// instead of back at its poster with the download to do again.
class InlineMediaBlock extends ConsumerStatefulWidget {
  const InlineMediaBlock({
    super.key,
    required this.media,
    this.borderRadius = 12,
  });

  final PostMedia media;

  /// Zero where the block runs edge to edge (the full-screen post view), the
  /// card radius where it sits inline in padded content.
  final double borderRadius;

  @override
  ConsumerState<InlineMediaBlock> createState() => _InlineMediaBlockState();
}

class _InlineMediaBlockState extends ConsumerState<InlineMediaBlock>
    with WidgetsBindingObserver {
  VideoPlayerController? _videoController;
  void Function()? _videoCleanup;
  bool _loading = false;
  bool _failed = false;

  /// This block's claim on [activeVideoProvider]. Identity is the whole point —
  /// two blocks showing the same media item are still two players.
  final Object _playbackToken = Object();

  /// The list this block scrolls in, if any. Watched rather than wrapped in a
  /// notification listener because scroll notifications travel *up* from the
  /// scrollable, and this block sits below it.
  ScrollPosition? _scrollPosition;

  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position == _scrollPosition) return;
    _scrollPosition?.removeListener(_onScroll);
    _scrollPosition = position;
    position?.addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollPosition?.removeListener(_onScroll);
    // No `release` here on purpose: `ref` is not safe to touch this late, and a
    // claim left behind by a disposed block is inert — it matches no live token,
    // so every block is already paused, and the next claim overwrites it.
    _videoController?.removeListener(_onPlaybackChanged);
    _videoController?.dispose();
    _videoCleanup?.call();
    super.dispose();
  }

  /// Backgrounding the app is "off screen" too — and on Android it is also when
  /// the platform can take the player's surface away, which is the state a clip
  /// used to come back from playing sound over a frozen picture.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _videoController?.pause();
  }

  /// The claim is made from the *player*, not from the button that started it:
  /// playback resumes from the poster, from the surface's own play button, and
  /// one day from somewhere else again — this way every one of them counts.
  void _onPlaybackChanged() {
    final playing = _videoController?.value.isPlaying ?? false;
    if (playing == _wasPlaying || !mounted) return;
    _wasPlaying = playing;
    final active = ref.read(activeVideoProvider.notifier);
    if (playing) {
      active.claim(_playbackToken);
    } else {
      active.release(_playbackToken);
    }
  }

  void _onScroll() {
    final controller = _videoController;
    if (!mounted || controller == null || !controller.value.isPlaying) return;
    if (_visibleFraction() >= _kPauseBelowVisibleFraction) return;
    controller.pause();
  }

  /// How much of the block is on screen, 0 (gone) to 1 (fully visible).
  ///
  /// Measured against the window rather than the scrollable's own viewport: the
  /// post view is full-screen, so the two agree closely enough for a decision
  /// this coarse, and it costs one `localToGlobal` per scroll tick instead of a
  /// viewport walk.
  double _visibleFraction() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize || box.size.height == 0) {
      return 1;
    }
    final blockRect = box.localToGlobal(Offset.zero) & box.size;
    final windowRect = Offset.zero & MediaQuery.sizeOf(context);
    final visible = blockRect.intersect(windowRect);
    if (visible.isEmpty || visible.height <= 0) return 0;
    return visible.height / blockRect.height;
  }

  Future<void> _play() async {
    // The poster's button is replaced by a spinner on the next frame, but a
    // second controller for the same block would leak the first one — still
    // playing, now with nothing drawing it.
    if (_loading || _videoController != null) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final source = await videoSourceFor(ref, widget.media.url);
      await source.controller.initialize().timeout(_kVideoInitTimeout);
      if (!mounted) {
        await source.controller.dispose();
        source.dispose?.call();
        return;
      }
      source.controller.addListener(_onPlaybackChanged);
      setState(() {
        _videoController = source.controller;
        _videoCleanup = source.dispose;
        _loading = false;
      });
      // A post's clip runs to a minute at most, so it loops rather than ending
      // on a frozen last frame with a replay button over it — the same reason
      // the chrome lives along the bottom edge: watching is never interrupted
      // by something drawn on the picture. Pausing is still how it stops.
      await source.controller.setLooping(true);
      // Tapping the poster *is* the request to play, so the surface is only ever
      // mounted onto a clip already running.
      await source.controller.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Someone else started a clip: whatever this block was doing, it stops. The
    // controller stays, so the frame and the position survive for a resume.
    ref.listen(activeVideoProvider, (previous, next) {
      if (next != _playbackToken) _videoController?.pause();
    });

    final media = widget.media;
    final knownRatio = media.aspectRatio;

    if (!media.isVideo) {
      return _framed(
        ratio: knownRatio ?? _kUnknownRatio,
        child: PostMediaImage(
          url: media.url,
          // An exact fit when the shape is known, so a 4:3 photo fills its 4:3
          // box with no crop and no letterbox; padded when it isn't.
          fit: knownRatio != null ? BoxFit.cover : BoxFit.contain,
        ),
      );
    }

    final videoController = _videoController;
    if (videoController != null) {
      // A track the platform can parse but not *decode* reports 0x0, whose
      // aspect ratio is NaN - which throws out of layout rather than showing
      // anything. The backend now normalizes every upload to H.264 so this
      // shouldn't happen (see media_validation.py: _transcode_video), but a
      // codec the player silently can't handle must degrade to a visible
      // error, never a crash.
      final ratio = videoController.value.aspectRatio;
      if (!ratio.isFinite || ratio <= 0) {
        return _framed(
          ratio: knownRatio ?? _kUnknownRatio,
          child: const _ErrorSurface(),
        );
      }
      return _framed(
        ratio: ratio,
        child: VideoPlayerSurface(controller: videoController),
      );
    }

    return _framed(
      ratio: knownRatio ?? _kUnknownRatio,
      child: _VideoPoster(
        media: media,
        loading: _loading,
        failed: _failed,
        onPlay: _play,
      ),
    );
  }

  Widget _framed({required double ratio, required Widget child}) => ClipRRect(
    borderRadius: BorderRadius.circular(widget.borderRadius),
    child: AspectRatio(aspectRatio: ratio, child: child),
  );
}

/// An unplayed clip: its poster frame, a play button, and the clip's length.
///
/// The scrim is deliberately light and only under the controls — the frame is
/// the point, and dimming the whole thing would put back the "why is this
/// black?" feeling the poster exists to remove.
class _VideoPoster extends StatelessWidget {
  const _VideoPoster({
    required this.media,
    required this.loading,
    required this.failed,
    required this.onPlay,
  });

  final PostMedia media;
  final bool loading;
  final bool failed;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final duration = media.durationSeconds;
    final hasPoster = media.posterUrl != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasPoster)
          PostMediaPreview(media: media)
        else
          const ColoredBox(color: Colors.black87),
        if (failed)
          const _ErrorSurface()
        else if (loading)
          const ColoredBox(
            color: Colors.black26,
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          )
        else
          Center(
            child: Material(
              color: Colors.black.withValues(alpha: 0.45),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPlay,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 40,
                    color: Colors.white,
                    semanticLabel: l10n.postMediaPlayVideo,
                  ),
                ),
              ),
            ),
          ),
        if (duration != null && !loading && !failed)
          Positioned(
            right: 8,
            bottom: 8,
            child: DurationBadge(seconds: duration),
          ),
      ],
    );
  }
}

class _ErrorSurface extends StatelessWidget {
  const _ErrorSurface();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Icon(Icons.error_outline, color: Colors.white70, size: 32),
      ),
    );
  }
}
