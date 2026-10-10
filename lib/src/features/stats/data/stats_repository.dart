import 'package:dio/dio.dart';

import '../../../core/cache/cached.dart';
import '../../../core/cache/cached_fetch.dart';
import '../../../core/cache/json_cache.dart';
import '../../feed/data/post.dart';
import 'post_stats.dart';
import 'user_stats.dart';

class StatsRepository {
  StatsRepository(this._dio, this._cache);

  final Dio _dio;
  final JsonCache _cache;

  Future<Cached<UserStats>> fetchStats() {
    return fetchCached<UserStats>(
      cache: _cache,
      key: CacheKeys.userStats,
      fetchJson: () async {
        final response = await _dio.get<Map<String, dynamic>>('/stats/me');
        return response.data!;
      },
      parse: (json) => UserStats.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<Cached<List<OwnPostViews>>> fetchOwnPostViews() {
    return fetchCached<List<OwnPostViews>>(
      cache: _cache,
      key: CacheKeys.ownPostViews,
      fetchJson: () async {
        final response = await _dio.get<List<dynamic>>('/stats/posts');
        return response.data!;
      },
      parse: (json) => (json as List<dynamic>)
          .map((j) => OwnPostViews.fromJson(j as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<Cached<List<Post>>> fetchTrendingPosts() {
    return fetchCached<List<Post>>(
      cache: _cache,
      key: CacheKeys.trendingPosts,
      fetchJson: () async {
        final response = await _dio.get<List<dynamic>>('/stats/trending');
        return response.data!;
      },
      parse: (json) => (json as List<dynamic>)
          .map((j) => Post.fromJson(j as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<Cached<List<TrendingChannel>>> fetchTrendingChannels() {
    return fetchCached<List<TrendingChannel>>(
      cache: _cache,
      key: CacheKeys.trendingChannels,
      fetchJson: () async {
        final response = await _dio.get<List<dynamic>>(
          '/stats/trending/channels',
        );
        return response.data!;
      },
      parse: (json) => (json as List<dynamic>)
          .map((j) => TrendingChannel.fromJson(j as Map<String, dynamic>))
          .toList(),
    );
  }
}
