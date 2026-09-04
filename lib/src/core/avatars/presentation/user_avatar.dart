import 'package:flutter/material.dart';

import '../../media/presentation/network_media_image.dart';
import '../../theme/app_colors.dart';

/// A user's profile picture, with [fallback] shown until — or unless — there is
/// one to display.
///
/// A plain network image: the backend hands out a presigned bucket URL that
/// carries its own authorization, so this no longer needs the bearer token, the
/// Dio client, or the memo cache that existed to make those workable. See
/// [NetworkMediaImage].
///
/// A replaced picture arrives on its own now, too. Every upload writes a new
/// object key, so the URL genuinely changes and this widget's inputs change with
/// it — which is why there is no eviction call anywhere any more. It used to be
/// derived from the user id, identical before and after, and nothing on screen
/// could notice the swap.
///
/// There is deliberately no spinner. An avatar is decoration around a name that
/// is already legible, so a loading state would be more distracting than the
/// monogram it replaces a moment later — and swapping a spinner for an image
/// would make every feed card jitter on scroll.
class UserAvatar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null) return fallback;
    return ClipOval(
      child: NetworkMediaImage(
        url: url,
        fallback: fallback,
        width: radius * 2,
        height: radius * 2,
      ),
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
