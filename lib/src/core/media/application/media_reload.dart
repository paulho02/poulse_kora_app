import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A counter every network image on screen keys itself by, so bumping it makes
/// all of them load again.
///
/// This is the small remainder of what used to be two whole `AuthenticatedByteCache`
/// instances. Media now comes from presigned bucket URLs that need no bearer
/// token (see the backend's `app/core/storage.py`), so `Image.network` does the
/// fetching, the decoding, the memoizing and the eviction — and on web the
/// browser's own HTTP cache does it. What Flutter's caches cannot do by
/// themselves is the one thing those classes were also carrying:
///
/// - **Reconnecting.** An image that failed while offline is a resolved failure
///   for the widget holding it; nothing retries on its own. Bumping this after
///   `backOnline` is what gives every avatar and photo on screen another go.
/// - **A session boundary.** Flutter's image cache is keyed by URL and would
///   happily paint the previous account's faces at the start of the next
///   session. Signing in or out clears it, and the bump forces anything already
///   mounted to re-resolve rather than keep pixels fetched as someone else.
class MediaReloadNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Drop what Flutter has cached and make mounted widgets fetch again.
  ///
  /// Both halves are needed and neither is enough alone: clearing the cache does
  /// not disturb an already-resolved `ImageStream`, and bumping the counter
  /// alone would re-resolve straight back into the cached failure.
  void reload() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    state = state + 1;
  }
}

final mediaReloadProvider = NotifierProvider<MediaReloadNotifier, int>(
  MediaReloadNotifier.new,
);
