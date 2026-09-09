import 'dart:typed_data';

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
    required this.width,
    required this.height,
    required this.posterUrl,
    this.localBytes,
  });

  /// An attachment that has not been uploaded yet — the composer's preview
  /// (`create_post/presentation/post_preview.dart`) assembles a [Post] out of
  /// picked files so the *reader's* widgets can draw it, rather than the
  /// composer growing a second copy of the post layout that would drift.
  ///
  /// [width]/[height] are the published *shape*, not a pixel count: the ratio
  /// is all a block is laid out from, and for a video the real pixel size is
  /// the server-side transcode's to decide. There is no [url] and no poster
  /// for the same reason — nothing has been uploaded, so callers must branch
  /// on [isLocal] rather than reach for either.
  factory PostMedia.local({
    required Uint8List bytes,
    required bool isVideo,
    required double aspectRatio,
  }) => PostMedia(
    id: -1,
    mediaType: isVideo ? 'video' : 'image',
    contentType: '',
    url: '',
    durationSeconds: null,
    width: (aspectRatio * 1000).round(),
    height: 1000,
    posterUrl: null,
    localBytes: bytes,
  );

  factory PostMedia.fromJson(Map<String, dynamic> json) => PostMedia(
    id: json['id'] as int,
    mediaType: json['media_type'] as String,
    contentType: json['content_type'] as String,
    url: json['url'] as String,
    durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
    width: json['width'] as int?,
    height: json['height'] as int?,
    posterUrl: json['poster_url'] as String?,
  );

  final int id;
  final String mediaType; // "image" | "video"
  final String contentType;
  final String url;
  final double? durationSeconds;

  /// Pixel size of the stored file, or null for anything uploaded before the
  /// backend started measuring it. Everything published since is one of two
  /// fixed shapes, but old rows are *not* backfilled and may be anything — so
  /// null means "unknown, letterbox it", never "assume the default".
  final int? width;
  final int? height;

  /// A still frame to show in place of an unplayed video. Null for images
  /// (which are their own preview) and for a video whose frame extraction
  /// failed server-side, which is a tolerated outcome rather than an error.
  final String? posterUrl;

  bool get isVideo => mediaType == 'video';

  /// The shape to lay this block out in, or null when it isn't known yet — see
  /// [width]. Callers letterbox rather than guessing, since a wrong guess crops
  /// an old post's photo instead of merely padding it.
  double? get aspectRatio {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  /// The bytes of an attachment that is still local to the composer, or null
  /// for everything that came from the server — which is every post the app
  /// reads. See [PostMedia.local].
  final Uint8List? localBytes;

  bool get isLocal => localBytes != null;

  /// What to fetch to show this item *without* playing it: a photo is its own
  /// preview, a video has a poster frame (when one exists).
  String? get previewUrl => isVideo ? posterUrl : url;
}

/// One paragraph of text or one attached image/video, in the post's display
/// order — a post is an ordered sequence of these (see the backend's
/// `PostBlock`), article-style, rather than a text blob with a media strip
/// bolted on the end.
sealed class PostBlock {
  factory PostBlock.fromJson(Map<String, dynamic> json) =>
      switch (json['type']) {
        'media' => PostMediaBlock(
          PostMedia.fromJson(json['media'] as Map<String, dynamic>),
        ),
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

/// One slot in the review queue: the post that fills it, or a hole where a post
/// used to be.
///
/// The queue lives in the backend's Redis and holds nothing but post ids, so an
/// author erasing their account leaves ids behind in every reader's queue that
/// was holding one (see the backend's `app/core/account_deletion.py`). Rather
/// than scan every queue in the deployment, the backend answers the hole
/// honestly and the reader is given a way to clear the slot.
///
/// A sealed pair rather than a nullable field on [Post]: a vanished post has no
/// channel, no author and no creation time, so anything a [Post] carried for one
/// would be invented — and the compiler makes every renderer say what it does
/// with the case instead of tripping over a null later.
sealed class FeedEntry {
  const FeedEntry();

  factory FeedEntry.fromJson(Map<String, dynamic> json) {
    final post = json['post'] as Map<String, dynamic>?;
    return post == null
        ? MissingPost(json['post_id'] as int)
        : FeedPost(Post.fromJson(post));
  }

  /// The queue slot's post id — the one thing that exists in both cases, and
  /// what every list operation (dedupe, removal, "have I seen this?") keys on.
  int get postId;
}

class FeedPost extends FeedEntry {
  const FeedPost(this.post);

  final Post post;

  @override
  int get postId => post.id;
}

/// A slot whose post has been erased. Nothing can be done with it but dismissed
/// — there is nothing left to read, and nothing to forward.
class MissingPost extends FeedEntry {
  const MissingPost(this.postId);

  @override
  final int postId;
}

class Post {
  Post({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.blocks,
    required this.isAnonymous,
    required this.author,
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
    subscriptionKind: json['subscription_kind'] as String?,
    created: DateTime.parse(json['created'] as String),
  );

  final int id;
  final int channelId;
  final String channelName;
  final List<PostBlock> blocks;
  final bool isAnonymous;
  final PostAuthor author;
  // No forward/drop counts here on purpose: the server withholds how a post has
  // fared until the reader has reviewed it, so it cannot sway the verdict. The
  // numbers arrive once, on PostReviewResult.
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
