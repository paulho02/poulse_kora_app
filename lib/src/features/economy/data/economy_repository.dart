import 'package:dio/dio.dart';

import '../../../core/cache/cached.dart';
import '../../../core/cache/cached_fetch.dart';
import '../../../core/cache/json_cache.dart';
import 'economy.dart';

class EconomyRepository {
  EconomyRepository(this._dio, this._cache);

  final Dio _dio;
  final JsonCache _cache;

  /// GET /posts/economy — current token balance and live post price.
  ///
  /// Cached so the status bar doesn't go blank offline, but note the price is a
  /// function of live operation-queue congestion (`compute_price` server-side),
  /// so a cached price is an indication, not a quote. The status bar labels it as
  /// stale rather than presenting it as current.
  Future<Cached<Economy>> fetchEconomy() {
    return fetchCached<Economy>(
      cache: _cache,
      key: CacheKeys.economy,
      fetchJson: () async {
        final response = await _dio.get<Map<String, dynamic>>('/posts/economy');
        return response.data!;
      },
      parse: (json) => Economy.fromJson(json as Map<String, dynamic>),
    );
  }
}
