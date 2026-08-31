import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/media/data/media_video_source.dart';
import '../data/post.dart';
import 'post_media_thumbnail.dart' show PostMediaImage;

/// How long a video is given to start playing before giving up and showing an
/// error instead of spinning forever.
const _kVideoInitTimeout = Duration(seconds: 20);

/// A fixed height for the media area, image or video - the real aspect ratio
/// isn't known ahead of a video actually initializing (or, for images, without
/// decoding them first), so this bounds the block the same way
/// `PostMediaGallery` used to for the whole post's media.
const _kMediaHeight = 240.0;

/// One media block rendered inline among a post's text paragraphs (see
/// `post_detail_sheet.dart` / `history_post_detail_sheet.dart`) - full width,
/// at its actual position in the article, not grouped into a separate
/// swipeable gallery the way earlier versions of the detail sheet did.
///
/// A video starts as a tap-to-play tile and only creates a real
/// [VideoPlayerController] once tapped - lazy per block, so opening a
/// text-heavy post with several videos doesn't fire several concurrent
/// authenticated video fetches just because the sheet was opened.
class InlineMediaBlock extends ConsumerStatefulWidget {
  const InlineMediaBlock({super.key, required this.media});

  final PostMedia media;

  @override
  ConsumerState<InlineMediaBlock> createState() => _InlineMediaBlockState();
}

class _InlineMediaBlockState extends ConsumerState<InlineMediaBlock> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  void Function()? _videoCleanup;
  bool _loading = false;
  bool _failed = false;

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    _videoCleanup?.call();
    super.dispose();
  }

  Future<void> _play() async {
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
      setState(() {
        _videoController = source.controller;
        _videoCleanup = source.dispose;
        _chewieController = ChewieController(
          videoPlayerController: source.controller,
          autoPlay: true,
          looping: false,
        );
        _loading = false;
      });
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
    if (!widget.media.isVideo) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: _kMediaHeight,
          width: double.infinity,
          child: PostMediaImage(url: widget.media.url, fit: BoxFit.contain),
        ),
      );
    }

    final chewie = _chewieController;
    final videoController = _videoController;
    if (chewie != null && videoController != null) {
      // A track the platform can parse but not *decode* reports 0x0, whose
      // aspect ratio is NaN - which throws out of layout rather than showing
      // anything. The backend now normalizes every upload to H.264 so this
      // shouldn't happen (see media_validation.py: _transcode_video), but a
      // codec the player silently can't handle must degrade to a visible
      // error, never a crash.
      final ratio = videoController.value.aspectRatio;
      if (!ratio.isFinite || ratio <= 0) {
        return _errorTile();
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: ratio,
          child: Chewie(controller: chewie),
        ),
      );
    }

    final l10n = AppLocalizations.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: _kMediaHeight,
        width: double.infinity,
        child: ColoredBox(
          color: Colors.black87,
          child: Center(
            child: _loading
                ? const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  )
                : _failed
                ? const Icon(
                    Icons.error_outline,
                    color: Colors.white70,
                    size: 32,
                  )
                : IconButton(
                    iconSize: 48,
                    color: Colors.white,
                    tooltip: l10n.postMediaPlayVideo,
                    onPressed: _play,
                    icon: const Icon(Icons.play_circle_outline),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _errorTile() => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      height: _kMediaHeight,
      width: double.infinity,
      child: const ColoredBox(
        color: Colors.black87,
        child: Center(
          child: Icon(Icons.error_outline, color: Colors.white70, size: 32),
        ),
      ),
    ),
  );
}
