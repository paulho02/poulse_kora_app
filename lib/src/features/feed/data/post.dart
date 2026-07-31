class PostAuthor {
  PostAuthor({required this.id, required this.username});

  factory PostAuthor.fromJson(Map<String, dynamic> json) => PostAuthor(
    id: json['id'] as String?,
    username: json['username'] as String?,
  );

  final String? id;
  final String? username;
}

class Post {
  Post({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.text,
    required this.hasImage,
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
    text: json['text'] as String,
    hasImage: json['has_image'] as bool,
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
  final String text;
  final bool hasImage;
  final bool isAnonymous;
  final PostAuthor author;
  final int forwardedCount;
  final int droppedCount;
  // Snapshot of the author's subscription at the moment this post was created
  // (e.g. "supporter"), or null. Fixed forever — doesn't reflect their current
  // subscription status.
  final String? subscriptionKind;
  final DateTime created;

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
