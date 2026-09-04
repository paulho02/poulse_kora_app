import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/media_reload.dart';

/// Every image the backend hands us — a profile picture, a post photo, a video's
/// poster frame — drawn straight from its URL.
///
/// It is a plain `Image.network` and that is the point. These used to be fetched
/// as bytes through the authenticated Dio client and rendered with
/// `Image.memory`, because the routes serving them required the bearer token and
/// an `<img>` cannot send one. The backend now hands out **presigned bucket
/// URLs** instead (see `app/core/storage.py` there): the signature in the query
/// string is the whole authorization, the bytes never pass through the backend,
/// and attaching an `Authorization` header would in fact make S3 *reject* the
/// request. So the memo caches, their eviction rules and their offline/session
/// bookkeeping are all gone — Flutter's own `ImageCache` (and, on web, the
/// browser's HTTP cache) does that work, and does it better.
///
/// Two things make that caching actually land, and both live on the backend:
/// the presigned URL is quantized so it stays byte-identical for ~15 minutes
/// rather than changing per request, and every object carries
/// `Cache-Control: private, max-age=86400, immutable`. Without the first, every
/// feed refresh would be a cache miss on every image.
///
/// [mediaReloadProvider] is the one piece of manual control kept — see there.
class NetworkMediaImage extends ConsumerWidget {
  const NetworkMediaImage({
    super.key,
    required this.url,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  final String url;

  /// Shown while loading, and instead of the image if it fails.
  ///
  /// Deliberately the same widget for both: media here is decoration around
  /// content that already reads fine without it, so a spinner would be more
  /// distracting than the placeholder it replaces a moment later — and a feed
  /// full of them would jitter on every scroll.
  final Widget fallback;

  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reloadToken = ref.watch(mediaReloadProvider);
    return Image.network(
      url,
      // Part of the key rather than of the URL: changing the URL would change
      // what gets signed and cached, while this only forces the widget to
      // re-resolve the same image.
      key: ValueKey('$url#$reloadToken'),
      fit: fit,
      width: width,
      height: height,
      // Keeps the old pixels up while a *different* URL loads, instead of
      // blanking to the placeholder first. That is what a replaced profile
      // picture now looks like: the key changes (a new object key per upload),
      // and without this the face would visibly disappear for a beat.
      gaplessPlayback: true,
      // Web only, and no-op elsewhere. `fallback` (not `prefer`) keeps the
      // normal byte-fetching path — full Flutter image handling — and drops to
      // an `<img>` element only when the fetch is blocked. That is the case
      // worth covering here: a cross-origin fetch needs CORS on the bucket, and
      // a Railway Bucket currently offers no way to set it (the injected
      // credentials have no `s3:PutBucketCors`). An `<img>` is not subject to
      // CORS, so this is what keeps web images working without one. Video needs
      // no equivalent — `video_player_web` renders into a bare `<video>`
      // element, which is not CORS-gated either.
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      errorBuilder: (context, error, stackTrace) => fallback,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return fallback;
      },
    );
  }
}
