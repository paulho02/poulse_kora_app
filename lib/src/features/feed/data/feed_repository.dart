import 'package:dio/dio.dart';

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

/// Thrown when the backend rejects a request with a structured `detail`
/// error body (e.g. `not_subscribed`, `review_gate_locked`).
class RelayApiException implements Exception {
  RelayApiException(this.statusCode, this.error, this.detail);

  final int statusCode;
  final String error;
  final Map<String, dynamic> detail;

  @override
  String toString() => 'RelayApiException($statusCode, $error)';

  static RelayApiException fromDioException(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic> &&
        data['detail'] is Map<String, dynamic>) {
      final detail = data['detail'] as Map<String, dynamic>;
      return RelayApiException(
        e.response?.statusCode ?? 0,
        detail['error'] as String? ?? 'unknown',
        detail,
      );
    }
    return RelayApiException(e.response?.statusCode ?? 0, 'unknown', {});
  }
}

/// Shared between the Feed and Create-Post features — both operate on the
/// same `/posts` resource.
class FeedRepository {
  FeedRepository(this._dio);

  final Dio _dio;

  Future<List<Post>> fetchFeed({
    int? channelId,
    int skip = 0,
    int limit = 20,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/posts/feed',
      queryParameters: {'channel_id': ?channelId, 'skip': skip, 'limit': limit},
    );
    return response.data!
        .map((json) => Post.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<CreatePostResult> createPost({
    required int channelId,
    required String text,
    bool hasImage = false,
    bool isAnonymous = false,
  }) async {
    try {
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
    } on DioException catch (e) {
      throw RelayApiException.fromDioException(e);
    }
  }

  Future<PostReviewResult> reviewPost(int postId, String kind) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/posts/$postId/review',
        data: {'kind': kind},
      );
      return PostReviewResult.fromJson(response.data!);
    } on DioException catch (e) {
      throw RelayApiException.fromDioException(e);
    }
  }
}
