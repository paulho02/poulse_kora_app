import 'package:dio/dio.dart';

import '../../../core/cache/cached.dart';
import '../../../core/cache/cached_fetch.dart';
import '../../../core/cache/json_cache.dart';
import 'global_stats.dart';
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

  Future<Cached<GlobalStats>> fetchGlobalStats() {
    return fetchCached<GlobalStats>(
      cache: _cache,
      key: CacheKeys.globalStats,
      fetchJson: () async {
        final response = await _dio.get<Map<String, dynamic>>('/stats/global');
        return response.data!;
      },
      parse: (json) => GlobalStats.fromJson(json as Map<String, dynamic>),
    );
  }
}
