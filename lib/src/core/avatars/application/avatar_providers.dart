import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../media/data/authenticated_byte_cache.dart';
import '../../providers.dart';

/// One cache per app, shared by every avatar on every screen — that sharing is
/// the whole point (see [AuthenticatedByteCache]). Kept as a plain `Provider`
/// holding a mutable object rather than a `FutureProvider.family` keyed by URL,
/// because the cache has to outlive the widgets watching it: feed cards are
/// disposed and rebuilt constantly while scrolling, and an auto-disposed family
/// would drop each image the moment its card scrolled off.
///
/// A separate instance from `postMediaImageCacheProvider`
/// (core/media/application/media_providers.dart) - not shared, so this cache's
/// eviction semantics (tied to profile-picture upload/session boundaries) don't
/// tangle with post images'.
final avatarCacheProvider = Provider<AuthenticatedByteCache>((ref) {
  return AuthenticatedByteCache(ref.watch(dioClientProvider).dio);
});
