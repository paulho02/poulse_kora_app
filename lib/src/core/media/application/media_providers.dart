import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../data/authenticated_byte_cache.dart';

/// One cache per app for post images (`PostMediaRead.url` where `media_type` is
/// `"image"`), shared by every feed card and gallery page — same reasoning as
/// `avatarCacheProvider`. Kept separate from it deliberately: avatar eviction is
/// tied to profile-picture upload/session boundaries, and this shouldn't tangle
/// with that.
///
/// Post *video* deliberately does not go through a byte cache at all — see
/// `videoControllerFor` in `media_video_source.dart`.
final postMediaImageCacheProvider = Provider<AuthenticatedByteCache>((ref) {
  return AuthenticatedByteCache(ref.watch(dioClientProvider).dio);
});
