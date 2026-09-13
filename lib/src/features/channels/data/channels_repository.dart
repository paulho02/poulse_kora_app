import 'package:dio/dio.dart';

import '../../../core/cache/cached.dart';
import '../../../core/cache/cached_fetch.dart';
import '../../../core/cache/json_cache.dart';
import 'channel.dart';

class ChannelsRepository {
  ChannelsRepository(this._dio, this._cache);

  final Dio _dio;
  final JsonCache _cache;

  /// Only the unfiltered list is cached. A search is a live question about the
  /// full catalogue, and answering it from a stale local subset would quietly
  /// hide channels that do exist.
  Future<Cached<List<Channel>>> fetchChannels({String? query}) {
    final isSearch = query != null && query.isNotEmpty;
    return fetchCached<List<Channel>>(
      cache: _cache,
      key: isSearch ? '${CacheKeys.channels}:search' : CacheKeys.channels,
      fetchJson: () async {
        final response = await _dio.get<List<dynamic>>(
          '/channels',
          queryParameters: {if (isSearch) 'q': query},
        );
        return response.data!;
      },
      parse: (json) => (json as List<dynamic>)
          .map((e) => Channel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// The exact price for one (channel, language) route — see [PostPrice].
  ///
  /// Deliberately **not** cached. It is a quote the backend guarantees for the
  /// current price window and nothing longer, so serving a stale one offline
  /// would show a number the next publish would not honour. The composer treats
  /// a failure as "price unknown" and falls back to the channel's range, which
  /// is the honest answer when we cannot ask.
  Future<PostPrice> fetchPostPrice({
    required int channelId,
    required String language,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/posts/price',
      queryParameters: {'channel_id': channelId, 'language': language},
    );
    return PostPrice.fromJson(response.data!);
  }

  Future<Channel> subscribe(int channelId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/channels/$channelId/subscribe',
    );
    return Channel.fromJson(response.data!);
  }

  Future<Channel> unsubscribe(int channelId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/channels/$channelId/unsubscribe',
    );
    return Channel.fromJson(response.data!);
  }
}
