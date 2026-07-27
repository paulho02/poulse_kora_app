import 'package:dio/dio.dart';

import '../../../core/cache/cached.dart';
import '../../../core/cache/cached_fetch.dart';
import '../../../core/cache/json_cache.dart';
import 'post.dart';

class PostReviewResult {
  PostReviewResult({
    required this.postId,
    required this.kind,
    required this.reviewedCount,
    required this.reviewGate,
    required this.unlocked,
    required this.tokenBalance,
  });

  factory PostReviewResult.fromJson(Map<String, dynamic> json) =>
      PostReviewResult(
        postId: json['post_id'] as int,
        kind: json['kind'] as String,
        reviewedCount: json['reviewed_count'] as int,
        reviewGate: json['review_gate'] as int,
        unlocked: json['unlocked'] as bool,
        tokenBalance: json['token_balance'] as int,
      );

  final int postId;
  final String kind;
  final int reviewedCount;
  final int reviewGate;
  final bool unlocked;

  /// Spendable balance after earning one token for this review.
  final int tokenBalance;
}

/// Result of publishing an original post: the created post plus what it cost.
class CreatePostResult {
  CreatePostResult({
    required this.post,
    required this.price,
    required this.tokenBalance,
  });

  factory CreatePostResult.fromJson(Map<String, dynamic> json) =>
      CreatePostResult(
        post: Post.fromJson(json['post'] as Map<String, dynamic>),
        price: json['price'] as int,
        tokenBalance: json['token_balance'] as int,
      );

  final Post post;
  final int price;

  /// Spendable balance after paying the post's price.
  final int tokenBalance;
}

/// Shared between the Feed and Create-Post features — both operate on the
/// same `/posts` resource.
class FeedRepository {
  FeedRepository(this._dio, this._cache);

  final Dio _dio;
  final JsonCache _cache;

  /// Reads fall back to the last cached queue when the backend is unreachable, so
  /// an offline user can still read what they had. Writes below deliberately do
  /// not queue: reviewing is guarded server-side by the Redis queue and posting is
  /// priced at request time, so a deferred replay could fail or overcharge long
  /// after the user believed it succeeded.
  Future<Cached<List<Post>>> fetchFeed({
    int? channelId,
    int skip = 0,
    int limit = 20,
  }) {
    return fetchCached<List<Post>>(
      cache: _cache,
      key: CacheKeys.feed(channelId),
      fetchJson: () async {
        final response = await _dio.get<List<dynamic>>(
          '/posts/feed',
          queryParameters: {
            'channel_id': ?channelId,
            'skip': skip,
            'limit': limit,
          },
        );
        return response.data!;
      },
      parse: (json) => (json as List<dynamic>)
          .map((e) => Post.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<CreatePostResult> createPost({
    required int channelId,
    required String text,
    bool hasImage = false,
    bool isAnonymous = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/posts',
      data: {
        'channel_id': channelId,
        'text': text,
        'has_image': hasImage,
        'is_anonymous': isAnonymous,
      },
    );
    return CreatePostResult.fromJson(response.data!);
  }

  Future<PostReviewResult> reviewPost(int postId, String kind) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/posts/$postId/review',
      data: {'kind': kind},
    );
    return PostReviewResult.fromJson(response.data!);
  }
}
