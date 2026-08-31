import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/media/application/media_providers.dart';
import '../../../core/media/data/authenticated_byte_cache.dart';
import '../data/post.dart';

/// Rectangular equivalent of `UserAvatar` for a post-media *image*'s bytes -
/// fetched through the authenticated Dio client and memoized in
/// `postMediaImageCacheProvider`, the same shape as avatars for the same reason
/// (the serving route requires the bearer token).
class PostMediaImage extends ConsumerStatefulWidget {
  const PostMediaImage({super.key, required this.url, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  ConsumerState<PostMediaImage> createState() => _PostMediaImageState();
}

class _PostMediaImageState extends ConsumerState<PostMediaImage> {
  Uint8List? _bytes;
  late final AuthenticatedByteCache _cache;

  @override
  void initState() {
    super.initState();
    _cache = ref.read(postMediaImageCacheProvider)
      ..addListener(_onCacheChanged);
    _resolve();
  }

  @override
  void dispose() {
    _cache.removeListener(_onCacheChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PostMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = null;
      _resolve();
    }
  }

  void _onCacheChanged() {
    final url = widget.url;
    if (_cache.isResolved(url)) return;
    _cache.load(url).then((bytes) {
      if (!mounted || widget.url != url) return;
      setState(() => _bytes = bytes);
    });
  }

  void _resolve() {
    final url = widget.url;
    if (_cache.isResolved(url)) {
      _bytes = _cache.peek(url);
      return;
    }
    _cache.load(url).then((bytes) {
      if (!mounted || widget.url != url) return;
      setState(() => _bytes = bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      );
    }
    return Image.memory(bytes, fit: widget.fit);
  }
}

/// A post's `media.first` (position 0), sized for the feed card. Deliberately
/// the only place a post's media appears before the detail sheet is opened -
/// tapping the card is the sole entry point into the real gallery/player, so
/// nothing here autoplays or streams video.
///
/// Sized by aspect ratio, not a fixed height: a fixed ~80px strip on a
/// ~350dp-wide card cropped most photos into an unrecognisable sliver.
/// A 4:3 window is wide enough to read a landscape photo and tall enough
/// that a cover-fit portrait one doesn't lose its subject.
class PostMediaThumbnail extends StatelessWidget {
  const PostMediaThumbnail({
    super.key,
    required this.media,
    this.aspectRatio = 4 / 3,
  });

  final PostMedia media;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: media.isVideo
            ? _VideoPlaceholderTile(media: media)
            : PostMediaImage(url: media.url),
      ),
    );
  }
}

/// Video's feed-card representation: a neutral tile with a play glyph, never a
/// decoded frame. Extracting a thumbnail frame would mean downloading video
/// bytes just to render a scrolling-list card, which fights the entire point
/// of the backend's Range-based lazy playback (see http_range.py server-side).
class _VideoPlaceholderTile extends StatelessWidget {
  const _VideoPlaceholderTile({required this.media});

  final PostMedia media;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final duration = media.durationSeconds;
    return ColoredBox(
      color: Colors.black87,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.play_circle_outline,
            color: Colors.white,
            size: 32,
            semanticLabel: l10n.postMediaPlayVideo,
          ),
          if (duration != null)
            Positioned(right: 6, bottom: 6, child: _DurationBadge(duration)),
        ],
      ),
    );
  }
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge(this.seconds);

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
