import 'package:dio/dio.dart';

import '../../feed/data/post.dart';
import 'reviewed_post.dart';

/// Plain (uncached) paged reads of the current user's post/review history.
///
/// Unlike `FeedRepository`, this doesn't go through `fetchCached` — that
/// helper caches one whole list under a single key, which doesn't fit
/// progressively-paged history. There's no offline fallback here; that's
/// acceptable for a secondary "view your history" screen.
class HistoryRepository {
  HistoryRepository(this._dio);

  final Dio _dio;

  Future<List<Post>> fetchMyPosts({int skip = 0, int limit = 20}) async {
    final response = await _dio.get<List<dynamic>>(
      '/posts/mine',
      queryParameters: {'skip': skip, 'limit': limit},
    );
    return response.data!
        .map((e) => Post.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ReviewedPost>> fetchMyReviews({
    int skip = 0,
    int limit = 20,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/posts/reviewed',
      queryParameters: {'skip': skip, 'limit': limit},
    );
    return response.data!
        .map((e) => ReviewedPost.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
