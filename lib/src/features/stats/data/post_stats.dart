import '../../feed/data/post.dart';

/// One of the viewer's own recent posts and how many people have reviewed it
/// (`GET /stats/posts`).
///
/// [viewCount] is forwards + drops as one number — the server never sends the
/// split, so the author learns how far the post got rather than how it was
/// judged. A review is also the only "view" the backend can count: there is no
/// delivery counter.
class OwnPostViews {
  OwnPostViews({required this.post, required this.viewCount});

  factory OwnPostViews.fromJson(Map<String, dynamic> json) => OwnPostViews(
    post: Post.fromJson(json['post'] as Map<String, dynamic>),
    viewCount: json['view_count'] as int,
  );

  final Post post;
  final int viewCount;
}

/// A channel's top posts in the per-channel trending view
/// (`GET /stats/trending/channels`), best first.
///
/// Like the global list, trending carries only an order, never counts: being
/// listed already says the crowd liked a post, and a number would make it a
/// score to vote along with.
class TrendingChannel {
  TrendingChannel({
    required this.channelId,
    required this.channelName,
    required this.posts,
  });

  factory TrendingChannel.fromJson(Map<String, dynamic> json) =>
      TrendingChannel(
        channelId: json['channel_id'] as int,
        channelName: json['channel_name'] as String,
        posts: (json['posts'] as List<dynamic>)
            .map((j) => Post.fromJson(j as Map<String, dynamic>))
            .toList(),
      );

  final int channelId;
  final String channelName;
  final List<Post> posts;
}
