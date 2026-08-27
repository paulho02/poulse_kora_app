import 'package:flutter/material.dart';

import '../../../core/avatars/presentation/user_avatar.dart';
import '../data/post.dart';

/// The avatar shown beside a post's author, wherever a post is rendered — the
/// feed card, the feed detail sheet and the history detail sheet.
///
/// Kept in one place because the anonymity rule belongs in one place: an
/// anonymous post shows the neutral glyph and never a picture or a monogram, and
/// that must not depend on which screen happens to be drawing the post.
///
/// The backend already enforces it (an anonymous post carries no author at all,
/// so [PostAuthor.profilePictureUrl] is null before this widget sees it); the
/// check here is what keeps the *placeholder* right, not what keeps the picture
/// secret.
class PostAuthorAvatar extends StatelessWidget {
  const PostAuthorAvatar({super.key, required this.post, required this.radius});

  final Post post;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (post.isAnonymous) {
      return CircleAvatar(
        radius: radius,
        child: Icon(Icons.person_outline, size: radius * 1.15),
      );
    }
    final username = post.author.username ?? '?';
    return UserAvatar(
      imageUrl: post.author.profilePictureUrl,
      radius: radius,
      fallback: MonogramAvatar(seed: username, radius: radius),
    );
  }
}
