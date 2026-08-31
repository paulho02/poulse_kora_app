class PostAuthor {
  PostAuthor({
    required this.id,
    required this.username,
    required this.profilePictureUrl,
  });

  factory PostAuthor.fromJson(Map<String, dynamic> json) => PostAuthor(
    id: json['id'] as String?,
    username: json['username'] as String?,
    profilePictureUrl: json['profile_picture_url'] as String?,
  );

  final String? id;
  final String? username;

  /// Where to fetch the author's profile picture, or null if there is none.
  ///
  /// Also null on an anonymous post: the backend withholds the entire author
  /// (id and username included) rather than trusting the client to hide it, so
  /// there is nothing here that could give an anonymous poster away.
  final String? profilePictureUrl;
}

class PostMedia {
  PostMedia({
    required this.id,
    required this.mediaType,
    required this.contentType,
    required this.url,
    required this.durationSeconds,
  });

  factory PostMedia.fromJson(Map<String, dynamic> json) => PostMedia(
    id: json['id'] as int,
    mediaType: json['media_type'] as String,
    contentType: json['content_type'] as String,
    url: json['url'] as String,
    durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
  );

  final int id;
  final String mediaType; // "image" | "video"
  final String contentType;
  final String url;
  final double? durationSeconds;

  bool get isVideo => mediaType == 'video';
}

/// One paragraph of text or one attached image/video, in the post's display
/// order — a post is an ordered sequence of these (see the backend's
/// `PostBlock`), article-style, rather than a text blob with a media strip
/// bolted on the end.
sealed class PostBlock {
  factory PostBlock.fromJson(Map<String, dynamic> json) => switch (json['type']) {
    'media' => PostMediaBlock(PostMedia.fromJson(json['media'] as Map<String, dynamic>)),
    _ => PostTextBlock(json['text'] as String),
  };
}

class PostTextBlock implements PostBlock {
  PostTextBlock(this.text);
  final String text;
}

class PostMediaBlock implements PostBlock {
  PostMediaBlock(this.media);
  final PostMedia media;
}

class Post {
  Post({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.blocks,
    required this.isAnonymous,
    required this.author,
    required this.forwardedCount,
    required this.droppedCount,
    required this.subscriptionKind,
    required this.created,
  });

  factory Post.fromJson(Map<String, dynamic> json) => Post(
    id: json['id'] as int,
    channelId: json['channel_id'] as int,
    channelName: json['channel_name'] as String,
    blocks: (json['blocks'] as List<dynamic>)
        .map((b) => PostBlock.fromJson(b as Map<String, dynamic>))
        .toList(),
    isAnonymous: json['is_anonymous'] as bool,
    author: PostAuthor.fromJson(json['author'] as Map<String, dynamic>),
    forwardedCount: json['forwarded_count'] as int,
    droppedCount: json['dropped_count'] as int,
    subscriptionKind: json['subscription_kind'] as String?,
    created: DateTime.parse(json['created'] as String),
  );

  final int id;
  final int channelId;
  final String channelName;
  final List<PostBlock> blocks;
  final bool isAnonymous;
  final PostAuthor author;
  final int forwardedCount;
  final int droppedCount;
  // Snapshot of the author's subscription at the moment this post was created
  // (e.g. "supporter"), or null. Fixed forever — doesn't reflect their current
  // subscription status.
  final String? subscriptionKind;
  final DateTime created;

  /// All the post's text blocks, joined into one string — used for the feed
  /// card's 2-line preview and for history search/highlighting
  /// (`post_history_screen.dart`). The full, in-order block-by-block layout is
  /// only rendered in the detail sheet.
  String get previewText =>
      blocks.whereType<PostTextBlock>().map((b) => b.text).join(' ');

  /// Every attached image/video, in the order its block appears — the
  /// equivalent of the old flat `media` list, for call sites (feed card
  /// thumbnail, "+N" badge) that just need "the attachments", not their
  /// position among the text.
  List<PostMedia> get mediaItems =>
      blocks.whereType<PostMediaBlock>().map((b) => b.media).toList();

  bool get hasMedia => mediaItems.isNotEmpty;

  /// Whether this post should get the supporter visual treatment.
  bool get isSupporterPost => subscriptionKind == 'supporter';

  /// Fraction of the prototype's 24h review-deadline window that has
  /// elapsed since creation — a purely client-side, display-only visual.
  double get deadlineProgress {
    const window = Duration(hours: 24);
    final elapsed = DateTime.now().toUtc().difference(created.toUtc());
    return (elapsed.inSeconds / window.inSeconds).clamp(0.0, 1.0);
  }

  Duration get timeRemaining {
    const window = Duration(hours: 24);
    final elapsed = DateTime.now().toUtc().difference(created.toUtc());
    final remaining = window - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Compact relative age (e.g. "3h", "2d") — deliberately not an absolute
  /// timestamp: nothing else in this app formats calendar dates, and a
  /// relative label is what a 24h-lifetime feed post actually needs.
  String get timeAgo {
    final diff = DateTime.now().toUtc().difference(created.toUtc());
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
