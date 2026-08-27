import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_colors.dart';
import '../application/avatar_providers.dart';
import '../data/avatar_cache.dart';

/// A user's profile picture, with [fallback] shown until — or unless — there is
/// one to display.
///
/// The picture is fetched as bytes through the authenticated Dio client and
/// memoized (see [AvatarCache]); it cannot be an `Image.network`, because the
/// backend route requires the bearer token.
///
/// There is deliberately no spinner. An avatar is decoration around a name that
/// is already legible, so a loading state would be more distracting than the
/// monogram it replaces a moment later — and swapping a spinner for an image
/// would make every feed card jitter on scroll.
class UserAvatar extends ConsumerStatefulWidget {
  const UserAvatar({
    super.key,
    required this.imageUrl,
    required this.radius,
    required this.fallback,
  });

  /// `PostAuthor.profile_picture_url` / `UserRead.profile_picture_url`. Null both
  /// when the user has no picture and when the post is anonymous — the backend
  /// withholds the whole author, so there is nothing here to leak.
  final String? imageUrl;
  final double radius;

  /// Shown while loading, when there is no picture, and when fetching one fails.
  final Widget fallback;

  @override
  ConsumerState<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends ConsumerState<UserAvatar> {
  Uint8List? _bytes;
  late final AvatarCache _cache;

  @override
  void initState() {
    super.initState();
    _cache = ref.read(avatarCacheProvider)..addListener(_onCacheChanged);
    _resolve();
  }

  @override
  void dispose() {
    _cache.removeListener(_onCacheChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _bytes = null;
      _resolve();
    }
  }

  /// The cache dropped something. If it was ours, fetch it again.
  ///
  /// This is what makes a replaced picture appear immediately: the URL is
  /// unchanged, so [didUpdateWidget] above cannot detect the swap and this
  /// notification is the only signal that arrives.
  void _onCacheChanged() {
    final url = widget.imageUrl;
    if (url == null || _cache.isResolved(url)) return;

    // Note the old pixels are left on screen while the new ones load, rather
    // than blanking to the monogram first — that would read as the picture
    // being lost for a moment every time it is changed.
    _cache.load(url).then((bytes) {
      if (!mounted || widget.imageUrl != url) return;
      setState(() => _bytes = bytes);
    });
  }

  void _resolve() {
    final url = widget.imageUrl;
    if (url == null) return;

    // Synchronous hit: assign directly rather than going through the future, so
    // an already-cached picture is painted on the first frame instead of
    // flashing the monogram for one frame on every rebuild.
    if (_cache.isResolved(url)) {
      _bytes = _cache.peek(url);
      return;
    }

    _cache.load(url).then((bytes) {
      if (!mounted || widget.imageUrl != url) return;
      setState(() => _bytes = bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return widget.fallback;
    return CircleAvatar(
      radius: widget.radius,
      backgroundImage: MemoryImage(bytes),
    );
  }
}

/// The coloured initial shown when someone has no profile picture.
///
/// Factored out of the feed card, the detail sheets and the profile header,
/// which each grew their own copy of it. The colour is derived from the name
/// (see [AppColors.avatarColor]), so a given user keeps the same one everywhere.
class MonogramAvatar extends StatelessWidget {
  const MonogramAvatar({super.key, required this.seed, required this.radius});

  final String seed;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.avatarColor(seed),
      child: Text(
        seed.isNotEmpty ? seed[0].toUpperCase() : '?',
        style: TextStyle(
          // Tracks the radius so one widget covers the 12px feed card and the
          // 36px profile header alike.
          fontSize: radius * 0.8,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
