import '../../feed/data/post.dart';

/// A post paired with the viewer's own review of it — one row per entry in
/// the "My Reviews" history, ordered by [reviewedAt] (the review), not
/// [Post.created] (the post).
class ReviewedPost {
  ReviewedPost({
    required this.post,
    required this.kind,
    required this.reviewedAt,
    this.gifted = false,
  });

  factory ReviewedPost.fromJson(Map<String, dynamic> json) => ReviewedPost(
    post: Post.fromJson(json['post'] as Map<String, dynamic>),
    kind: json['kind'] as String,
    reviewedAt: DateTime.parse(json['reviewed_at'] as String),
    gifted: json['gifted'] as bool? ?? false,
  );

  final Post post;
  final String kind;
  final DateTime reviewedAt;

  /// A forward whose earned token went to the author.
  final bool gifted;

  bool get isForward => kind == 'forward';
}
