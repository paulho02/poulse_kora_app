import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/media/presentation/network_media_image.dart';
import '../data/post.dart';

/// Rectangular equivalent of `UserAvatar` for a post-media *image* — and for a
/// video's **poster frame**, which is just another image URL, so an unplayed clip
/// costs one small JPEG rather than a video fetch.
///
/// A plain network image, like every other image in the app now: these URLs are
/// presigned and carry their own authorization, so there is no token to attach
/// and no byte cache to keep. See [NetworkMediaImage].
class PostMediaImage extends StatelessWidget {
  const PostMediaImage({super.key, required this.url, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return NetworkMediaImage(
      url: url,
      fit: fit,
      fallback: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    );
  }
}

/// A photo, or a video's poster frame, filling its parent — the one widget
/// that knows how to draw "what this attachment looks like" without playing
/// anything.
///
/// Falls back to a neutral surface only when there is genuinely nothing to
/// show: an old post's video from before posters existed, or one whose frame
/// extraction failed server-side (deliberately non-fatal, see the backend's
/// `_extract_poster`).
class PostMediaPreview extends StatelessWidget {
  const PostMediaPreview({
    super.key,
    required this.media,
    this.fit = BoxFit.cover,
  });

  final PostMedia media;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final url = media.previewUrl;
    if (url == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      );
    }
    return PostMediaImage(url: url, fit: fit);
  }
}

/// A post's `media.first` (position 0), sized for the feed card. Deliberately
/// the only place a post's media appears before the detail view is opened —
/// tapping the card is the sole entry point into the real player, so nothing
/// here autoplays or streams video: a clip shows its poster frame, which is a
/// small JPEG stored as its own object.
///
/// Sized by the item's real aspect ratio when the backend reported one, so a
/// portrait photo reads as portrait on the card instead of being squashed into
/// a landscape window. Falls back to 4:3 for media uploaded before dimensions
/// were recorded.
///
/// [minAspectRatio] is why a card is not simply the post at true shape: a 4:5
/// photo across a ~350dp card is ~440dp tall, which pushes the drop/forward
/// buttons off screen and makes the feed unscannable. A card is a *preview* —
/// so a taller-than-square item is centre-cropped here and shown at its real
/// shape once the post is opened, where there is a whole screen for it.
class PostMediaThumbnail extends StatelessWidget {
  const PostMediaThumbnail({
    super.key,
    required this.media,
    this.minAspectRatio = 1,
  });

  final PostMedia media;
  final double minAspectRatio;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: math.max(media.aspectRatio ?? 4 / 3, minAspectRatio),
        child: media.isVideo
            ? _VideoPreviewTile(media: media)
            : PostMediaPreview(media: media),
      ),
    );
  }
}

/// Video's feed-card representation: its poster frame under a play glyph, so an
/// unplayed clip looks like the photo it is a moment of rather than a black
/// rectangle. Still never a decoded frame *from the clip itself* — that would
/// mean downloading video bytes to render a scrolling-list card, which is
/// exactly what the poster exists to avoid.
class _VideoPreviewTile extends StatelessWidget {
  const _VideoPreviewTile({required this.media});

  final PostMedia media;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final duration = media.durationSeconds;
    return Stack(
      fit: StackFit.expand,
      children: [
        media.posterUrl != null
            ? PostMediaPreview(media: media)
            : const ColoredBox(color: Colors.black87),
        // Keeps the glyph legible over a bright frame without dimming the
        // picture the way a full-surface scrim would.
        const _PlayBadge(size: 34),
        if (duration != null)
          Positioned(
            right: 6,
            bottom: 6,
            child: DurationBadge(seconds: duration),
          ),
        Positioned.fill(
          child: Semantics(
            label: l10n.postMediaPlayVideo,
            child: const SizedBox(),
          ),
        ),
      ],
    );
  }
}

/// The play glyph itself: a translucent disc so it reads against both a dark
/// and a blown-out poster frame.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: size * 0.66,
        ),
      ),
    );
  }
}

/// `m:ss` badge for a clip's length.
class DurationBadge extends StatelessWidget {
  const DurationBadge({super.key, required this.seconds});

  final double seconds;

  @override
  Widget build(BuildContext context) {
    final total = seconds.round();
    final label = '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
    );
  }
}

/// Small "+N" corner badge for a thumbnail representing more than one media
/// item (N = the items not shown).
class PostMediaCountBadge extends StatelessWidget {
  const PostMediaCountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '+$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
