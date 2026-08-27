import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../data/avatar_cache.dart';

/// One cache per app, shared by every avatar on every screen — that sharing is
/// the whole point (see [AvatarCache]). Kept as a plain `Provider` holding a
/// mutable object rather than a `FutureProvider.family` keyed by URL, because
/// the cache has to outlive the widgets watching it: feed cards are disposed and
/// rebuilt constantly while scrolling, and an auto-disposed family would drop
/// each image the moment its card scrolled off.
final avatarCacheProvider = Provider<AvatarCache>((ref) {
  return AvatarCache(ref.watch(dioClientProvider).dio);
});
